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
import struct
from datetime import datetime
from enum import Enum


class ConnectionStatus(Enum):
  """
  TODO: Document
  """

  SUCCESS = 0
  CONNFAIL = -1
  TIMEOUT = -2
  UNKNOWN = -3


class MineStat:
  VERSION = "2.0.0"             # MineStat version
  NUM_FIELDS = 6                # number of values expected from server
  NUM_FIELDS_BETA = 3           # number of values expected from a 1.8b/1.3 server
  DEFAULT_TIMEOUT = 5           # default TCP timeout in seconds

  def __init__(self, address, port, timeout = DEFAULT_TIMEOUT):
    self.address = address
    self.port = port
    self.online = None          # online or offline?
    self.version = None         # server version
    self.motd = None            # message of the day
    self.current_players = None # current number of players online
    self.max_players = None     # maximum player capacity
    self.latency = None         # ping time to server in milliseconds

    # TODO: Implement
    #
    # 1.: try to connect to MC 1.7+ SLP interface (JSON)
    # 2.: try to connect to MC 1.6 SLP int
    # 3.: 1.4/ 1.5 SLP
    # 4.: b1.8 to 1.3

  def json_query(self):
    """
    Minecraft 1.7+ SLP query, encoded JSON
    See https://wiki.vg/Server_List_Ping#Current

    TODO: Implement
    """
    pass

  def query_1_6(self):
    """
    Minecraft 1.6 SLP query, extended legacy ping protocol

    See https://wiki.vg/Server_List_Ping#1.6
    :return:
    """

  def query_legacy(self):
    """
    Minecraft 1.4-1.5 SLP query, server response contains more info than beta SLP
    See https://wiki.vg/Server_List_Ping#1.4_to_1.5

  TODO: Implement
    :return:
    """
    pass

  def query_beta(self):
    """
    Minecraft Beta 1.8 to Release 1.3 SLP protocol
    See https://wiki.vg/Server_List_Ping#Beta_1.8_to_1.3

  TODO: Implement
    :return:
    """
    pass
