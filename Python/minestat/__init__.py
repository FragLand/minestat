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
from time import perf_counter, perf_counter_ns
from enum import Enum
from typing import Union


class ConnStatus(Enum):
  """
Contains possible connection states.

- `SUCCESS`: The specified SLP connection succeeded (Request & response parsing OK)
- `CONNFAIL`: The socket to the server could not be established. Server offline, wrong hostname or port?
- `TIMEOUT`:
  """

  SUCCESS = 0
  CONNFAIL = -1
  TIMEOUT = -2
  UNKNOWN = -3


class MineStat:
  VERSION = "2.0.0"             # MineStat version
  DEFAULT_TIMEOUT = 5           # default TCP timeout in seconds

  def __init__(self, address, port, timeout = DEFAULT_TIMEOUT):
    self.address = address
    self.port = port
    self.online = None           # online or offline?
    self.version = None          # server version
    self.motd = None             # message of the day
    self.current_players = None  # current number of players online
    self.max_players = None      # maximum player capacity
    self.latency = None          # ping time to server in milliseconds
    self.timeout = timeout       # socket timeout

    # TODO: Minecraft SRV resolution
    # Maybe allow setting port to None, then internally try to resolve Minecraft SRV
    # DNS entries?

    # TODO: Next problem: IPv4/IPv6, multiple addresses
    # If a host has multiple IP addresses or a IPv4 and a IPv6 address,
    # socket.connect choses the first IPv4 address returned by DNS.
    # If a mc server is not available over IPv4, this failes as "offline".
    # Or in some environments, the DNS returns the external and the internal
    # address, but from an internal client, only the internal address is reachable
    # See https://docs.python.org/3/library/socket.html#socket.getaddrinfo

    # TODO: Implement
    #
    # 1.: try to connect to MC 1.7+ SLP interface (JSON)
    # 2.: MC 1.6 SLP int - done
    # 3.: 1.4/ 1.5 SLP - done
    # 4.: b1.8 to 1.3 - done

    # Minecraft 1.7+ (JSON SLP)
    result = self.json_query()

    # Minecraft 1.6 (extended legacy SLP)
    if result is not ConnStatus.CONNFAIL \
        and result is not ConnStatus.SUCCESS:
      result = self.extended_legacy_query()

    # Minecraft 1.4 & 1.5 (legacy SLP)
    if result is not ConnStatus.CONNFAIL \
        and result is not ConnStatus.SUCCESS:
      result = self.legacy_query()

    # Minecraft Beta 1.8 to Release 1.3 (beta SLP)
    if result is not ConnStatus.CONNFAIL \
        and result is not ConnStatus.SUCCESS:
      self.beta_query()

  def json_query(self):
    """
    Minecraft 1.7+ SLP query, encoded JSON
    See https://wiki.vg/Server_List_Ping#Current

    TODO: Implement
    """
    return ConnStatus.UNKNOWN

  def extended_legacy_query(self):
    """
    Minecraft 1.6 SLP query, extended legacy ping protocol.
    All modern servers are currently backwards compatible with this protocol.

    See https://wiki.vg/Server_List_Ping#1.6
    :return:
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(self.timeout)

    try:
      start_time = perf_counter()
      sock.connect((self.address, self.port))
      self.latency = round((perf_counter() - start_time) * 1000)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except:
      return ConnStatus.CONNFAIL

    # Send 0xFE as packet identifier,
    # 0x01 as ping packet content
    # 0xFA as packet identifier for a plugin message
    # 0x00 0x0B as strlen of following string
    req_data = bytearray([0xFE, 0x01, 0xFA, 0x00, 0x0B])
    # the string 'MC|PingHost' as UTF-16BE encoded string
    req_data += bytearray("MC|PingHost", "utf-16-be")
    # 0xXX 0xXX byte count of rest of data, 7+len(serverhostname), as short
    req_data += struct.pack(">h", 7 + (len(self.address) * 2))
    # 0xXX [legacy] protocol version (before netty rewrite)
    # Used here: 74 (MC 1.6.2)
    req_data += bytearray([0x4A])
    # strlen of serverhostname (big-endian short)
    req_data += struct.pack(">h", len(self.address))
    # the hostname of the server
    req_data += bytearray(self.address, "utf-16-be")
    # port of the server, as int (4 byte)
    req_data += struct.pack(">i", self.port)

    # Now send the contructed client requests
    sock.send(req_data)

    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    raw_header = sock.recv(3)
    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # Parse and save to object attributes
    return self.__parse_legacy_payload(payload_raw)

  def legacy_query(self):
    """
    Minecraft 1.4-1.5 SLP query, server response contains more info than beta SLP

    See https://wiki.vg/Server_List_Ping#1.4_to_1.5

    :return: ConnStatus
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(self.timeout)

    try:
      start_time = perf_counter()
      sock.connect((self.address, self.port))
      self.latency = round((perf_counter() - start_time) * 1000)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except:
      return ConnStatus.CONNFAIL

    # Send 0xFE 0x01 as packet id
    sock.send(bytearray([0xFE, 0x01]))
    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    raw_header = sock.recv(3)
    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # Parse and save to object attributes
    return self.__parse_legacy_payload(payload_raw)

  def __parse_legacy_payload(self, payload_raw: Union[bytearray, bytes]) -> ConnStatus:
    """
    Internal helper method for parsing the legacy SLP payload (legacy and extended legacy).

    :param payload_raw: The extracted legacy SLP payload as bytearray/bytes
    """
    # According to wiki.vg, beta, legacy and extended legacy use UTF-16BE as "payload" encoding
    payload_str = payload_raw.decode('utf-16-be')

    # This "payload" contains six fields delimited by a NUL character:
    # - a fixed prefix '§1'
    # - the protocol version
    # - the server version
    # - the MOTD
    # - the online player count
    # - the max player count
    payload_list = payload_str.split('\x00')

    # Check for count of string parts, expected is 6 for this protocol version
    if len(payload_list) != 6:
      return ConnStatus.UNKNOWN

    # - a fixed prefix '§1'
    # - the protocol version
    # - the server version
    self.version = payload_list[2]
    # - the MOTD
    self.motd = payload_list[3]
    # - the online player count
    self.current_players = int(payload_list[4])
    # - the max player count
    self.max_players = int(payload_list[5])

    # If we got here, everything is in order
    self.online = True
    return ConnStatus.SUCCESS

  def beta_query(self):
    """
    Minecraft Beta 1.8 to Release 1.3 SLP protocol
    See https://wiki.vg/Server_List_Ping#Beta_1.8_to_1.3

    :return: ConnStatus
    """

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(self.timeout)

    try:
      start_time = perf_counter()
      sock.connect((self.address, self.port))
      self.latency = round((perf_counter() - start_time) * 1000)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except:
      return ConnStatus.CONNFAIL

    # Send 0xFE as packet id
    sock.send(bytearray([0xFE]))
    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    raw_header = sock.recv(3)
    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # According to wiki.vg, beta, legacy and extended legacy use UTF-16BE as "payload" encoding
    payload_str = payload_raw.decode('utf-16-be')
    # This "payload" contains three values:
    # The MOTD, the max player count, and the online player count
    payload_list = payload_str.split('§')

    # Check for count of string parts, expected is 3 for this protocol version
    # Note: We could check here if the list has the len() one, as that is most probably an error message.
    # e.g. ['Protocol error']
    if len(payload_list) < 3:
      return ConnStatus.UNKNOWN

    # The last value is the max player count
    self.max_players = int(payload_list[-1])
    # The second(-to-last) value is the online player count
    self.current_players = int(payload_list[-2])
    # The first value it the server MOTD
    # This could contain '§' itself, thats the reason for the join here
    self.motd = "§".join(payload_list[:-2])

    # Set general version, as the protocol doesn't contain the server version
    self.version = "<= 1.3"

    # If we got here, everything is in order
    self.online = True

    return ConnStatus.SUCCESS
