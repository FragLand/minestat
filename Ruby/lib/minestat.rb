# minestat.rb - A Minecraft server status checker
# Copyright (C) 2014-2021 Lloyd Dilley
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

require 'json'
require 'socket'
require 'timeout'

##
# Provides a ruby interface for polling Minecraft server status.
class MineStat
  # MineStat version
  VERSION = "2.1.1"
  # Number of values expected from server
  NUM_FIELDS = 6
  # Number of values expected from a 1.8b/1.3 server
  NUM_FIELDS_BETA = 3
  # Maximum number of bytes a varint can be
  MAX_VARINT_SIZE = 5
  # Default TCP port
  DEFAULT_PORT = 25565
  # Default TCP timeout in seconds
  DEFAULT_TIMEOUT = 5

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
  end

  ##
  # Instantiate an instance of MineStat and poll the specified server for information
  def initialize(address, port = DEFAULT_PORT, timeout = DEFAULT_TIMEOUT, request_type = Request::NONE)
    @address = address # address of server
    @port = port       # TCP port of server
    @online            # online or offline?
    @version           # server version
    @motd              # message of the day
    @stripped_motd     # message of the day without formatting
    @current_players   # current number of players online
    @max_players       # maximum player capacity
    @protocol          # protocol level
    @json_data         # JSON data for 1.7 queries
    @latency           # ping time to server in milliseconds
    @timeout = timeout # TCP timeout
    @server            # server socket
    @request_type      # SLP protocol version

    case request_type
      when Request::BETA
        retval = beta_request()
      when Request::LEGACY
        retval = legacy_request()
      when Request::EXTENDED
        retval = extended_legacy_request()
      when Request::JSON
        retval = json_request()
      else
        # Attempt various SLP ping requests in a particular order. If the request
        # succeeds or the connection fails, there is no reason to continue with
        # subsequent requests. Attempts should continue in the event of a timeout
        # however since it may be due to an issue during the handshake.
        # Note: Newer server versions may still respond to older SLP requests.
        # For example, 1.13.2 responds to 1.4/1.5 queries, but not 1.6 queries.
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
    end
    @online = false unless retval == Retval::SUCCESS
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
    @stripped_motd = @stripped_motd.gsub(/§./, "")
  end

  ##
  # Establishes a connection to the Minecraft server
  def connect()
    begin
      start_time = Time.now
      @server = TCPSocket.new(@address, @port)
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
      if @server.read(1).unpack('C').first == 0xFF # kick packet (255)
        len = @server.read(2).unpack('n').first
        data = @server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
        @server.close
      else
        @server.close
        return Retval::UNKNOWN
      end
    rescue => exception
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
    else
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
  # * message of the day
  # * current players
  # * max players
  def beta_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        # Perform handshake and acquire data
        @request_type = "SLP 1.8b/1.3 (beta)"
        @server.write("\xFE")
        retval = parse_data("\u00A7", true) # section symbol
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
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
  # * the section symbol and 1
  # * protocol version
  # * server version
  # * message of the day
  # * current players
  # * max players
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
        @request_type = "SLP 1.4/1.5 (legacy)"
        @server.write("\xFE\x01")
        retval = parse_data("\x00") # null
      end
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
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
  # * the section symbol and 1
  # * protocol version
  # * server version
  # * message of the day
  # * current players
  # * max players
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
        @request_type = "SLP 1.6 (extended legacy)"
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
        @request_type = "SLP 1.7 (JSON)"
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

  # Returns the Minecraft server IP
  attr_reader :address

  # Returns the Minecraft server TCP port
  attr_reader :port

  # Returns a boolean describing whether the server is online or offline
  attr_reader :online

  # Returns the Minecraft version that the server is running
  attr_reader :version

  # Returns the full version of the MOTD
  #
  # If you just want the MOTD text, use stripped_motd
  attr_reader :motd

  # Returns just the plain text contained within the MOTD
  attr_reader :stripped_motd

  # Returns the current player count
  attr_reader :current_players

  # Returns the maximum player count
  attr_reader :max_players

  # Returns the SLP (Server List Ping) protocol level
  #
  # This is arbitrary and varies by Minecraft version.
  # However, multiple Minecraft versions can share the same
  # protocol level
  attr_reader :protocol

  # Returns the complete JSON response data for queries to Minecraft
  # servers with a version greater than or equal to 1.7
  attr_reader :json_data

  # Returns the ping time to the server in ms
  attr_reader :latency

  # Returns the SLP (Server List Ping) protocol version
  attr_reader :request_type
end
