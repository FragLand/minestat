/*
 * minestat.go - A Minecraft server status checker
 * Copyright (C) 2016 Lloyd Dilley
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
import "strings"
import "time"

const NUM_FIELDS int = 6
const DEFAULT_TIMEOUT int = 5 // default TCP timeout in seconds
var Address string
var Port string
var Online bool               // online or offline?
var Version string            // server version
var Motd string               // message of the day
var Current_players string    // current number of players online
var Max_players string        // maximum player capacity

func Init(given_address string, given_port string, optional_timeout ...int) {
  timeout := DEFAULT_TIMEOUT
  if len(optional_timeout) > 0 {
    timeout = optional_timeout[0]
  }
  Address = given_address
  Port = given_port
  conn, err := net.DialTimeout("tcp", Address + ":" + Port, time.Duration(timeout) * time.Second)
  if err != nil {
    Online = false
    return
  }

  _, err = conn.Write([]byte("\xFE\x01"))
  if err != nil {
    Online = false
    return
  }

  raw_data := make([]byte, 512)
  _, err = conn.Read(raw_data)
  if err != nil {
    Online = false
    return
  }
  conn.Close()

  if raw_data == nil || len(raw_data) == 0 {
    Online = false
    return
  }

  data := strings.Split(string(raw_data[:]), "\x00\x00\x00")
  if data != nil && len(data) >= NUM_FIELDS {
    Online = true
    Version = data[2]
    Motd = data[3]
    Current_players = data[4]
    Max_players = data[5]
  } else {
    Online = false
  }
}
