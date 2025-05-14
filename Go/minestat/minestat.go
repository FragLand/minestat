/*
 * minestat.go - A Minecraft server status checker
 * Copyright (C) 2016, 2023 Lloyd Dilley, 2023 Sch8ill
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

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/text/encoding/unicode"
)

const VERSION string = "2.2.0"     // MineStat version
const NUM_FIELDS uint8 = 6         // number of values expected from server
const NUM_FIELDS_BETA uint8 = 3    // number of values expected from a 1.8b/1.3 server
const DEFAULT_TCP_PORT = 25565     // default TCP port
const DEFAULT_BEDROCK_PORT = 19132 // Bedrock/Pocket Edition default UDP port
const DEFAULT_TIMEOUT uint8 = 5    // default TCP timeout in seconds

type Status_code uint8

const (
	RETURN_SUCCESS  Status_code = 0 // connection was successful and the response data was parsed without problems
	RETURN_CONNFAIL             = 1 // connection failed due to an unknown hostname or incorrect port number
	RETURN_TIMEOUT              = 2 // connection timed out -- either the server is overloaded or it dropped our packets
	RETURN_UNKNOWN              = 3 // connection was successful, but the response data could not be properly parsed
)

// uint16 to be compatible with optional_params array
const (
	REQUEST_NONE     uint16 = 0 // try all protocols
	REQUEST_BETA            = 1 // server versions 1.8b to 1.3
	REQUEST_LEGACY          = 2 // server versions 1.4 to 1.5
	REQUEST_EXTENDED        = 3 // server version 1.6
	REQUEST_JSON            = 4 // server versions 1.7 to latest
	REQUEST_BEDROCK         = 5 // Bedrock/Pocket Edition
)

var Address string          // server hostname or IP address
var Port uint16             // server TCP port
var Srv_address string      // server address from DNS SRV record
var Srv_port uint16         // server TCP port from DNS SRV record
var Srv_enabled bool        // perform SRV lookups?
var Online bool             // online or offline?
var Version string          // server version
var Motd string             // message of the day
var Game_mode string        // game mode (Bedrock/Pocket Edition only)
var Current_players uint32  // current number of players online
var Max_players uint32      // maximum player capacity
var Latency int64           // ping time to server in milliseconds
var Timeout uint8           // TCP/UDP timeout in seconds
var Protocol string         // friendly name of protocol
var Request_type uint8      // protocol version
var Connection_status uint8 // status of connection
var Server_socket net.Conn  // server socket
var Port_set bool           // was a port number provided to Init()?
var Debug bool              // debug mode

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
	Srv_address = ""
	Srv_port = 0
	Srv_enabled = true
	Timeout = DEFAULT_TIMEOUT
	Request_type = uint8(REQUEST_NONE)
	Port_set = false
	Debug = false

	if len(optional_params) == 1 {
		Port = optional_params[0]
		Port_set = true
	} else if len(optional_params) == 2 {
		Port = optional_params[0]
		Port_set = true
		Timeout = uint8(optional_params[1])
	} else if len(optional_params) == 3 {
		Port = optional_params[0]
		Port_set = true
		Timeout = uint8(optional_params[1])
		Request_type = uint8(optional_params[2])
	} else if len(optional_params) == 4 {
		Port = optional_params[0]
		Port_set = true
		Timeout = uint8(optional_params[1])
		Request_type = uint8(optional_params[2])
		if uint8(optional_params[3]) == 1 {
			Debug = true
		}
	} else if len(optional_params) >= 5 {
		Port = optional_params[0]
		Port_set = true
		Timeout = uint8(optional_params[1])
		Request_type = uint8(optional_params[2])
		if uint8(optional_params[3]) == 1 {
			Debug = true
		}
		if uint8(optional_params[4]) == 0 {
			Srv_enabled = false
		}
	}

	if Srv_enabled {
		lookup_srv()
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
		*/
		// SLP 1.7
		if retval != RETURN_CONNFAIL {
			retval = json_request()
		}

		// Bedrock/Pocket Edition
		if !Online && retval != RETURN_SUCCESS {
			retval = bedrock_request()
		}
	}
}

