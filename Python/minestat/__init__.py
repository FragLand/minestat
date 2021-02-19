# minestat.py - A Minecraft server status checker
# Copyright (C) 2016-2021 Lloyd Dilley
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
from datetime import datetime

class MineStat:
  VERSION = "1.0.1"             # MineStat version
  NUM_FIELDS = 6                # number of values expected from server
  NUM_FIELDS_BETA = 3           # number of values expected from a 1.8b/1.3 server
  DEFAULT_TIMEOUT = 5           # default TCP timeout in seconds

  def enum(**enums):
    return type('Enum', (), enums)

  Retval = enum(SUCCESS = 0, CONNFAIL = -1, TIMEOUT = -2, UNKNOWN = -3)

  def __init__(self, address, port, timeout = DEFAULT_TIMEOUT):
    self.address = address
    self.port = port
    self.online = None          # online or offline?
    self.version = None         # server version
    self.motd = None            # message of the day
    self.current_players = None # current number of players online
    self.max_players = None     # maximum player capacity
    self.latency = None         # ping time to server in milliseconds

    # Connect to the server and get the data
    byte_array = bytearray([0xFE, 0x01])
    raw_data = None
    data = []
    try:
      sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
      sock.settimeout(timeout)
      start_time = datetime.now()
      sock.connect((address, port))
      self.latency = datetime.now() - start_time
      self.latency = int(round(self.latency.total_seconds() * 1000))
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
        self.version = data[2].replace("\x00", "")
        self.motd = str(data[3].encode('utf-8').replace(b"\x00", b""), 'utf-8')
        self.current_players = data[4].replace("\x00", "")
        self.max_players = data[5].replace("\x00", "")
      else:
        self.online = False
