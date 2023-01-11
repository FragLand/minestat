# minestat.py - A Minecraft server status checker
# Copyright (C) 2016-2022 Lloyd Dilley, Felix Ern (MindSolve)
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
import base64
import io
import json
import socket
import struct
import re
from time import time, perf_counter
from enum import Enum
from typing import Union, Optional

class ConnStatus(Enum):
  """
Contains possible connection states.

- `SUCCESS`: The specified SLP connection succeeded (Request & response parsing OK)
- `CONNFAIL`: The socket to the server could not be established. Server offline, wrong hostname or port?
- `TIMEOUT`: The connection timed out. (Server under too much load? Firewall rules OK?)
- `UNKNOWN`: The connection was established, but the server spoke an unknown/unsupported SLP protocol.
  """

  def __str__(self) -> str:
    return str(self.name)

  SUCCESS = 0
  """The specified SLP connection succeeded (Request & response parsing OK)"""

  CONNFAIL = -1
  """The socket to the server could not be established. (Server offline, wrong hostname or port?)"""

  TIMEOUT = -2
  """The connection timed out. (Server under too much load? Firewall rules OK?)"""

  UNKNOWN = -3
  """The connection was established, but the server spoke an unknown/unsupported SLP protocol."""

class SlpProtocols(Enum):
  """
Contains possible SLP (Server List Ping) protocols.

- `ALL`: Try all protocols.

  Attempts to connect to a remote server using all available protocols until an acceptable response
  is received or until failure.

- `BEDROCK_RAKNET`: The Minecraft Bedrock/Education edition protocol.

  *Available for all Minecraft Bedrock versions, not compatible with Java edition.*

- `JSON`: The newest and currently supported SLP protocol.

  Uses (wrapped) JSON as payload. Complex query, see `json_query()` for the protocol implementation.

  *Available since Minecraft 1.7*
- `EXTENDED_LEGACY`: The previous SLP protocol

  Used by Minecraft 1.6, it is still supported by all newer server versions.
  Complex query needed, see implementation `extended_legacy_query()` for full protocol details.

  *Available since Minecraft 1.6*
- `LEGACY`: The legacy SLP protocol.

  Used by Minecraft 1.4 and 1.5, it is the first protocol to contain the server version number.
  Very simple protocol call (2 byte), simple response decoding.
  See `legacy_query()` for full implementation and protocol details.

  *Available since Minecraft 1.4*
- `BETA`: The first SLP protocol.

  Used by Minecraft Beta 1.8 till Release 1.3, it is the first SLP protocol.
  It contains very few details, no server version info, only MOTD, max- and online player counts.

  *Available since Minecraft Beta 1.8*
  """

  def __str__(self) -> str:
    return str(self.name)

  ALL = 5
  """
  Attempt to use all protocols.
  """

  BEDROCK_RAKNET = 4
  """
  The Bedrock SLP-equivalent using the RakNet `Unconnected Ping` packet.

  Currently experimental.
  """

  JSON = 3
  """
  The newest and currently supported SLP protocol.

  Uses (wrapped) JSON as payload. Complex query, see `json_query()` for the protocol implementation.

  *Available since Minecraft 1.7*
  """

  EXTENDED_LEGACY = 2
  """The previous SLP protocol

  Used by Minecraft 1.6, it is still supported by all newer server versions.
  Complex query needed, see implementation `extended_legacy_query()` for full protocol details.

  *Available since Minecraft 1.6*
  """

  LEGACY = 1
  """
  The legacy SLP protocol.

  Used by Minecraft 1.4 and 1.5, it is the first protocol to contain the server version number.
  Very simple protocol call (2 byte), simple response decoding.
  See `legacy_query()` for full implementation and protocol details.

  *Available since Minecraft 1.4*
  """

  BETA = 0
  """
  The first SLP protocol.

  Used by Minecraft Beta 1.8 till Release 1.3, it is the first SLP protocol.
  It contains very few details, no server version info, only MOTD, max- and online player counts.

  *Available since Minecraft Beta 1.8*
  """