// Attempts to resolve SRV records
func lookup_srv() {
	_, records, err := net.LookupSRV("minecraft", "tcp", Address)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "lookup_srv(): %s", err)
		}
		return
	}
	// Strip trailing period from returned SRV target if one exists.
	Srv_address = strings.TrimSuffix(records[0].Target, ".")
	Srv_port = records[0].Port
}

// Establishes a connection to the Minecraft server
func connect() Status_code {
	var conn net.Conn
	var err error
	// Latency may report a misleading value of >1s due to name resolution delay when using net.Dial().
	// A workaround for this issue is to use an IP address instead of a hostname or FQDN.
	start_time := time.Now()
	if Request_type == REQUEST_BEDROCK {
		if !Port_set {
			Port = DEFAULT_BEDROCK_PORT
		}
		conn, err = net.DialTimeout("udp", Address+":"+strconv.FormatUint(uint64(Port), 10), time.Duration(Timeout)*time.Second)
	} else {
		if len(Srv_address) > 0 {
			conn, err = net.DialTimeout("tcp", Srv_address+":"+strconv.FormatUint(uint64(Srv_port), 10), time.Duration(Timeout)*time.Second)
		} else {
			conn, err = net.DialTimeout("tcp", Address+":"+strconv.FormatUint(uint64(Port), 10), time.Duration(Timeout)*time.Second)
		}
	}
	Latency = time.Since(start_time).Milliseconds()
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "connect(): %s", err)
		}
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
		if Debug {
			fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
		}
		return RETURN_UNKNOWN
	}
	if kick_packet[0] != 255 {
		return RETURN_UNKNOWN
	}

	// ToDo: Unpack this 2-byte length as a big-endian short
	msg_len := make([]byte, 2)
	_, err = Server_socket.Read(msg_len)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
		}
		return RETURN_UNKNOWN
	}

	raw_data := make([]byte, msg_len[1]*2)
	_, err = Server_socket.Read(raw_data)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
		}
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
				if Debug {
					fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
				}
				return RETURN_UNKNOWN
			}
			max_players, err := strconv.ParseUint(data[2], 10, 32)
			if err != nil {
				if Debug {
					fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
				}
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
				if Debug {
					fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
				}
				return RETURN_UNKNOWN
			}
			max_players, err := strconv.ParseUint(data[5], 10, 32)
			if err != nil {
				if Debug {
					fmt.Fprintf(os.Stderr, "parse_data(): %s", err)
				}
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
 1. Client sends 0xFE (server list ping)
 2. Server responds with:
    2a. 0xFF (kick packet)
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
		if Debug {
			fmt.Fprintf(os.Stderr, "beta_request(): %s", err)
		}
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
    1a. 0xFE (server list ping)
    1b. 0x01 (server list ping payload)
 2. Server responds with:
    2a. 0xFF (kick packet)
    2b. data length
    2c. 6 fields delimited by 0x00 (null)

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
		if Debug {
			fmt.Fprintf(os.Stderr, "legacy_request(): %s", err)
		}
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
	retval := connect()
	if retval != RETURN_SUCCESS {
		return retval
	}

	// Send handshake
	handshake := []byte{0x00}                                   // ID: 0x00 (handshake)
	handshake = append(handshake, 0xFF, 0xFF, 0xFF, 0xFF, 0x0F) // version: -1 (VarInt)

	// Add server address and port
	var serverAddr string
	if len(Srv_address) > 0 {
		serverAddr = Srv_address
	} else {
		serverAddr = Address
	}
	hostLen := len(serverAddr)
	handshake = append(handshake, byte(hostLen))         // hostlen
	handshake = append(handshake, []byte(serverAddr)...) // host

	var serverPort uint16
	if len(Srv_address) > 0 {
		serverPort = Srv_port
	} else {
		serverPort = Port
	}
	handshake = append(handshake, byte(serverPort>>8), byte(serverPort&0xFF)) // port 2 bytes

	handshake = append(handshake, 0x01)

	handshakeLen := len(handshake)
	var lenBytes []byte
	if handshakeLen < 128 {
		lenBytes = []byte{byte(handshakeLen)}
	} else if handshakeLen < 16384 {
		lenBytes = []byte{byte(handshakeLen&0x7F | 0x80), byte(handshakeLen >> 7)}
	} else {
		// > 16384
		lenBytes = []byte{byte(handshakeLen&0x7F | 0x80), byte((handshakeLen>>7)&0x7F | 0x80), byte(handshakeLen >> 14)}
	}

	// Handshake
	_, err := Server_socket.Write(append(lenBytes, handshake...))
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "json_request(): %s", err)
		}
		return RETURN_UNKNOWN
	}

	// Send status request packet
	statusRequest := []byte{0x01, 0x00}
	_, err = Server_socket.Write(statusRequest)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "json_request(): %s", err)
		}
		return RETURN_UNKNOWN
	}

	var length int
	var shift uint
	for {
		b := make([]byte, 1)
		_, err = Server_socket.Read(b)
		if err != nil {
			if Debug {
				fmt.Fprintf(os.Stderr, "json_request(): %s", err)
			}
			return RETURN_UNKNOWN
		}

		length |= int(b[0]&0x7F) << shift
		if (b[0] & 0x80) == 0 {
			break
		}
		shift += 7
		if shift > 35 {
			if Debug {
				fmt.Fprintf(os.Stderr, "json_request(): VarInt too long")
			}
			return RETURN_UNKNOWN
		}
	}

	// Check ID
	packetId := make([]byte, 1)
	_, err = Server_socket.Read(packetId)
	if err != nil || packetId[0] != 0x00 {
		if Debug {
			fmt.Fprintf(os.Stderr, "json_request(): Invalid packet ID: %v, error: %v", packetId, err)
		}
		return RETURN_UNKNOWN
	}

	// Read JSON data
	jsonData := make([]byte, length-1) // Subtract packet ID length
	_, err = Server_socket.Read(jsonData)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "json_request(): %s", err)
		}
		return RETURN_UNKNOWN
	}
	Server_socket.Close()

	// JSON parsing
	jsonStr := string(jsonData)
	if Debug {
		fmt.Fprintf(os.Stderr, "json_request(): Received JSON data: %s\n", jsonStr)
	}

	// Simplified JSON parsing
	Online = true
	Protocol = "SLP 1.7+"

	// Try to get version
	versionStart := strings.Index(jsonStr, "\"name\":\"")
	if versionStart != -1 {
		versionStart += 8
		versionEnd := strings.Index(jsonStr[versionStart:], "\"")
		if versionEnd != -1 {
			Version = jsonStr[versionStart : versionStart+versionEnd]
			// Clean up color codes
			Version = strings.ReplaceAll(Version, "§", "")
		}
	}

	// Try to get players online and max
	playersOnlineStart := strings.Index(jsonStr, "\"online\":")
	if playersOnlineStart != -1 {
		playersOnlineStart += 9
		playersOnlineEnd := strings.IndexAny(jsonStr[playersOnlineStart:], ",}")
		if playersOnlineEnd != -1 {
			onlinePlayers, err := strconv.ParseUint(strings.TrimSpace(jsonStr[playersOnlineStart:playersOnlineStart+playersOnlineEnd]), 10, 32)
			if err == nil {
				Current_players = uint32(onlinePlayers)
			}
		}
	}

	playersMaxStart := strings.Index(jsonStr, "\"max\":")
	if playersMaxStart != -1 {
		playersMaxStart += 6
		playersMaxEnd := strings.IndexAny(jsonStr[playersMaxStart:], ",}")
		if playersMaxEnd != -1 {
			maxPlayers, err := strconv.ParseUint(strings.TrimSpace(jsonStr[playersMaxStart:playersMaxStart+playersMaxEnd]), 10, 32)
			if err == nil {
				Max_players = uint32(maxPlayers)
			}
		}
	}

	// Try to get motd
	motdStart := strings.Index(jsonStr, "\"description\":")
	if motdStart != -1 {
		motdStart += 14
		// Is string?
		if jsonStr[motdStart:motdStart+1] == "\"" { // String format
			motdStart += 1
			motdEnd := strings.Index(jsonStr[motdStart:], "\"")
			if motdEnd != -1 {
				Motd = jsonStr[motdStart : motdStart+motdEnd]
			}
		} else { // Object format, try to extract text field
			textStart := strings.Index(jsonStr[motdStart:], "\"text\":\"")
			if textStart != -1 {
				textStart += 8
				textEnd := strings.Index(jsonStr[motdStart+textStart:], "\"")
				if textEnd != -1 {
					Motd = jsonStr[motdStart+textStart : motdStart+textStart+textEnd]
				}
			}
		}
		// Clean up MOTD color codes
		Motd = strings.ReplaceAll(Motd, "§", "")
	}

	if len(Version) == 0 || Current_players == 0 && Max_players == 0 {
		return RETURN_UNKNOWN
	}

	return RETURN_SUCCESS
}

