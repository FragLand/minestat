# minestat.rb - A Minecraft server status checker
# Copyright (C) 2014-2023 Lloyd Dilley
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

# @author Lloyd Dilley

# Provides a Ruby interface for polling the status of Minecraft servers
class MineStat
  # MineStat version
  VERSION = "3.0.5"

  # Number of values expected from server
  NUM_FIELDS = 6
  private_constant :NUM_FIELDS

  # Number of values expected from a 1.8b - 1.3 server
  NUM_FIELDS_BETA = 3
  private_constant :NUM_FIELDS_BETA

  # Maximum number of bytes a varint can be
  MAX_VARINT_SIZE = 5
  private_constant :MAX_VARINT_SIZE

  # Default TCP port
  DEFAULT_TCP_PORT = 25565

  # Bedrock/Pocket Edition default UDP port
  DEFAULT_BEDROCK_PORT = 19132

  # Default TCP/UDP timeout in seconds
  DEFAULT_TIMEOUT = 5

  # Bedrock/Pocket Edition packet offset in bytes (1 + 8 + 8 + 16 + 2)
  #   Unconnected pong (0x1C) = 1 byte
  #   Timestamp as a long = 8 bytes
  #   Server GUID as a long = 8 bytes
  #   Magic number = 16 bytes
  #   String ID length = 2 bytes
  BEDROCK_PACKET_OFFSET = 35
  private_constant :BEDROCK_PACKET_OFFSET

  # UT3/GS4 query handshake packet size in bytes (1 + 4 + 13)
  #   Handshake (0x09) = 1 byte
  #   Session ID = 4 bytes
  #   Challenge token = variable null-terminated string up to 13 bytes(?)
  QUERY_HANDSHAKE_SIZE = 18
  private_constant :QUERY_HANDSHAKE_SIZE

  # UT3/GS4 query handshake packet offset for challenge token in bytes (1 + 4)
  #  Handshake (0x09) = 1 byte
  #  Session ID = 4 bytes
  QUERY_HANDSHAKE_OFFSET = 5
  private_constant :QUERY_HANDSHAKE_OFFSET

  # UT3/GS4 query full stat packet offset in bytes (1 + 4 + 11)
  #   Stat (0x00) = 1 byte
  #   Session ID = 4 bytes
  #   Padding = 11 bytes
  QUERY_STAT_OFFSET = 16
  private_constant :QUERY_STAT_OFFSET

  # These constants represent the result of a server request
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

  # These constants represent the various protocols used when requesting server data
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

    # Unreal Tournament 3/GameSpy 4 query
    QUERY = 5

    # SLP only
    # @since 3.0.1
    SLP = 6
  end

  # Instantiates a MineStat object and polls the specified server for information
  # @param address [String] Minecraft server address
  # @param port [Integer] Minecraft server TCP or UDP port
  # @param timeout [Integer] TCP/UDP timeout in seconds
  # @param request_type [Request] Protocol used to poll a Minecraft server
  # @param debug [Boolean] Enable or disable error output
  # @return [MineStat] A MineStat object
  # @example Simply connect to an address
  #   ms = MineStat.new("frag.land")
  # @example Connect to an address on a certain TCP or UDP port
  #   ms = MineStat.new("frag.land", 25565)
  # @example Same as above example and additionally includes a timeout in seconds
  #   ms = MineStat.new("frag.land", 25565, 3)
  # @example Same as above example and additionally includes an explicit protocol to use
  #   ms = MineStat.new("frag.land", 25565, 3, MineStat::Request::QUERY)
  # @example Connect to a Bedrock server and enable debug mode
  #   ms = MineStat.new("minecraft.frag.land", 19132, 3, MineStat::Request::BEDROCK, true)
  # @example Attempt all SLP protocols, disable debug mode, and disable DNS SRV resolution
  #   ms = MineStat.new("minecraft.frag.land", 25565, 3, MineStat::Request::SLP, false, false)
  def initialize(address, port = DEFAULT_TCP_PORT, timeout = DEFAULT_TIMEOUT, request_type = Request::NONE, debug = false, srv_enabled = true)
    @address = address         # address of server
    @port = port               # TCP/UDP port of server
    @srv_address               # server address from DNS SRV record
    @srv_port                  # server TCP port from DNS SRV record
    @online                    # online or offline?
    @version                   # server version
    @mode                      # game mode (Bedrock/Pocket Edition only)
    @motd                      # message of the day
    @stripped_motd             # message of the day without formatting
    @current_players           # current number of players online
    @max_players               # maximum player capacity
    @player_list               # list of players (UT3/GS4 query only)
    @plugin_list               # list of plugins (UT3/GS4 query only)
    @protocol                  # protocol level
    @json_data                 # JSON data for 1.7 queries
    @favicon_b64               # base64-encoded favicon possibly contained in JSON 1.7 responses
    @favicon                   # decoded favicon data
    @latency                   # ping time to server in milliseconds
    @timeout = timeout         # TCP/UDP timeout
    @server                    # server socket
    @request_type              # protocol version
    @connection_status         # status of connection ("Success", "Fail", "Timeout", or "Unknown")
    @try_all = false           # try all protocols?
    @debug = debug             # debug mode
    @srv_enabled = srv_enabled # enable SRV resolution?
    @srv_succeeded = false     # SRV resolution successful?

    @try_all = true if request_type == Request::NONE
    @srv_succeeded = resolve_srv() if @srv_enabled
    set_connection_status(attempt_protocols(request_type))
  end

  # Attempts to resolve DNS SRV records
  # @return [Boolean] Whether or not SRV resolution was successful
  # @since 2.3.0
  def resolve_srv()
    begin
      resolver = Resolv::DNS.new
      res = resolver.getresource("_minecraft._tcp.#{@address}", Resolv::DNS::Resource::IN::SRV)
      @srv_address = res.target.to_s # SRV target
      @srv_port = res.port.to_i      # SRV port
    rescue => exception              # primarily catch Resolv::ResolvError and revert if unable to resolve SRV record(s)
      $stderr.puts "resolve_srv(): #{exception}" if @debug
      return false
    end
    return true
  end
  private :resolve_srv

  # Attempts the use of various protocols
  # @param request_type [Request] Protocol used to poll a Minecraft server
  # @return [Retval] Return value
  def attempt_protocols(request_type)
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
      when Request::QUERY
        retval = query_request()
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
        return retval if request_type == Request::SLP
        # Bedrock/Pocket Edition
        unless @online || retval == Retval::SUCCESS
          retval = bedrock_request()
        end
        # UT3/GS4 query
        unless @online || retval == Retval::SUCCESS
          retval = query_request()
        end
    end
    return retval
  end
  private :attempt_protocols

  # Sets connection status
  # @param retval [Retval] Return value
  def set_connection_status(retval)
    @connection_status = "Success" if @online || retval == Retval::SUCCESS
    @connection_status = "Fail" if retval == Retval::CONNFAIL
    @connection_status = "Timeout" if retval == Retval::TIMEOUT
    @connection_status = "Unknown" if retval == Retval::UNKNOWN
  end
  private :set_connection_status

  # Strips message of the day formatting characters
  def strip_motd(raw_motd)
    @stripped_motd = raw_motd if raw_motd.is_a?(String)

    if raw_motd.is_a?(Hash)
      @stripped_motd = raw_motd['text'] unless raw_motd['text'].nil?

      unless raw_motd['extra'].nil?
        raw_motd['extra'].each do |nested_hash|
          @stripped_motd += strip_motd(nested_hash)
        end
      end
    end

    @stripped_motd = @stripped_motd.force_encoding('UTF-8')
    @stripped_motd = @stripped_motd.gsub(/§./, "")
  end
  private :strip_motd

  # Establishes a connection to the Minecraft server
  def connect()
    begin
      if @request_type == Request::BEDROCK || @request_type == "Bedrock/Pocket Edition" || @request_type == "UT3/GS4 Query"
        @port = DEFAULT_BEDROCK_PORT if @port == DEFAULT_TCP_PORT && @request_type != "UT3/GS4 Query" && @try_all
        start_time = Time.now
        @server = UDPSocket.new
        @server.connect(@address, @port)
      else
        start_time = Time.now
        if @srv_enabled && @srv_succeeded
          @server = TCPSocket.new(@srv_address, @srv_port)
        else
          @server = TCPSocket.new(@address, @port)
        end
      end
      @latency = ((Time.now - start_time) * 1000).round
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      $stderr.puts "connect(): Host unreachable or connection refused" if @debug
      return Retval::CONNFAIL
    rescue => exception
      $stderr.puts "connect(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    return Retval::SUCCESS
  end
  private :connect

  # Validates server response based on beginning of the packet
  # @return [String, Retval] Raw data received from a Minecraft server and the return value
  def check_response()
    data = nil
    retval = nil
    begin
      if @request_type == "Bedrock/Pocket Edition"
        if @server.recv(1, Socket::MSG_PEEK).unpack('C').first == 0x1C # unconnected pong packet
          server_id_len = @server.recv(BEDROCK_PACKET_OFFSET, Socket::MSG_PEEK)[-2..-1].unpack('n').first
          data = @server.recv(BEDROCK_PACKET_OFFSET + server_id_len)[BEDROCK_PACKET_OFFSET..-1]
          @server.close
        else
          @server.close
          retval = Retval::UNKNOWN
        end
      elsif @request_type == "UT3/GS4 Query"
        if @server.recv(1, Socket::MSG_PEEK).unpack('C').first == 0x00 # stat packet
          data = @server.recv(4096)[QUERY_STAT_OFFSET..-1]
          @server.close
        else
          @server.close
          retval = Retval::UNKNOWN
        end
      else # SLP
        if @server.read(1).unpack('C').first == 0xFF # kick packet (255)
          len = @server.read(2).unpack('n').first
          data = @server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
          @server.close
        else
          @server.close
          retval = Retval::UNKNOWN
        end
      end
    rescue => exception
      $stderr.puts "check_response(): #{exception}" if @debug
      return nil, Retval::UNKNOWN
    end
    retval = Retval::UNKNOWN if data == nil || data.empty?
    return data, retval
  end
  private :check_response

  # Populates object fields after retrieving data from a Minecraft server
  # @param delimiter [String] Delimiter used to split a string into an array
  # @param is_beta [Boolean] Whether or not the Minecraft server is using version 1.8b to 1.3
  def parse_data(delimiter, is_beta = false)
    data, retval = check_response()
    return retval if retval == Retval::UNKNOWN

    server_info = nil
    if @request_type == "UT3/GS4 Query"
      server_info = data.split("\x00\x00\x01player_\x00\x00")
    else
      server_info = data.split(delimiter)
    end
    if is_beta
      if server_info != nil && server_info.length >= NUM_FIELDS_BETA
        @version = ">=1.8b/1.3" # since server does not return version, set it
        @motd = server_info[0]
        strip_motd(@motd)
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
        strip_motd(@motd)
        @current_players = server_info[4].to_i
        @max_players = server_info[5].to_i
        @online = true
      else
        return Retval::UNKNOWN
      end
    elsif @request_type == "UT3/GS4 Query"
      if server_info != nil
        @player_list = server_info[1].split(delimiter) unless server_info[1].nil? || server_info[1].empty?
        server_info = Hash[*server_info[0].split(delimiter).flatten(1)]
        @version = server_info["version"]
        @motd = server_info["hostname"]
        strip_motd(@motd)
        @current_players = server_info["numplayers"].to_i
        @max_players = server_info["maxplayers"].to_i
        unless server_info["plugins"].nil? || server_info["plugins"].empty?
          # Vanilla servers do not send a list of plugins.
          # Bukkit and derivatives send plugins in the form: Paper on 1.19.3-R0.1-SNAPSHOT: Essentials 2.19.7; EssentialsChat 2.19.7
          @plugin_list = server_info["plugins"].split(':')
          @plugin_list = @plugin_list[1].split(';').collect(&:strip) if @plugin_list.size > 1
        end
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
        strip_motd(@motd)
        @current_players = server_info[4].to_i
        @max_players = server_info[5].to_i
        @online = true
      else
        return Retval::UNKNOWN
      end
    end
    return Retval::SUCCESS
  end
  private :parse_data

  # 1.8b - 1.3 (SLP request)
  # @note
  #   1. Client sends 0xFE (server list ping)
  #   2. Server responds with:
  #     2a. 0xFF (kick packet)
  #     2b. data length
  #     2c. 3 fields delimited by \u00A7 (section symbol)
  #   The 3 fields, in order, are:
  #     * message of the day
  #     * current players
  #     * max players
  # @return [Retval] Return value
  # @since 0.2.1
  # @see https://wiki.vg/Server_List_Ping#Beta_1.8_to_1.3
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
      $stderr.puts "beta_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts "beta_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.8b/1.3 (beta)"
      set_connection_status(retval)
    end
    return retval
  end
  private :beta_request

  # 1.4 and 1.5 (SLP request)
  # @note
  #   1. Client sends:
  #     1a. 0xFE (server list ping)
  #     1b. 0x01 (server list ping payload)
  #   2. Server responds with:
  #     2a. 0xFF (kick packet)
  #     2b. data length
  #     2c. 6 fields delimited by 0x00 (null)
  #   The 6 fields, in order, are:
  #     * the section symbol and 1
  #     * protocol version
  #     * server version
  #     * message of the day
  #     * current players
  #     * max players
  #
  #   The protocol version corresponds with the server version and can be the
  #   same for different server versions.
  # @return [Retval] Return value
  # @see https://wiki.vg/Server_List_Ping#1.4_to_1.5
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
      $stderr.puts "legacy_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts "legacy_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.4/1.5 (legacy)"
      set_connection_status(retval)
    end
    return retval
  end
  private :legacy_request

  # 1.6 (SLP request)
  # @note
  #   1. Client sends:
  #     1a. 0xFE (server list ping)
  #     1b. 0x01 (server list ping payload)
  #     1c. 0xFA (plugin message)
  #     1d. 0x00 0x0B (11 which is the length of "MC|PingHost")
  #     1e. "MC|PingHost" encoded as a UTF-16BE string
  #     1f. length of remaining data as a short: remote address (encoded as UTF-16BE) + 7
  #     1g. arbitrary 1.6 protocol version (0x4E for example for 78)
  #     1h. length of remote address as a short
  #     1i. remote address encoded as a UTF-16BE string
  #     1j. remote port as an int
  #   2. Server responds with:
  #     2a. 0xFF (kick packet)
  #     2b. data length
  #     2c. 6 fields delimited by 0x00 (null)
  #   The 6 fields, in order, are:
  #     * the section symbol and 1
  #     * protocol version
  #     * server version
  #     * message of the day
  #     * current players
  #     * max players
  #
  # The protocol version corresponds with the server version and can be the
  # same for different server versions.
  # @return [Retval] Return value
  # @since 0.2.0
  # @see https://wiki.vg/Server_List_Ping#1.6
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
      $stderr.puts "extended_legacy_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts "extended_legacy_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.6 (extended legacy)"
      set_connection_status(retval)
    end
    return retval
  end
  private :extended_legacy_request

  # >=1.7 (SLP request)
  # @note
  #   1. Client sends:
  #     1a. 0x00 (handshake packet containing the fields specified below)
  #     1b. 0x00 (request)
  #   The handshake packet contains the following fields respectively:
  #       1. protocol version as a varint (0x00 suffices)
  #       2. remote address as a string
  #       3. remote port as an unsigned short
  #       4. state as a varint (should be 1 for status)
  #   2. Server responds with:
  #     2a. 0x00 (JSON response)
  #   An example JSON string contains:
  #     {'players': {'max': 20, 'online': 0},
  #     'version': {'protocol': 404, 'name': '1.13.2'},
  #     'description': {'text': 'A Minecraft Server'}}
  # @return [Retval] Return value
  # @since 0.3.0
  # @see https://wiki.vg/Server_List_Ping#Current_.281.7.2B.29
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
        strip_motd(@motd)
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
      $stderr.puts "json_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue JSON::ParserError
      $stderr.puts "json_request(): JSON parse error" if @debug
      return Retval::UNKNOWN
    rescue => exception
      $stderr.puts "json_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      @request_type = "SLP 1.7 (JSON)"
      set_connection_status(retval)
    end
    return retval
  end
  private :json_request

  # Reads JSON data from the socket
  # @param json_len [Integer] Length of the JSON data received from the Minecraft server
  # @return [String] JSON data received from the Mincraft server
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
      $stderr.puts "recv_json(): #{exception}" if @debug
    end
    return json_data
  end
  private :recv_json

  # Decodes the value of a varint type
  # @return [Integer] Value decoded from a varint type
  # @see https://en.wikipedia.org/wiki/LEB128
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
  private :unpack_varint

  # Bedrock/Pocket Edition (unconnected ping request)
  # @note
  #   1. Client sends:
  #     1a. 0x01 (unconnected ping packet containing the fields specified below)
  #     1b. current time as a long
  #     1c. magic number
  #     1d. client GUID as a long
  #   2. Server responds with:
  #     2a. 0x1c (unconnected pong packet containing the follow fields)
  #     2b. current time as a long
  #     2c. server GUID as a long
  #     2d. 16-bit magic number
  #     2e. server ID string length
  #     2f. server ID as a string
  #   The fields from the pong response, in order, are:
  #     * edition
  #     * MotD line 1
  #     * protocol version
  #     * version name
  #     * current player count
  #     * maximum player count
  #     * unique server ID
  #     * MotD line 2
  #     * game mode as a string
  #     * game mode as a numeric
  #     * IPv4 port number
  #     * IPv6 port number
  # @return [Retval] Return value
  # @since 2.2.0
  # @see https://wiki.vg/Raknet_Protocol#Unconnected_Ping
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
      $stderr.puts "bedrock_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts "bedrock_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      set_connection_status(retval)
    end
    return retval
  end
  private :bedrock_request

  # Unreal Tournament 3/GameSpy 4 (UT3/GS4) query protocol
  # @note
  #   1. Client sends:
  #     1a. 0xFE 0xFD (query identifier)
  #     1b. 0x09 (handshake)
  #     1c. arbitrary session ID (4 bytes)
  #   2. Server responds with:
  #     2a. 0x09 (handshake)
  #     2b. session ID (4 bytes)
  #     2c. challenge token (variable null-terminated string)
  #   3. Client sends:
  #     3a. 0xFE 0xFD (query identifier)
  #     3b. 0x00 (stat)
  #     3c. arbitrary session ID (4 bytes)
  #     3d. challenge token (32-bit integer in network byte order)
  #     3e. padding (4 bytes -- 0x00 0x00 0x00 0x00); omit padding for basic stat (which does not supply the version)
  #   4. Server responds with:
  #     4a. 0x00 (stat)
  #     4b. session ID (4 bytes)
  #     4c. padding (11 bytes)
  #     4e. key/value pairs of multiple null-terminated strings containing the fields below:
  #         hostname, game type, game ID, version, plugin list, map, current players, max players, port, address
  #     4f. padding (10 bytes)
  #     4g. list of null-terminated strings containing player names
  # @return [Retval] Return value
  # @since 3.0.0
  # @see https://wiki.vg/Query
  def query_request()
    retval = nil
    begin
      Timeout::timeout(@timeout) do
        @request_type = "UT3/GS4 Query"
        retval = connect()
        return retval unless retval == Retval::SUCCESS
        payload = "\xFE\xFD\x09\x0B\x03\x03\x0F"
        @server.write(payload)
        @server.flush
        if @server.recv(1, Socket::MSG_PEEK).unpack('C').first == 0x09 # query handshake packet
          # Session ID generated by the server is not used -- use a static session ID instead such as 0x0B 0x03 0x03 0x0F. 
          #session_id = @server.recv(QUERY_HANDSHAKE_OFFSET, Socket::MSG_PEEK)[1..-1].unpack('l>')
          challenge_token = @server.recv(QUERY_HANDSHAKE_SIZE)[QUERY_HANDSHAKE_OFFSET..-1]
          payload = "\xFE\xFD\x00\x0B\x03\x03\x0F".force_encoding('ASCII-8BIT')
          # Use the full stat below by stripping the null terminator from the challenge token and padding the end
          # of the payload with "\x00\x00\x00\x00". The basic stat response does not include the server version.
          payload += [challenge_token.rstrip.to_i].pack('l>').force_encoding('ASCII-8BIT')
          payload += "\x00\x00\x00\x00".force_encoding('ASCII-8BIT')
          @server.write(payload)
          @server.flush          
        else
          return Retval::UNKNOWN
        end
        retval = parse_data("\x00") # null
      end
    rescue Timeout::Error
      $stderr.puts "query_request(): Connection timed out" if @debug
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts "query_request(): #{exception}" if @debug
      return Retval::UNKNOWN
    end
    if retval == Retval::SUCCESS
      set_connection_status(retval)
    end
    return retval
  end
  private :query_request

  # Address (hostname or IP address) of the Minecraft server
  attr_reader :address

  # Port (TCP or UDP) of the Minecraft server
  attr_reader :port

  # Address of the Minecraft server from a DNS SRV record
  # @since 3.0.1
  attr_reader :srv_address

  # TCP port of the Minecraft server from a DNS SRV record
  # @since 3.0.1
  attr_reader :srv_port

  # Whether or not the Minecraft server is online
  attr_reader :online

  # Minecraft server version
  attr_reader :version

  # Game mode
  # @note Bedrock/Pocket Edition only
  # @since 2.2.0
  attr_reader :mode

  # Full message of the day (MotD)
  # @note If only the plain text MotD is relevant, use {#stripped_motd}
  # @see #stripped_motd
  attr_reader :motd

  # Plain text contained within the message of the day (MotD)
  # @note If the full MotD is desired, use {#motd}
  # @see #motd
  attr_reader :stripped_motd

  # Current player count
  attr_reader :current_players

  # Maximum player limit
  attr_reader :max_players

  # List of players
  # @note UT3/GS4 query only
  # @since 3.0.0
  attr_reader :player_list

  # List of plugins
  # @note UT3/GS4 query only
  # @since 3.0.0
  attr_reader :plugin_list

  # Protocol level
  # @note This is arbitrary and varies by Minecraft version (may also be shared by multiple Minecraft versions)
  attr_reader :protocol

  # Complete JSON response data
  # @note Received using SLP 1.7 (JSON) queries
  # @since 0.3.0
  attr_reader :json_data

  # Base64-encoded favicon
  # @note Received using SLP 1.7 (JSON) queries
  # @since 2.2.2
  attr_reader :favicon_b64

  # Decoded favicon
  # @note Received using SLP 1.7 (JSON) queries
  # @since 2.2.2
  attr_reader :favicon

  # Ping time to the server in milliseconds (ms)
  # @since 0.2.1
  attr_reader :latency

  # TCP/UDP timeout in seconds
  # @since 0.1.2
  attr_accessor :timeout

  # Protocol used to request data from a Minecraft server
  attr_reader :request_type

  # Connection status
  # @since 2.2.2
  attr_reader :connection_status

  # Whether or not all protocols should be attempted
  attr_reader :try_all

  # Whether or not debug mode is enabled
  # @since 3.0.0
  attr_reader :debug

  # Whether or not DNS SRV resolution is enabled
  # @since 3.0.1
  attr_reader :srv_enabled

  # Whether or not DNS SRV resolution was successful
  # @since 3.0.2
  attr_reader :srv_succeeded
end