class MineStat:
  VERSION = "2.4.0"             # MineStat version
  DEFAULT_TCP_PORT = 25565      # default TCP port for SLP queries
  DEFAULT_BEDROCK_PORT = 19132  # default UDP port for Bedrock/MCPE servers
  DEFAULT_TIMEOUT = 5           # default TCP timeout in seconds

  def __init__(self, address: str, port: int = 0, timeout: int = DEFAULT_TIMEOUT, query_protocol: SlpProtocols = SlpProtocols.ALL) -> None:
    self.address: str = address
    """hostname or IP address of the Minecraft server"""
    autoport: bool = False
    if port == 0:
      autoport = True
      if query_protocol is SlpProtocols.BEDROCK_RAKNET:
        self.port = self.DEFAULT_BEDROCK_PORT
      else:
        self.port = self.DEFAULT_TCP_PORT
    else:
      self.port: int = port
    """port number the Minecraft server accepts connections on"""
    self.online: bool = False
    """online or offline?"""
    self.version: Optional[str] = None
    """server version"""
    self.motd: Optional[str] = None
    """message of the day, unchanged server response (including formatting codes/JSON)"""
    self.stripped_motd: Optional[str] = None
    """message of the day, stripped of all formatting ("human-readable")"""
    self.current_players: Optional[int] = None
    """current number of players online"""
    self.max_players: Optional[int] = None
    """maximum player capacity"""
    self.latency: Optional[int] = None
    """ping time to server in milliseconds"""
    self.timeout: int = timeout
    """socket timeout"""
    self.slp_protocol: Optional[SlpProtocols] = None
    """Server List Ping protocol"""
    self.favicon_b64: Optional[str] = None
    """base64-encoded favicon possibly contained in JSON 1.7 responses"""
    self.favicon: Optional[str] = None
    """decoded favicon data"""
    self.gamemode: Optional[str] = None
    """Bedrock specific: The current game mode (Creative/Survival/Adventure)"""
    self.connection_status: Optional[ConnStatus] = None
    """Status of connection ("SUCCESS", "CONNFAIL", "TIMEOUT", or "UNKNOWN")"""

    # Future improvement: IPv4/IPv6, multiple addresses
    # If a host has multiple IP addresses or a IPv4 and a IPv6 address,
    # socket.connect choses the first IPv4 address returned by DNS.
    # If a mc server is not available over IPv4, this failes as "offline".
    # Or in some environments, the DNS returns the external and the internal
    # address, but from an internal client, only the internal address is reachable
    # See https://docs.python.org/3/library/socket.html#socket.getaddrinfo

    # If the user wants a specific protocol, use only that.
    result = ConnStatus.UNKNOWN
    if query_protocol is not SlpProtocols.ALL:
      if query_protocol is SlpProtocols.BETA:
        result = self.beta_query()
      elif query_protocol is SlpProtocols.LEGACY:
        result = self.legacy_query()
      elif query_protocol is SlpProtocols.EXTENDED_LEGACY:
        result = self.extended_legacy_query()
      elif query_protocol is SlpProtocols.JSON:
        result = self.json_query()
      elif query_protocol is SlpProtocols.BEDROCK_RAKNET:
        result = self.bedrock_raknet_query()
      self.connection_status = result

      return

    # Note: The order for Java edition here is unfortunately important.
    # Some older versions of MC don't accept packets for a few seconds
    # after receiving a not understood packet.
    # An example is MC 1.4: Nothing works directly after a json request.
    # A legacy query alone works fine.

    # Minecraft Bedrock/Pocket/Education Edition (MCPE/MCEE)
    if autoport:
      self.port = self.DEFAULT_BEDROCK_PORT
    result = self.bedrock_raknet_query()
    self.connection_status = result

    if result is ConnStatus.SUCCESS:
      return

    if autoport:
      self.port = self.DEFAULT_TCP_PORT

    # Minecraft 1.4 & 1.5 (legacy SLP)
    result = self.legacy_query()

    # Minecraft Beta 1.8 to Release 1.3 (beta SLP)
    if result not in [ConnStatus.CONNFAIL, ConnStatus.SUCCESS]:
      result = self.beta_query()

    # Minecraft 1.6 (extended legacy SLP)
    if result is not ConnStatus.CONNFAIL:
      result = self.extended_legacy_query()

    # Minecraft 1.7+ (JSON SLP)
    if result is not ConnStatus.CONNFAIL:
      self.json_query()

    self.connection_status = result

  @staticmethod
  def motd_strip_formatting(raw_motd: Union[str, dict]) -> str:
    """
    Function for stripping all formatting codes from a motd. Supports Json Chat components (as dict) and
    the legacy formatting codes.

    :param raw_motd: The raw MOTD, either as a string or dict (from "json.loads()")
    """
    stripped_motd = ""

    if isinstance(raw_motd, str):
      stripped_motd = re.sub(r"§.", "", raw_motd)

    elif isinstance(raw_motd, dict):
      stripped_motd = raw_motd.get("text", "")

      if raw_motd.get("extra"):
        for sub in raw_motd["extra"]:
          stripped_motd += MineStat.motd_strip_formatting(sub)

    return stripped_motd

  def bedrock_raknet_query(self) -> ConnStatus:
    """
    Method for querying a Bedrock server (Minecraft PE, Windows 10 or Education Edition).
    The protocol is based on the RakNet protocol.

    See https://wiki.vg/Raknet_Protocol#Unconnected_Ping

    Note: This method currently works as if the connection is handled via TCP (as if no packet loss might occur).
    Packet loss handling should be implemented (resending).
    """

    RAKNET_MAGIC = bytearray([0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78])

    # Create socket with type DGRAM (for UDP)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.settimeout(self.timeout)

    try:
      start_time = perf_counter()
      sock.connect((self.address, self.port))
      self.latency = round((perf_counter() - start_time) * 1000)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except OSError:
      return ConnStatus.CONNFAIL

    # Construct the `Unconnected_Ping` packet
    # Packet ID - 0x01
    req_data = bytearray([0x01])
    # current unix timestamp in ms as signed long (64-bit) LE-encoded
    req_data += struct.pack("<q", int(time()*1000))
    # RakNet MAGIC (0x00ffff00fefefefefdfdfdfd12345678)
    req_data += RAKNET_MAGIC
    # Client GUID - as signed long (64-bit) LE-encoded
    req_data += struct.pack("<q", 0x02)

    sock.send(req_data)

    # Do all the receiving in a try-catch, to reduce duplication of error handling

    # response packet:
    # byte - 0x1C - Unconnected Pong
    # long - timestamp
    # long - server GUID
    # 16 byte - magic
    # short - Server ID string length
    # string - Server ID string
    try:
      response_buffer, response_addr = sock.recvfrom(1024)
      response_stream = io.BytesIO(response_buffer)

      # Receive packet id
      packet_id = response_stream.read(1)

      # Response packet ID should always be 0x1c
      if packet_id != b'\x1c':
        return ConnStatus.UNKNOWN

      # Receive (& ignore) response timestamp
      response_timestamp = struct.unpack("<q", response_stream.read(8))

      # Server GUID
      response_server_guid = struct.unpack("<q", response_stream.read(8))

      # Magic
      response_magic = response_stream.read(16)
      if response_magic != RAKNET_MAGIC:
        return ConnStatus.UNKNOWN

      # Server ID string length
      response_id_string_length = struct.unpack(">h", response_stream.read(2))

      # Receive server ID string
      response_id_string = response_stream.read().decode("utf8")

    except socket.timeout:
      return ConnStatus.TIMEOUT
    except (ConnectionResetError, ConnectionAbortedError):
      return ConnStatus.UNKNOWN
    except OSError:
      return ConnStatus.CONNFAIL
    finally:
      sock.close()

    # Set protocol version
    self.slp_protocol = SlpProtocols.BEDROCK_RAKNET

    # Parse and save to object attributes
    return self.__parse_bedrock_payload(response_id_string)

  def __parse_bedrock_payload(self, payload_str: str) -> ConnStatus:
    motd_index = ["edition", "motd_1", "protocol_version", "version", "current_players", "max_players",
                  "server_uid", "motd_2", "gamemode", "gamemode_numeric", "port_ipv4", "port_ipv6"]
    payload = {e: f for e, f in zip(motd_index, payload_str.split(";"))}

    self.online = True

    self.current_players = int(payload["current_players"])
    self.max_players = int(payload["max_players"])
    self.version = payload["version"] + " " + payload["motd_2"] + "(" + payload["edition"] + ")"

    self.motd = payload["motd_1"]
    self.stripped_motd = self.motd_strip_formatting(self.motd)

    self.gamemode = payload["gamemode"]

    return ConnStatus.SUCCESS

  def json_query(self) -> ConnStatus:
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
    req_data += bytearray([0xff, 0xff, 0xff, 0xff, 0x0f])
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

    # Do all the receiving in a try-catch, to reduce duplication of error handling
    try:
      # Receive answer: full packet length as varint
      packet_len = self._unpack_varint(sock)

      # Check if full packet length seems acceptable
      if packet_len < 3:
        return ConnStatus.UNKNOWN

      # Receive actual packet id
      packet_id = self._unpack_varint(sock)

      # If we receive a packet with id 0x19, something went wrong.
      # Usually the payload is JSON text, telling us what exactly.
      # We could stop here, and display something to the user, as this is not normal
      # behaviour, maybe a bug somewhere here.

      # Instead I am just going to check for the correct packet id: 0x00
      if packet_id != 0:
        return ConnStatus.UNKNOWN

      # Receive & unpack payload length
      content_len = self._unpack_varint(sock)

      # Receive full payload
      payload_raw = self._recv_exact(sock, content_len)

    except socket.timeout:
      return ConnStatus.TIMEOUT
    except (ConnectionResetError, ConnectionAbortedError):
      return ConnStatus.UNKNOWN
    except OSError:
      return ConnStatus.CONNFAIL
    finally:
      sock.close()

    # Set protocol version
    self.slp_protocol = SlpProtocols.JSON

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

    # The motd might be a string directly, not a json object
    if isinstance(payload_obj["description"], str):
      self.motd = payload_obj["description"]
    else:
      self.motd = json.dumps(payload_obj["description"])
    self.stripped_motd = self.motd_strip_formatting(payload_obj["description"])

    self.max_players = payload_obj["players"]["max"]
    self.current_players = payload_obj["players"]["online"]

    try:
      self.favicon_b64 = payload_obj["favicon"]
      if self.favicon_b64:
        self.favicon = str(base64.b64decode(self.favicon_b64.split("base64,")[1]), 'ISO-8859–1')
    except KeyError:
      self.favicon_b64 = None
      self.favicon = None

    # If we got here, everything is in order.
    self.online = True
    return ConnStatus.SUCCESS

  def _unpack_varint(self, sock: socket.socket) -> int:
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

  def _pack_varint(self, data) -> bytes:
    """ Small helper method for packing a varint from an int. """
    ordinal = b''

    while True:
      byte = data & 0x7F
      data >>= 7
      ordinal += struct.pack('B', byte | (0x80 if data > 0 else 0))

      if data == 0:
        break

    return ordinal

  def extended_legacy_query(self) -> ConnStatus:
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

    # Now send the contructed client requests
    sock.send(req_data)

    try:
      # Receive answer packet id (1 byte)
      packet_id = self._recv_exact(sock, 1)

      # Check packet id (should be "kick packet 0xFF")
      if packet_id[0] != 0xFF:
        return ConnStatus.UNKNOWN

      # Receive payload lengh (signed big-endian short; 2 byte)
      raw_payload_len = self._recv_exact(sock, 2)

      # Extract payload length
      # Might be empty, if the server keeps the connection open but doesn't send anything
      content_len = struct.unpack(">h", raw_payload_len)[0]

      # Check if payload length is acceptable
      if content_len < 3:
        return ConnStatus.UNKNOWN

      # Receive full payload and close socket
      payload_raw = self._recv_exact(sock, content_len * 2)

    except socket.timeout:
      return ConnStatus.TIMEOUT
    except (ConnectionResetError, ConnectionAbortedError, struct.error):
      return ConnStatus.UNKNOWN
    except OSError:
      return ConnStatus.CONNFAIL
    finally:
      sock.close()

    # Set protocol version
    self.slp_protocol = SlpProtocols.EXTENDED_LEGACY

    # Parse and save to object attributes
    return self.__parse_legacy_payload(payload_raw)

  def legacy_query(self) -> ConnStatus:
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
      raw_header = self._recv_exact(sock, 3)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except (ConnectionAbortedError, ConnectionResetError):
      return ConnStatus.UNKNOWN
    except OSError:
      return ConnStatus.CONNFAIL

    # Extract payload length
    # Might be empty, if the server keeps the connection open but doesn't send anything
    try:
      content_len = struct.unpack(">xh", raw_header)[0]
    except struct.error:
      return ConnStatus.UNKNOWN

    # Receive full payload and close socket
    payload_raw = bytearray(self._recv_exact(sock, content_len * 2))
    sock.close()

    # Set protocol version
    self.slp_protocol = SlpProtocols.LEGACY

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
    self.stripped_motd = self.motd_strip_formatting(payload_list[3])
    # - the online player count
    self.current_players = int(payload_list[4])
    # - the max player count
    self.max_players = int(payload_list[5])

    # If we got here, everything is in order
    self.online = True
    return ConnStatus.SUCCESS

  def beta_query(self) -> ConnStatus:
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
      raw_header = self._recv_exact(sock, 3)
    except socket.timeout:
      return ConnStatus.TIMEOUT
    except (ConnectionResetError, ConnectionAbortedError):
      return ConnStatus.UNKNOWN
    except OSError:
      return ConnStatus.CONNFAIL

    # Extract payload length
    # Might be empty, if the server keeps the connection open but doesn't send anything
    try:
      content_len = struct.unpack(">xh", raw_header)[0]
    except struct.error:
      return ConnStatus.UNKNOWN

    # Receive full payload and close socket
    payload_raw = bytearray(self._recv_exact(sock, content_len * 2))
    sock.close()

    # Set protocol version
    self.slp_protocol = SlpProtocols.BETA

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
    self.stripped_motd = self.motd_strip_formatting("§".join(payload_list[:-2]))

    # Set general version, as the protocol doesn't contain the server version
    self.version = ">=1.8b/1.3"

    # If we got here, everything is in order
    self.online = True

    return ConnStatus.SUCCESS

  @staticmethod
  def _recv_exact(sock: socket.socket, size: int) -> bytearray:
    """
    Helper function for receiving a specific amount of data. Works around the problems of `socket.recv`.
    Throws a ConnectionAbortedError if the connection was closed while waiting for data.

    :param sock: Open socket to receive data from
    :param size: Amount of bytes of data to receive
    :return: bytearray with the received data
    """
    data = bytearray()

    while len(data) < size:
      temp_data = bytearray(sock.recv(size - len(data)))

      # If the connection was closed, `sock.recv` returns an empty string
      if not temp_data:
        raise ConnectionAbortedError

      data += temp_data

    return data