/*
Bedrock/Pocket Edition servers communicate as follows for an unconnected ping request:
 1. Client sends:
    1a. 0x01 (unconnected ping packet containing the fields specified below)
    1b. current time as a long
    1c. magic number
    1d. client GUID as a long
 2. Server responds with:
    2a. 0x1c (unconnected pong packet containing the follow fields)
    2b. current time as a long
    2c. server GUID as a long
    2d. 16-bit magic number
    2e. server ID string length
    2f. server ID as a string

The fields from the pong response, in order, are:
  - edition
  - MotD line 1
  - protocol version
  - version name
  - current player count
  - maximum player count
  - unique server ID
  - MotD line 2
  - game mode as a string
  - game mode as a numeric
  - IPv4 port number
  - IPv6 port number
*/
func bedrock_request() Status_code {
	Request_type = REQUEST_BEDROCK
	retval := connect()
	if retval != RETURN_SUCCESS {
		return retval
	}

	request := []byte("\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xff\x00\xfe\xfe\xfe\xfe\xfd\xfd\xfd\xfd\x124Vx")
	_, err := Server_socket.Write(request)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "bedrock_request(): %s", err)
		}
		return RETURN_UNKNOWN
	}

	buffer := make([]byte, 1024)
	pLen, err := Server_socket.Read(buffer)
	if err != nil {
		if Debug {
			fmt.Fprintf(os.Stderr, "bedrock_request(): %s", err)
		}
		return RETURN_UNKNOWN
	}

	// ToDo: Parse data and close socket in parse_data()
	Server_socket.Close()

	rawRes := buffer[:pLen]
	strRes := string(rawRes[35:])
	splitRes := strings.Split(strRes, ";")

	Online = true
	Motd = splitRes[1]

	current_players, _ := strconv.ParseUint(splitRes[4], 10, 32)
	max_players, _ := strconv.ParseUint(splitRes[5], 10, 32)
	Current_players = uint32(current_players)
	Max_players = uint32(max_players)

	if len(splitRes) >= 8 {
		Version = splitRes[3] + " " + splitRes[7] + " (" + splitRes[0] + ")"
	} else {
		Version = splitRes[3] + " (" + splitRes[0] + ")"
	}

	if len(splitRes) >= 9 {
		Game_mode = splitRes[8]
	}

	Protocol = "Bedrock v" + splitRes[2]

	return RETURN_SUCCESS
}
