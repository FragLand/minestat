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

const VERSION string = "2.0.0"     // MineStat version
const NUM_FIELDS uint8 = 6         // number of values expected from server
const NUM_FIELDS_BETA uint8 = 3    // number of values expected from a 1.8b/1.3 server
const DEFAULT_TCP_PORT = 25565     // default TCP port
const DEFAULT_BEDROCK_PORT = 19132 // Bedrock/Pocket Edition default UDP port
const DEFAULT_TIMEOUT uint8 = 5    // default TCP timeout in seconds

type Status_code uint8
const (
  RETURN_SUCCESS Status_code = 0 // connection was successful and the response data was parsed without problems
  RETURN_CONNFAIL = 1            // connection failed due to an unknown hostname or incorrect port number
  RETURN_TIMEOUT = 2             // connection timed out -- either the server is overloaded or it dropped our packets
  RETURN_UNKNOWN = 3             // connection was successful, but the response data could not be properly parsed
)

// uint16 to be compatible with optional_params array
const (
  REQUEST_NONE uint16 = 0 // try all protocols
  REQUEST_BETA = 1        // server versions 1.8b to 1.3
  REQUEST_LEGACY = 2      // server versions 1.4 to 1.5
  REQUEST_EXTENDED = 3    // server version 1.6
  REQUEST_JSON = 4        // server versions 1.7 to latest
  REQUEST_BEDROCK = 5     // Bedrock/Pocket Edition
)

var Address string          // server hostname or IP address
var Port uint16             // server TCP port
var Online bool             // online or offline?
var Version string          // server version
var Motd string             // message of the day
var Current_players uint32  // current number of players online
var Max_players uint32      // maximum player capacity
var Latency time.Duration   // ping time to server in milliseconds
var Timeout uint8           // TCP/UDP timeout in seconds
var Protocol string         // friendly name of protocol
var Request_type uint8      // protocol version
var Connection_status uint8 // status of connection
var Server_socket net.Conn  // server socket

// Initialize data and server connection
func Init(given_address string, optional_params ...uint16) {
  Online = false
  Motd = ""
  Version = ""
  Current_players = 0
  Max_players = 0
  Latency = 0
  Protocol = ""
  Connection_status = 7
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
  var retval Status_code
  if Request_type == REQUEST_BETA {
    retval = beta_request()
  } else if Request_type == REQUEST_LEGACY {
    retval = legacy_request()
  } else if Request_type == REQUEST_EXTENDED {
    retval = extended_request()
  } else if Request_type == REQUEST_JSON {
    retval = json_request()
  } else if Request_type == REQUEST_BEDROCK {
    retval = bedrock_request()
  } else {
    /*
       Attempt various ping requests in a particular order. If the
       connection fails, there is no reason to continue with subsequent
       requests. Attempts should continue in the event of a timeout
       however since it may be due to an issue during the handshake.
       Note: Newer server versions may still respond to older SLP requests.
    */
    // SLP 1.4/1.5
    retval = legacy_request()

    // SLP 1.8b/1.3
    if retval != RETURN_SUCCESS && retval != RETURN_CONNFAIL {
      retval = beta_request()
    }

    // SLP 1.6
    /*if retval != RETURN_CONNFAIL {
      retval = extended_request()
    }

    // SLP 1.7
    if retval != RETURN_CONNFAIL {
      retval = json_request()
    }

    // Bedrock/Pocket Edition
    if !Online && retval != RETURN_SUCCESS {
      retval = bedrock_request()
    }*/
  }
}

// Establishes a connection to the Minecraft server
func connect() Status_code {
  // Latency may report a misleading value of >1s due to name resolution delay when using net.Dial().
  // A workaround for this issue is to use an IP address instead of a hostname or FQDN.
  start_time := time.Now()
  conn, err := net.DialTimeout("tcp", Address + ":" + strconv.FormatUint(uint64(Port), 10), time.Duration(Timeout) * time.Second)
  Latency = time.Since(start_time)
  Latency = Latency.Round(time.Millisecond)
  if err != nil {
    if strings.Contains(err.Error(), "timeout") {
      return RETURN_TIMEOUT
    }
    return RETURN_CONNFAIL
  }
  Server_socket = conn
  return RETURN_SUCCESS
}

