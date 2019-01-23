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
  DEFAULT_TIMEOUT = 5  # default TCP timeout in seconds

  def initialize(address, port, timeout = DEFAULT_TIMEOUT)
    @address = address
    @port = port
    @online            # online or offline?
    @version           # server version
    @motd              # message of the day
    @current_players   # current number of players online
    @max_players       # maximum player capacity

    # Check if remote port is open and get the server protocol version
    case get_protocol(address, port)
      when 0 # 1.7
        json_query(address, port, timeout)
      when 1 # 1.6
        new_query(address, port, timeout)
      when 2 # 1.4/1.5
        legacy_query(address, port, timeout)
      when 3 # 1.8b/1.3
        beta_query(address, port, timeout)
      else   # unknown
        @online = false
    end
  end

  def get_protocol(address, port)
    # 1.7
    begin
      Timeout::timeout(DEFAULT_TIMEOUT) do
        # ToDo: Implement me!
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return -1
    rescue Timeout::Error
      # Fall through to next check...
    rescue => exception
      $stderr.puts exception
      return -1
    end

    # 1.6
    begin
      Timeout::timeout(DEFAULT_TIMEOUT) do
        server = TCPSocket.new(address, port)
        server.write("\xFE\x01\xFA")
        server.write("\x00\x0B") # 11 (length of "MC|PingHost")
        server.write('MC|PingHost'.encode('utf-16be').force_encoding('ASCII-8BIT'))
        server.write([7 + 2 * address.length].pack('n'))
        server.write("\x4E")     # 78 (1.6.4)
        server.write([address.length].pack('n'))
        server.write(address.encode('utf-16be').force_encoding('ASCII-8BIT'))
        server.write([port].pack('N'))
        if server.read(1).unpack('C').first == 0xFF # kick packet
          server.close()
          return 1
        else
          server.close()
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return -1
    rescue Timeout::Error
      # Fall through to next check...
    rescue => exception
      $stderr.puts exception
      return -1
    end

    # 1.4/1.5
    begin
      Timeout::timeout(DEFAULT_TIMEOUT) do
        server = TCPSocket.new(address, port)
        server.write("\xFE\x01")
        if server.read(1).unpack('C').first == 0xFF
          server.close()
          return 2
        else
          server.close()
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      return -1
    rescue Timeout::Error
      # Fall through to next check...
    rescue => exception
      $stderr.puts exception
      return -1
    end

    # 1.8b/1.3 (fallback)
#    begin
#      Timeout::timeout(DEFAULT_TIMEOUT) do
#        server = TCPSocket.new(address, port)
#        server.write("\xFE")
#        if server.read(1).unpack('C').first == 0xFF
#          server.close()
#          return 3
#        else
#          server.close()
#        end
#      end
#    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
#      return -1
#    rescue => exception
#      $stderr.puts exception
#      return -1
#    end

    return -1
  end

  # 1.8b/1.3
  def beta_query(address, port, timeout)
    data = nil
    begin
      Timeout::timeout(timeout) do
        server = TCPSocket.new(address, port)
        server.write("\xFE")
        data = server.gets()

        # ToDo: Handle returned data
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
      @online = false
    rescue exception
     @online = false
     $stderr.puts exception
    end
  end

  # 1.4/1.5
  def legacy_query(address, port, timeout)
    begin
      data = nil
      Timeout::timeout(timeout) do
        server = TCPSocket.new(address, port)
        server.write("\xFE\x01")
        data = server.gets()
        server.close()
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
      @online = false
    rescue exception
      @online = false
      $stderr.puts exception
    end

    if data == nil || data.empty?
      @online = false
    else
      server_info = data.split("\x00\x00\x00")
      if server_info != nil && server_info.length >= NUM_FIELDS
        @online = true
        @version = server_info[2].gsub("\x00",'')
        @motd = server_info[3].gsub("\x00",'')
        @current_players = server_info[4].gsub("\x00",'')
        @max_players = server_info[5].gsub("\x00",'')
      else
        @online = false
      end
    end
  end

  # 1.6
  def new_query(address, port, timeout)
    begin
      Timeout::timeout(DEFAULT_TIMEOUT) do
        server = TCPSocket.new(address, port)
        server.write("\xFE\x01\xFA")
        server.write("\x00\x0B") # 11 (length of "MC|PingHost")
        server.write('MC|PingHost'.encode('utf-16be').force_encoding('ASCII-8BIT'))
        server.write([7 + 2 * address.length].pack('n'))
        server.write("\x4E")     # 78 (1.6.4)
        server.write([address.length].pack('n'))
        server.write(address.encode('utf-16be').force_encoding('ASCII-8BIT'))
        server.write([port].pack('N'))
        if server.read(1).unpack('C').first == 0xFF # kick packet
          len = server.read(2).unpack('n').first
          data = server.read(len * 2).force_encoding('utf-16be').encode('utf-8')
          server_info = data.split("\u0000")
          server.close()
          if server_info != nil && server_info.length >= NUM_FIELDS
            #server_info[0] == "\u00A71"
            #server_info[1] == "78" # version number -- 78 for example
            @version = server_info[2]
            @motd = server_info[3]
            @current_players = server_info[4]
            @max_players = server_info[5]
            @online = true
          else
            @online = false
          end
        else
          server.close()
          @online = false
        end
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Timeout::Error
      @online = false
    rescue => exception
      @online = false
      $stderr.puts exception
    end
  end

  # 1.7
  def json_query(address, port, timeout)

  end

  attr_reader :address, :port, :online, :version, :motd, :current_players, :max_players
end
