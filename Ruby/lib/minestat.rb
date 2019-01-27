# minestat.rb - A Minecraft server status checker
# Copyright (C) 2014 Lloyd Dilley
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

require 'socket'
require 'timeout'

class MineStat
  NUM_FIELDS = 6       # number of values expected from server
  NUM_FIELDS_BETA = 3  # number of values expected from a 1.8b/1.3 server
  DEFAULT_TIMEOUT = 5  # default TCP timeout in seconds

  module Retval
    SUCCESS = 0
    CONNFAIL = -1
    TIMEOUT = -2
    UNKNOWN = -3
  end

  def initialize(address, port, timeout = DEFAULT_TIMEOUT)
    @address = address
    @port = port
    @online            # online or offline?
    @version           # server version
    @motd              # message of the day
    @current_players   # current number of players online
    @max_players       # maximum player capacity
    @latency           # ping time to server in milliseconds

    # Try the newest protocol first and work down. If the query succeeds or the
    # connection fails, there is no reason to continue with subsequent queries.
    # Attempts should continue in the event of a timeout however since it may
    # be due to an issue during the handshake.
    # Note: Newer server versions may still respond to older ping query types.
    # For example, 1.13.2 responds to 1.4/1.5 queries, but not 1.6 queries.
    # 1.7
    retval = json_query(address, port, timeout)
    # 1.6
    unless retval == Retval::SUCCESS || retval == Retval::CONNFAIL
      retval = new_query(address, port, timeout)
    end
    # 1.4/1.5
    unless retval == Retval::SUCCESS || retval == Retval::CONNFAIL
      retval = legacy_query(address, port, timeout)
    end
    # 1.8b/1.3
    unless retval == Retval::SUCCESS || retval == Retval::CONNFAIL
      retval = beta_query(address, port, timeout)
    end

    @online = false unless retval == Retval::SUCCESS
  end

  # 1.8b/1.3
  # 1.8 beta through 1.3 servers communicate as follows for a ping query:
  # 1. Client sends \xFE (server list ping)
  # 2. Server responds with:
  #   2a. \xFF (kick packet)
  #   2b. data length
  #   2c. 3 fields delimited by \u00A7 (section symbol)
  # The 3 fields, in order, are: message of the day, current players, and max players
  def beta_query(address, port, timeout)
    begin
      data = nil
      Timeout::timeout(timeout) do
        start_time = Time.now
        server = TCPSocket.new(address, port)
        @latency = ((Time.now - start_time) * 1000).round
        server.write("\xFE")
        if server.read(1).unpack('C').first == 0xFF # kick packet (255)
          len = server.read(2).unpack('n').first
          data = server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
          server.close
        else
          server.close
          return Retval::UNKNOWN
        end
      end

      if data == nil || data.empty?
        return Retval::UNKNOWN
      else
        server_info = data.split("\u00A7") # section symbol
        if server_info != nil && server_info.length >= NUM_FIELDS_BETA
          @version = "1.8b/1.3" # since server does not return version, set it
          @motd = server_info[0]
          @current_players = server_info[1]
          @max_players = server_info[2]
          @online = true
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return Retval::CONNFAIL
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    return Retval::SUCCESS
  end

  # 1.4/1.5
  # 1.4 and 1.5 servers communicate as follows for a ping query:
  # 1. Client sends:
  #   1a. \xFE (server list ping)
  #   1b. \x01 (server list ping payload)
  # 2. Server responds with:
  #   2a. \xFF (kick packet)
  #   2b. data length
  #   2c. 6 fields delimited by \x00 (null)
  # The 6 fields, in order, are: the section symbol and 1, protocol version,
  # server version, message of the day, current players, and max players
  # The protocol version corresponds with the server version and can be the
  # same for different server versions.
  def legacy_query(address, port, timeout)
    begin
      data = nil
      Timeout::timeout(timeout) do
        start_time = Time.now
        server = TCPSocket.new(address, port)
        @latency = ((Time.now - start_time) * 1000).round
        server.write("\xFE\x01")
        if server.read(1).unpack('C').first == 0xFF # kick packet (255)
          len = server.read(2).unpack('n').first
          data = server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
          server.close
        else
          server.close
          return Retval::UNKNOWN
        end
      end

      if data == nil || data.empty?
        return Retval::UNKNOWN
      else
        server_info = data.split("\x00") # null
        if server_info != nil && server_info.length >= NUM_FIELDS
          # server_info[0] contains the section symbol and 1
          # server_info[1] contains the protocol version (51 for example)
          @version = server_info[2]
          @motd = server_info[3]
          @current_players = server_info[4]
          @max_players = server_info[5]
          @online = true
        else
          return Retval::UNKNOWN
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return Retval::CONNFAIL
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    return Retval::SUCCESS
  end

  # 1.6
  # 1.6 servers communicate as follows for a ping query:
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
  # The 6 fields, in order, are: the section symbol and 1, protocol version,
  # server version, message of the day, current players, and max players
  # The protocol version corresponds with the server version and can be the
  # same for different server versions.
  def new_query(address, port, timeout)
    begin
      data = nil
      Timeout::timeout(DEFAULT_TIMEOUT) do
        start_time = Time.now
        server = TCPSocket.new(address, port)
        @latency = ((Time.now - start_time) * 1000).round
        server.write("\xFE\x01\xFA")
        server.write("\x00\x0B") # 11 (length of "MC|PingHost")
        server.write('MC|PingHost'.encode('UTF-16BE').force_encoding('ASCII-8BIT'))
        server.write([7 + 2 * address.length].pack('n'))
        server.write("\x4E")     # 78 (protocol version of 1.6.4)
        server.write([address.length].pack('n'))
        server.write(address.encode('UTF-16BE').force_encoding('ASCII-8BIT'))
        server.write([port].pack('N'))
        if server.read(1).unpack('C').first == 0xFF # kick packet (255)
          len = server.read(2).unpack('n').first
          data = server.read(len * 2).force_encoding('UTF-16BE').encode('UTF-8')
          server.close
        else
          server.close
          return Retval::UNKNOWN
        end
      end

      if data == nil || data.empty?
        return Retval::UNKNOWN
      else
        server_info = data.split("\x00") # null
        if server_info != nil && server_info.length >= NUM_FIELDS
          # server_info[0] contains the section symbol and 1
          # server_info[1] contains the protocol version (78 for example)
          @version = server_info[2]
          @motd = server_info[3]
          @current_players = server_info[4]
          @max_players = server_info[5]
          @online = true
        else
          return Retval::UNKNOWN
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return Retval::CONNFAIL
    rescue Timeout::Error
      return Retval::TIMEOUT
    rescue => exception
      $stderr.puts exception
      return Retval::UNKNOWN
    end
    return Retval::SUCCESS
  end

  # 1.7
  # 1.7 to current servers communicate as follows for a ping query:
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
  def json_query(address, port, timeout)
    return Retval::UNKNOWN # ToDo: Implement me!
  end

  attr_reader :address, :port, :online, :version, :motd, :current_players, :max_players, :latency
end
