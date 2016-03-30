# minestat.py - A Minecraft server status checker
# Copyright (C) 2016 Lloyd Dilley
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

import socket

class MineStat:
  NUM_FIELDS = 6                # number of values expected from server

  def __init__(self, address, port, timeout = 7):
    self.address = address
    self.port = port
    self.online = None          # online or offline?
    self.version = None         # server version
    self.motd = None            # message of the day
    self.current_players = None # current number of players online
    self.max_players = None     # maximum player capacity

    # Connect to the server and get the data
    byte_array = bytearray([0xFE, 0x01])
    raw_data = None
    data = []
    try:
      sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      sock.settimeout(timeout)
      sock.connect((address, port))
      sock.settimeout(None)
      sock.send(byte_array)
      raw_data = sock.recv(512)
      sock.close()
    except:
      self.online = False

    # Parse the received data
    if raw_data is None or raw_data == '':
      self.online = False
    else:
      data = raw_data.decode('cp437').split('\x00\x00\x00')
      if data and len(data) >= self.NUM_FIELDS:
        self.online = True
        self.version = data[2]
        self.motd = data[3]
        self.current_players = data[4]
        self.max_players = data[5]
      else:
        self.online = False
