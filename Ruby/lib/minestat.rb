# minestat.rb - A Minecraft server status checker
# Copyright (C) 2014-2022 Lloyd Dilley
# http://www.dilley.me/
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

require 'base64'
require 'json'
require 'resolv'
require 'socket'
require 'timeout'

##
# Provides a ruby interface for polling Minecraft server status.
class MineStat
  # MineStat version
  VERSION = "2.2.4"
  # Number of values expected from server
  NUM_FIELDS = 6
  # Number of values expected from a 1.8b/1.3 server
  NUM_FIELDS_BETA = 3
  # Maximum number of bytes a varint can be
  MAX_VARINT_SIZE = 5
  # Default TCP port
  DEFAULT_TCP_PORT = 25565
  # Bedrock/Pocket Edition default UDP port
  DEFAULT_BEDROCK_PORT = 19132
  # Default TCP/UDP timeout in seconds
  DEFAULT_TIMEOUT = 5
  # Bedrock/Pocket Edition packet offset in bytes (1 + 8 + 8 + 16 + 2)
  # Unconnected pong (0x1C) = 1 byte
  # Timestamp as a long = 8 bytes
  # Server GUID as a long = 8 bytes
  # Magic number = 16 bytes
  # String ID length = 2 bytes
  BEDROCK_PACKET_OFFSET = 35

  ##
  # Stores constants that represent the results of a server ping
  module Retval
    # The server ping completed successfully
    SUCCESS = 0
    # The server ping failed due to a connection error
    CONNFAIL = -1
    # The server ping failed due to a connection time out
    TIMEOUT = -2
    # The server ping failed for an unknown reason
    UNKNOWN = -3
  end

  ##
  # Stores constants that represent the different kinds of server
  # list pings/requests that a Minecraft server might expect when
  # being polled for status information.
  module Request
    # Try everything
    NONE = -1
    # Server versions 1.8b to 1.3
    BETA = 0
    # Server versions 1.4 to 1.5
    LEGACY = 1
    # Server version 1.6
    EXTENDED = 2
    # Server versions 1.7 to latest
    JSON = 3
    # Bedrock/Pocket Edition
    BEDROCK = 4
  end

  ##
  # Instantiate an instance of MineStat and poll the specified server for information
  def initialize(address, port = DEFAULT_TCP_PORT, timeout = DEFAULT_TIMEOUT, request_type = Request::NONE)
    @address = address    # address of server
    @port = port          # TCP/UDP port of server
    @online               # online or offline?
    @version              # server version
    @mode                 # game mode (Bedrock/Pocket Edition only)
    @motd                 # message of the day
    @stripped_motd        # message of the day without formatting
    @current_players      # current number of players online
    @max_players          # maximum player capacity
    @protocol             # protocol level
    @json_data            # JSON data for 1.7 queries
    @favicon_b64          # base64-encoded favicon possibly contained in JSON 1.7 responses
    @favicon              # decoded favicon data
    @latency              # ping time to server in milliseconds
    @timeout = timeout    # TCP/UDP timeout
    @server               # server socket
    @request_type         # protocol version
    @connection_status    # status of connection ("Success", "Fail", "Timeout", or "Unknown")
    @try_all = false      # try all protocols?

    @try_all = true if request_type == Request::NONE

    begin
      resolver = Resolv::DNS.new
      res = resolver.getresource("_minecraft._tcp.#{@address}", Resolv::DNS::Resource::IN::SRV)
      @address = res.target.to_s # SRV target
      @port = res.port.to_i      # SRV port
    rescue => exception          # primarily catch Resolv::ResolvError
      @address = address
      @port = port
    end

    case request_type
      when Request::BETA
        retval = beta_request()
      when Request::LEGACY
        retval = legacy_request()
      when Request::EXTENDED
        retval = extended_legacy_request()
      when Request::JSON
        retval = json_request()
      when Request::BEDROCK
        retval = bedrock_request()
      else
        # Attempt various ping requests in a particular order. If the
        # connection fails, there is no reason to continue with subsequent
        # requests. Attempts should continue in the event of a timeout
        # however since it may be due to an issue during the handshake.
        # Note: Newer server versions may still respond to older SLP requests.
        # SLP 1.4/1.5
        retval = legacy_request()
        # SLP 1.8b/1.3
        unless retval == Retval::SUCCESS || retval == Retval::CONNFAIL
          retval = beta_request()
        end
        # SLP 1.6
        unless retval == Retval::CONNFAIL
          retval = extended_legacy_request()
        end
        # SLP 1.7
        unless retval == Retval::CONNFAIL
          retval = json_request()
        end
        # Bedrock/Pocket Edition
        unless @online || retval == Retval::SUCCESS
          retval = bedrock_request()
        end
    end
    set_connection_status(retval)
  end

  # Sets connection status
  def set_connection_status(retval)
    @connection_status = "Success" if @online || retval == Retval::SUCCESS
    @connection_status = "Fail" if retval == Retval::CONNFAIL
    @connection_status = "Timeout" if retval == Retval::TIMEOUT
    @connection_status = "Unknown" if retval == Retval::UNKNOWN
  end

  # Strips message of the day formatting characters
  def strip_motd()
    unless @motd['text'] == nil
      @stripped_motd = @motd['text']
    else
      @stripped_motd = @motd
    end
    unless @motd['extra'] == nil
      json_data = @motd['extra']
      unless json_data.nil? || json_data.empty?
        json_data.each do |nested_hash|
          @stripped_motd += nested_hash['text']
        end
      end
    end
    @stripped_motd = @stripped_motd.force_encoding('UTF-8')
    @stripped_motd = @stripped_motd.gsub(/§./, "")
  end

  ##
  # Establishes a connection to the Minecraft server
  def connect()
    begin
      if @request_type == Request::BEDROCK || @request_type == "Bedrock/Pocket Edition"
        @port = DEFAULT_BEDROCK_PORT if @port == DEFAULT_TCP_PORT && @try_all
        start_time = Time.now
        @server = UDPSocket.new
        @server.connect(@address, @port)
      else
        start_time = Time.now
        @server = TCPSocket.new(@address, @port)
      end
      @latency = ((Time.now - start_time) * 1000).round
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return Retval::CONNFAIL
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    return Retval::SUCCESS
  end

  # Populates object fields after connecting
  def parse_data(delimiter, is_beta = false)
    data = nil
    begin
      if @request_type == "Bedrock/Pocket Edition"
        if @server.recv(1, Socket::MSG_PEEK).unpack('C').first == 0x1C # unconnected pong packet
          server_id_len = @server.recv(BEDROCK_PACKET_OFFSET, Socket::MSG_PEEK)[-2..-1].unpack('n').first
          data = @server.recv(BEDROCK_PACKET_OFFSET + server_id_len)[BEDROCK_PACKET_OFFSET..-1]
          @server.close
        else
          @server.close
          return Retval::UNKNOWN
        end
      else # SLP
        if @server.read(1).unpack('C').first == 0xFF # kick packet (255)
          len = @server.read(2).unpack('n').first
          data = @server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
          @server.close
        else
          @server.close
          return Retval::UNKNOWN
        end
      end
    rescue
    #rescue => exception
      #$stderr.puts exception
      return Retval::UNKNOWN
    end

    if data == nil || data.empty?
      return Retval::UNKNOWN
    end

    server_info = data.split(delimiter)
    if is_beta
      if server_info != nil && server_info.length >= NUM_FIELDS_BETA
        @version = ">=1.8b/1.3" # since server does not return version, set it
        @motd = server_info[0]
        strip_motd
        @current_players = server_info[1].to_i
        @max_players = server_info[2].to_i
        @online = true
      else
        return Retval::UNKNOWN
      end
    elsif @request_type == "Bedrock/Pocket Edition"
      if server_info != nil
        @protocol = server_info[2].to_i
        @version = "#{server_info[3]} #{server_info[7]} (#{server_info[0]})"
        @mode = server_info[8]
        @motd = server_info[1]
        strip_motd
        @current_players = server_info[4].to_i
        @max_players = server_info[5].to_i
        @online = true
      else
        return Retval::UNKNOWN
      end
    else # SLP
      if server_info != nil && server_info.length >= NUM_FIELDS
        # server_info[0] contains the section symbol and 1
        @protocol = server_info[1].to_i # contains the protocol version (51 for 1.9 or 78 for 1.6.4 for example)
        @version = server_info[2]
        @motd = server_info[3]
        strip_motd
        @current_players = server_info[4].to_i
        @max_players = server_info[5].to_i
        @online = true
      else
        return Retval::UNKNOWN
      end
    end
    return Retval::SUCCESS
  end

  ##
  # 1.8 beta through 1.3 servers communicate as follows for a ping request:
  # 1. Client sends \xFE (server list ping)
  # 2. Server responds with:
  #   2a. \xFF (kick packet)
  #   2b. data length
  #   2c. 3 fields delimited by \u00A7 (section symbol)
  # The 3 fields, in order, are:
  #   * message of the day
  #   * current players
  #   * max players
  def beta_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake and acquire data
        @server.write("\xFE")
        retval = parse_data("\u00A7", true) # section symbol
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.8b/1.3 (beta)"
      set_connection_status(retval)
    end
    return retval
  end

  ##
  # 1.4 and 1.5 servers communicate as follows for a ping request:
  # 1. Client sends:
  #   1a. \xFE (server list ping)
  #   1b. \x01 (server list ping payload)
  # 2. Server responds with:
  #   2a. \xFF (kick packet)
  #   2b. data length
  #   2c. 6 fields delimited by \x00 (null)
  # The 6 fields, in order, are:
  #   * the section symbol and 1
  #   * protocol version
  #   * server version
  #   * message of the day
  #   * current players
  #   * max players
  #
  # The protocol version corresponds with the server version and can be the
  # same for different server versions.
  def legacy_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake and acquire data
        @server.write("\xFE\x01")
        retval = parse_data("\x00") # null
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.4/1.5 (legacy)"
      set_connection_status(retval)
    end
    return retval
  end

  ##
  # 1.6 servers communicate as follows for a ping request:
  # 1. Client sends:
  #   1a. \xFE (server list ping)
  #   1b. \x01 (server list ping payload)
  #   1c. \xFA (plugin message)
  #   1d. \x00\x0B (11 which is the length of "MC|PingHost")
  #   1e. "MC|PingHost" encoded as a UTF-16BE string
  #   1f. length of remaining data as a short: remote address (encoded as UTF-16BE) + 7
  #   1g. arbitrary 1.6 protocol version (\x4E for example for 78)
  #   1h. length of remote address as a short
  #   1i. remote address encoded as a UTF-16BE string
  #   1j. remote port as an int
  # 2. Server responds with:
  #   2a. \xFF (kick packet)
  #   2b. data length
  #   2c. 6 fields delimited by \x00 (null)
  # The 6 fields, in order, are:
  #   * the section symbol and 1
  #   * protocol version
  #   * server version
  #   * message of the day
  #   * current players
  #   * max players
  #
  # The protocol version corresponds with the server version and can be the
  # same for different server versions.
  def extended_legacy_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake and acquire data
        @server.write("\xFE\x01\xFA")
        @server.write("\x00\x0B") # 11 (length of "MC|PingHost")
        @server.write('MC|PingHost'.encode('UTF-16BE').force_encoding('ASCII-8BIT'))
        @server.write([7 + 2 * @address.length].pack('n'))
        @server.write("\x4E")     # 78 (protocol version of 1.6.4)
        @server.write([@address.length].pack('n'))
        @server.write(@address.encode('UTF-16BE').force_encoding('ASCII-8BIT'))
        @server.write([@port].pack('N'))
        retval = parse_data("\x00") # null
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.6 (extended legacy)"
      set_connection_status(retval)
    end
    return retval
  end

  ##
  # 1.7 to current servers communicate as follows for a ping request:
  # 1. Client sends:
  #   1a. \x00 (handshake packet containing the fields specified below)
  #   1b. \x00 (request)
  # The handshake packet contains the following fields respectively:
  #     1. protocol version as a varint (\x00 suffices)
  #     2. remote address as a string
  #     3. remote port as an unsigned short
  #     4. state as a varint (should be 1 for status)
  # 2. Server responds with:
  #   2a. \x00 (JSON response)
  # An example JSON string contains:
  # {'players': {'max': 20, 'online': 0},
  # 'version': {'protocol': 404, 'name': '1.13.2'},
  # 'description': {'text': 'A Minecraft Server'}}
  def json_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake
        payload = "\x00\x00"
        payload += [@address.length].pack('c') << @address
        payload += [@port].pack('n')
        payload += "\x01"
        payload = [payload.length].pack('c') << payload
        @server.write(payload)
        @server.write("\x01\x00")
        @server.flush

        # Acquire data
        _total_len = unpack_varint
        return Retval::UNKNOWN if unpack_varint != 0
        json_len = unpack_varint
        json_data = recv_json(json_len)
        @server.close

        # Parse data
        json_data = JSON.parse(json_data)
        @json_data = json_data
        @protocol = json_data['version']['protocol'].to_i
        @version = json_data['version']['name']
        @motd = json_data['description']
        strip_motd
        @current_players = json_data['players']['online'].to_i
        @max_players = json_data['players']['max'].to_i
        @favicon_b64 = json_data['favicon']
        if !@favicon_b64.nil? && !@favicon_b64.empty?
          @favicon_b64 = favicon_b64.split("base64,")[1]
          @favicon = Base64.decode64(favicon_b64)
        end
        if !@version.empty? && !@motd.empty? && !@current_players.nil? && !@max_players.nil?
          @online = true
        else
          retval = Retval::UNKNOWN
        end
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue JSON::ParserError
      return Retval::UNKNOWN
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.7 (JSON)"
      set_connection_status(retval)
    end
    return retval
  end

  # Reads JSON data from the socket
  def recv_json(json_len)
    json_data = ""
    begin
      loop do
        remaining = json_len - json_data.length
        data = @server.recv(remaining)
        @server.flush
        json_data += data
        break if json_data.length >= json_len
      end
    rescue => exception
      $stderr.puts exception
    end
    return json_data
  end

  # Returns value of varint type
  def unpack_varint()
    vint = 0
    i = 0
    while i <= MAX_VARINT_SIZE
      data = @server.read(1)
      return 0 if data.nil? || data.empty?
      data = data.ord
      vint |= (data & 0x7F) << 7 * i
      break if (data & 0x80) != 128
      i += 1
    end
    return vint
  end

  ##
  # Bedrock/Pocket Edition servers communicate as follows for an unconnected ping request:
  # 1. Client sends:
  #   1a. \x01 (unconnected ping packet containing the fields specified below)
  #   1b. current time as a long
  #   1c. magic number
  #   1d. client GUID as a long
  # 2. Server responds with:
  #   2a. \x1c (unconnected pong packet containing the follow fields)
  #   2b. current time as a long
  #   2c. server GUID as a long
  #   2d. 16-bit magic number
  #   2e. server ID string length
  #   2f. server ID as a string
  # The fields from the pong response, in order, are:
  #   * edition
  #   * MotD line 1
  #   * protocol version
  #   * version name
  #   * current player count
  #   * maximum player count
  #   * unique server ID
  #   * MotD line 2
  #   * game mode as a string
  #   * game mode as a numeric
  #   * IPv4 port number
  #   * IPv6 port number
  def bedrock_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        @request_type = "Bedrock/Pocket Edition"
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake and acquire data
        payload = "\x01".force_encoding('ASCII-8BIT')                       # unconnected ping
        payload += [Time.now.to_i].pack('L!<').force_encoding('ASCII-8BIT') # current time as a long
        payload += "\x00\xFF\xFF\x00\xFE\xFE\xFE\xFE\xFD\xFD\xFD\xFD\x12\x34\x56\x78".force_encoding('ASCII-8BIT') # magic number
        payload += [2].pack('L!<').force_encoding('ASCII-8BIT')             # client GUID as a long
        @server.write(payload)
        @server.flush
        retval = parse_data("\x3B") # semicolon
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      set_connection_status(retval)
    end
    return retval
  end

  # Returns the Minecraft server IP
  attr_reader :address

  # Returns the Minecraft server TCP port
  attr_reader :port

  # Returns a boolean describing whether the server is online or offline
  attr_reader :online

  # Returns the Minecraft version that the server is running
  attr_reader :version

  # Returns the game mode (Bedrock/Pocket Edition only)
  attr_reader :mode

  # Returns the full version of the MotD
  #
  # If you just want the MotD text, use stripped_motd
  attr_reader :motd

  # Returns just the plain text contained within the MotD
  attr_reader :stripped_motd

  # Returns the current player count
  attr_reader :current_players

  # Returns the maximum player count
  attr_reader :max_players

  # Returns the protocol level
  #
  # This is arbitrary and varies by Minecraft version.
  # However, multiple Minecraft versions can share the same
  # protocol level
  attr_reader :protocol

  # Returns the complete JSON response data for queries to Minecraft
  # servers with a version greater than or equal to 1.7
  attr_reader :json_data

  # Returns the base64-encoded favicon from JSON 1.7 queries
  attr_reader :favicon_b64

  # Returns the decoded favicon from JSON 1.7 queries
  attr_reader :favicon

  # Returns the ping time to the server in ms
  attr_reader :latency

  # Returns the protocol version
  attr_reader :request_type

  # Returns the connection status
  attr_reader :connection_status

  # Returns whether or not all ping protocols should be attempted
  attr_reader :try_all
end
