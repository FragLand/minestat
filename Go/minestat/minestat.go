/*
 * minestat.go - A Minecraft server status checker
 * Copyright (C) 2016, 2022 Lloyd Dilley
 * http://www.dilley.me/
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

package minestat

import "net"
import "strconv"
import "strings"
import "time"
// To install the unicode dependency below: go get golang.org/x/text/encoding/unicode
import "golang.org/x/text/encoding/unicode"

const VERSION string = "1.0.0"     // MineStat version
const NUM_FIELDS int = 6           // number of values expected from server
const NUM_FIELDS_BETA uint8 = 3    // number of values expected from a 1.8b/1.3 server
const DEFAULT_TCP_PORT = 25565     // default TCP port
const DEFAULT_BEDROCK_PORT = 19132 // Bedrock/Pocket Edition default UDP port
const DEFAULT_TIMEOUT uint8 = 5    // default TCP timeout in seconds

const (
  RETURN_SUCCESS uint8 = 0
  RETURN_CONNFAIL = 1
  RETURN_TIMEOUT = 2
  RETURN_UNKNOWN = 3
)

const (
  REQUEST_NONE uint16 = 0 // uint16 to be compatible with optional_params array
  REQUEST_BETA = 0
  REQUEST_LEGACY = 1
  REQUEST_EXTENDED = 2
  REQUEST_JSON = 3
  REQUEST_BEDROCK = 4
)

var Address string          // server hostname or IP address
var Port uint16             // server TCP port
var Online bool = false     // online or offline?
var Version string          // server version
var Motd string             // message of the day
var Current_players uint32  // current number of players online
var Max_players uint32      // maximum player capacity
var Latency time.Duration   // ping time to server in milliseconds
var Timeout uint8           // TCP/UDP timeout in seconds
var Request_type uint8      // protocol version
var Connection_status uint8 // status of connection

func Init(given_address string, optional_params ...uint16) {
  Address = given_address
  Port = DEFAULT_TCP_PORT
  Timeout = DEFAULT_TIMEOUT
  Request_type = uint8(REQUEST_NONE)

  if len(optional_params) == 1 {
    Port = optional_params[0]
  } else if len(optional_params) == 2 {
    Port = optional_params[0]
    Timeout = uint8(optional_params[1])
  } else if len(optional_params) >= 3 {
    Port = optional_params[0]
    Timeout = uint8(optional_params[1])
    Request_type = uint8(optional_params[2])
  }

  /* Latency may report a misleading value of >1s due to name resolution delay when using net.Dial().
     A workaround for this issue is to use an IP address instead of a hostname or FQDN. */
  start_time := time.Now()
  conn, err := net.DialTimeout("tcp", Address + ":" + strconv.FormatUint(uint64(Port), 10), time.Duration(Timeout) * time.Second)
  Latency = time.Since(start_time)
  Latency = Latency.Round(time.Millisecond)
  if err != nil {
    return
  }

  _, err = conn.Write([]byte("\xFE\x01"))
  if err != nil {
    return
  }

  kick_packet := make([]byte, 1)
  _, err = conn.Read(kick_packet)
  if err != nil {
    return
  }
  if kick_packet[0] != 255 {
    return
  }

  // ToDo: Unpack this 2-byte length as a big-endian short
  msg_len := make([]byte, 2)
  _, err = conn.Read(msg_len)
  if err != nil {
    return
  }

  raw_data := make([]byte, msg_len[1] * 2)
  _, err = conn.Read(raw_data)
  if err != nil {
    return
  }
  conn.Close()

  if raw_data == nil || len(raw_data) == 0 {
    return
  }

  // raw_data is UTF-16BE encoded, so it needs to be decoded to UTF-8.
  utf16be_decoder := unicode.UTF16(unicode.BigEndian, unicode.IgnoreBOM).NewDecoder()
  utf8_str, _ := utf16be_decoder.String(string(raw_data[:]))

  data := strings.Split(utf8_str, "\x00")
  if data != nil && len(data) >= NUM_FIELDS {
    Online = true
    Version = data[2]
    Motd = data[3]
    current_players, err := strconv.ParseUint(data[4], 10, 32)
    if err != nil {
      panic(err)
    }
    max_players, err := strconv.ParseUint(data[5], 10, 32)
    if err != nil {
      panic(err)
    }
    Current_players = uint32(current_players)
    Max_players = uint32(max_players)
  } else {
    Online = false
  }
}
