# minestat.py - A Minecraft server status checker
# Copyright (C) 2016-2021 Lloyd Dilley, Felix Ern (MindSolve)
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
import json
import socket
import struct
from time import perf_counter
from enum import Enum
from typing import Union


class ConnStatus(Enum):
  """
Contains possible connection states.

- `SUCCESS`: The specified SLP connection succeeded (Request & response parsing OK)
- `CONNFAIL`: The socket to the server could not be established. Server offline, wrong hostname or port?
- `TIMEOUT`: The connection timed out. (Server under too much load? Firewall rules OK?)
- `UNKNOWN`: The connection was established, but the server spoke an unknown/unsupported SLP protocol.
  """

  SUCCESS = 0
  """The specified SLP connection succeeded (Request & response parsing OK)"""

  CONNFAIL = -1
  """The socket to the server could not be established. (Server offline, wrong hostname or port?)"""

  TIMEOUT = -2
  """The connection timed out. (Server under too much load? Firewall rules OK?)"""

  UNKNOWN = -3
  """The connection was established, but the server spoke an unknown/unsupported SLP protocol."""


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
    self.slp_protocol = None     # Server List Ping protocol

    # Future improvement: IPv4/IPv6, multiple addresses
    # If a host has multiple IP addresses or a IPv4 and a IPv6 address,
    # socket.connect choses the first IPv4 address returned by DNS.
    # If a mc server is not available over IPv4, this failes as "offline".
    # Or in some environments, the DNS returns the external and the internal
    # address, but from an internal client, only the internal address is reachable
    # See https://docs.python.org/3/library/socket.html#socket.getaddrinfo

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
    Method for querying a modern (MC Java >= 1.7) server with the SLP protocol.
    This protocol is based on encoded JSON, see the documentation at wiki.vg below
    for a full packet description.

    See https://wiki.vg/Server_List_Ping#Current
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(self.timeout)

    try:
      start_time = perf_counter()
      sock.connect((self.address, self.port))
      self.latency = round((perf_counter() - start_time) * 1000)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Construct Handshake packet
    req_data = bytearray([0x00])
    # Add protocol version. If pinging to determine version, use `-1`
    req_data += self._pack_varint(0)
    # Add server address length
    req_data += self._pack_varint(len(self.address))
    # Server address. Encoded with UTF8
    req_data += bytearray(self.address, "utf8")
    # Server port
    req_data += struct.pack(">H", self.port)
    # Next packet state (1 for status, 2 for login)
    req_data += bytearray([0x01])

    # Prepend full packet length
    req_data = self._pack_varint(len(req_data)) + req_data

    # Now actually send the constructed client request
    sock.send(req_data)

    # Now send empty "Request" packet
    # varint len, 0x00
    sock.send(bytearray([0x01, 0x00]))

    # Receive answer: full packet lenght as varint
    try:
      packet_len = self._unpack_varint(sock)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Receive actual packet id
    packet_id = self._unpack_varint(sock)

    # Receive & unpack payload length
    content_len = self._unpack_varint(sock)

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # If we receive a packet with id 0x19, something went wrong.
    # Usually the payload is JSON text, telling us what exactly.
    # We could stop here, and display something to the user, as this is not normal
    # behaviour, maybe a bug somewhere here.

    # Instead I am just going to check for the correct packet id: 0x00
    if packet_id != 0:
      return ConnStatus.UNKNOWN

    # Set protocol version
    self.slp_protocol = "json"

    # Parse and save to object attributes
    return self.__parse_json_payload(payload_raw)

  def __parse_json_payload(self, payload_raw: Union[bytes, bytearray]) -> ConnStatus:
    """
    Helper method for parsing the modern JSON-based SLP protocol.
    In use for Minecraft Java >= 1.7, see `json_query()` above for details regarding the protocol.

    :param payload_raw: The raw SLP payload, without header and string lenght
    """
    try:
      payload_obj = json.loads(payload_raw.decode('utf8'))
    except json.JSONDecodeError:
      return ConnStatus.UNKNOWN

    # Now that we have the status object, set all fields
    self.version = payload_obj["version"]["name"]
    self.motd = payload_obj["description"]["text"]
    self.max_players = payload_obj["players"]["max"]
    self.current_players = payload_obj["players"]["online"]

    # If we got here, everything is in order.
    self.online = True
    return ConnStatus.SUCCESS

  def _unpack_varint(self, sock: socket.socket):
    """ Small helper method for unpacking an int from an varint (streamed from socket). """
    data = 0
    for i in range(5):
      ordinal = sock.recv(1)

      if len(ordinal) == 0:
        break

      byte = ord(ordinal)
      data |= (byte & 0x7F) << 7 * i

      if not byte & 0x80:
        break

    return data

  def _pack_varint(self, data):
    """ Small helper method for packing a varint from an int. """
    ordinal = b''

    while True:
      byte = data & 0x7F
      data >>= 7
      ordinal += struct.pack('B', byte | (0x80 if data > 0 else 0))

      if data == 0:
        break

    return ordinal

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
    except OSError:
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
    req_data += bytearray([0x49])
    # strlen of serverhostname (big-endian short)
    req_data += struct.pack(">h", len(self.address))
    # the hostname of the server
    req_data += bytearray(self.address, "utf-16-be")
    # port of the server, as int (4 byte)
    req_data += struct.pack(">i", self.port)

    # DEBUG
    with open("req_data.bin", "wb") as fp:
      fp.write(req_data)

    # Now send the contructed client requests
    sock.send(req_data)

    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    try:
      raw_header = sock.recv(3)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # Set protocol version
    self.slp_protocol = "extended_legacy"

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
    except OSError:
      return ConnStatus.CONNFAIL

    # Send 0xFE 0x01 as packet id
    sock.send(bytearray([0xFE, 0x01]))

    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    try:
      raw_header = sock.recv(3)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # Set protocol version
    self.slp_protocol = "legacy"

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
    except OSError:
      return ConnStatus.CONNFAIL

    # Send 0xFE as packet id
    sock.send(bytearray([0xFE]))

    # Receive answer packet id (1 byte) and payload lengh (signed big-endian short; 2 byte)
    try:
      raw_header = sock.recv(3)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Extract payload length
    content_len = struct.unpack(">xh", raw_header)[0]

    # Receive full payload and close socket
    payload_raw = bytearray(sock.recv(content_len * 2))
    sock.close()

    # Set protocol version
    self.slp_protocol = "beta"

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