// Populates object fields after connecting
func parse_data(delimiter string, is_beta ...bool) Status_code {
  kick_packet := make([]byte, 1)
  _, err := Server_socket.Read(kick_packet)
  if err != nil {
    return RETURN_UNKNOWN
  }
  if kick_packet[0] != 255 {
    return RETURN_UNKNOWN
  }

  // ToDo: Unpack this 2-byte length as a big-endian short
  msg_len := make([]byte, 2)
  _, err = Server_socket.Read(msg_len)
  if err != nil {
    return RETURN_UNKNOWN
  }

  raw_data := make([]byte, msg_len[1] * 2)
  _, err = Server_socket.Read(raw_data)
  if err != nil {
    return RETURN_UNKNOWN
  }
  Server_socket.Close()

  if raw_data == nil || len(raw_data) == 0 {
    return RETURN_UNKNOWN
  }

  // raw_data is UTF-16BE encoded, so it needs to be decoded to UTF-8.
  utf16be_decoder := unicode.UTF16(unicode.BigEndian, unicode.IgnoreBOM).NewDecoder()
  utf8_str, _ := utf16be_decoder.String(string(raw_data[:]))

  data := strings.Split(utf8_str, delimiter)
  if len(is_beta) >= 1 && is_beta[0] { // SLP 1.8b/1.3
    if data != nil && uint8(len(data)) >= NUM_FIELDS_BETA {
      Online = true
      Version = ">=1.8b/1.3" // since server does not return version, set it
      Motd = data[0]
      current_players, err := strconv.ParseUint(data[1], 10, 32)
      if err != nil {
        return RETURN_UNKNOWN
      }
      max_players, err := strconv.ParseUint(data[2], 10, 32)
      if err != nil {
        return RETURN_UNKNOWN
      }
      Current_players = uint32(current_players)
      Max_players = uint32(max_players)
    } else {
      return RETURN_UNKNOWN
    }
  } else { // SLP > 1.8b/1.3
    if data != nil && uint8(len(data)) >= NUM_FIELDS {
      Online = true
      Version = data[2]
      Motd = data[3]
      current_players, err := strconv.ParseUint(data[4], 10, 32)
      if err != nil {
        return RETURN_UNKNOWN
      }
      max_players, err := strconv.ParseUint(data[5], 10, 32)
      if err != nil {
        return RETURN_UNKNOWN
      }
      Current_players = uint32(current_players)
      Max_players = uint32(max_players)
    } else {
      return RETURN_UNKNOWN
    }
  }
  return RETURN_SUCCESS
}

/*
   1.8b/1.3
   1.8 beta through 1.3 servers communicate as follows for a ping request:
   1. Client sends \xFE (server list ping)
   2. Server responds with:
     2a. \xFF (kick packet)
     2b. data length
     2c. 3 fields delimited by \u00A7 (section symbol)
   The 3 fields, in order, are: message of the day, current players, and max players
*/
func beta_request() Status_code {
  retval := connect()
  if retval != RETURN_SUCCESS {
    return retval
  }

  // Perform handshake
  _, err := Server_socket.Write([]byte("\xFE"))
  if err != nil {
    return RETURN_UNKNOWN
  }

  retval = parse_data("\u00A7", true) // section symbol '§'
  if retval == RETURN_SUCCESS {
    Protocol = "SLP 1.8b/1.3 (beta)"
  }

  return retval
}

/*
   1.4/1.5
   1.4 and 1.5 servers communicate as follows for a ping request:
   1. Client sends:
     1a. \xFE (server list ping)
     1b. \x01 (server list ping payload)
   2. Server responds with:
     2a. \xFF (kick packet)
     2b. data length
     2c. 6 fields delimited by \x00 (null)
   The 6 fields, in order, are: the section symbol and 1, protocol version,
   server version, message of the day, current players, and max players.
   The protocol version corresponds with the server version and can be the
   same for different server versions.
*/
func legacy_request() Status_code {
  retval := connect()
  if retval != RETURN_SUCCESS {
    return retval
  }

  // Perform handshake
  _, err := Server_socket.Write([]byte("\xFE\x01"))
  if err != nil {
    return RETURN_UNKNOWN
  }

  retval = parse_data("\x00") // null character
  if retval == RETURN_SUCCESS {
    Protocol = "SLP 1.4/1.5 (legacy)"
  }

  return retval
}

// ToDo: Implement me.
func extended_request() Status_code {
  return RETURN_UNKNOWN
}

// ToDo: Implement me.
func json_request() Status_code {
  return RETURN_UNKNOWN
}

// ToDo: Implement me.
func bedrock_request() Status_code {
  return RETURN_UNKNOWN
}
