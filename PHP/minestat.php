<?php
/*
 * minestat.php - A Minecraft server status checker
 * Copyright (C) 2014-2022 Lloyd Dilley
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

class MineStat
{
  const VERSION = "2.3.0";            // MineStat version
  const NUM_FIELDS = 6;               // number of values expected from server
  const NUM_FIELDS_BETA = 3;          // number of values expected from a 1.8b/1.3 server
  const MAX_VARINT_SIZE = 5;          // maximum number of bytes a varint can be
  const DEFAULT_TCP_PORT = 25565;     // default TCP port
  const DEFAULT_BEDROCK_PORT = 19132; // Bedrock/Pocket Edition default UDP port
  const DEFAULT_TIMEOUT = 5;          // default TCP/UDP timeout in seconds
  /*
   * Bedrock/Pocket Edition packet offset in bytes (1 + 8 + 8 + 16 + 2)
   * Unconnected pong (0x1C) = 1 byte
   * Timestamp as a long = 8 bytes
   * Server GUID as a long = 8 bytes
   * Magic number = 16 bytes
   * String ID length = 2 bytes
   */
  const BEDROCK_PACKET_OFFSET = 35;

  // No enums or class nesting in PHP, so this is our workaround for return values
  const RETURN_SUCCESS = 0;           // the server ping completed successfully
  const RETURN_CONNFAIL = -1;         // the server ping failed due to a connection error
  const RETURN_TIMEOUT = -2;          // the server ping failed due to a time out
  const RETURN_UNKNOWN = -3;          // the server ping failed for an unknown reason

  // Request types
  const REQUEST_NONE = -1;            // try everything
  const REQUEST_BETA = 0;             // server versions 1.8b to 1.3
  const REQUEST_LEGACY = 1;           // server version 1.4 to 1.5
  const REQUEST_EXTENDED = 2;         // server version 1.6
  const REQUEST_JSON = 3;             // server version 1.7 to latest
  const REQUEST_BEDROCK = 4;          // Bedrock/Pocket Edition

  private $address;                   // hostname or IP address of the Minecraft server
  private $port;                      // port number the Minecraft server accepts connections on
  private $online;                    // online or offline?
  private $version;                   // Minecraft server version
  private $mode;                      // game mode (Bedrock/Pocket Edition only)
  private $motd;                      // message of the day
  private $stripped_motd;             // message of the day without formatting
  private $current_players;           // current number of players online
  private $max_players;               // maximum player capacity
  private $protocol;                  // protocol level
  private $json_data;                 // JSON data for 1.7 queries
  private $latency;                   // ping time to server in milliseconds
  private $timeout;                   // timeout in seconds
  private $socket;                    // network socket
  private $request_type;              // protocol version
  private $try_all;                   // try all protocols?

  public function __construct($address, $port = MineStat::DEFAULT_TCP_PORT, $timeout = MineStat::DEFAULT_TIMEOUT, $request_type = MineStat::REQUEST_NONE)
  {
    $this->address = $address;
    $this->port = $port;
    $this->timeout = $timeout;
    $this->online = false;
    if($request_type == MineStat::REQUEST_NONE)
      $this->try_all = true;

    switch($request_type)
    {
      case MineStat::REQUEST_BETA:
        $this->beta_request();
        break;
      case MineStat::REQUEST_LEGACY:
        $this->legacy_request();
        break;
      case MineStat::REQUEST_EXTENDED:
        $this->extended_legacy_request();
        break;
      case MineStat::REQUEST_JSON:
        $this->json_request();
        break;
      case MineStat::REQUEST_BEDROCK:
        $this->bedrock_request();
        break;
      default:
        $retval = $this->legacy_request();            // SLP 1.4/1.5
        if($retval != MineStat::RETURN_SUCCESS && $retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->beta_request();            // SLP 1.8b/1.3
        if($retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->extended_legacy_request(); // SLP 1.6
        if($retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->json_request();            // SLP 1.7
        if($retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->bedrock_request();         // Bedrock/Pocket Edition
    }
  }

  public function __destruct()
  {
    if(@socket_read($this->socket, 1))
    {
      socket_shutdown($this->socket);
      socket_close($this->socket);
      $this->socket = null;
    }
  }

  public function get_address() { return $this->address; }

  public function get_port() { return $this->port; }

  public function is_online() { return $this->online; }

  public function get_version() { return $this->version; }

  public function get_mode() { return $this->mode; }

  public function get_motd() { return $this->motd; }

  public function get_stripped_motd() { return $this->stripped_motd; }

  public function get_current_players() { return $this->current_players; }

  public function get_max_players() { return $this->max_players; }

  public function get_protocol() { return $this->protocol; }

  public function get_json() { return $this->json_data; }

  public function get_latency() { return $this->latency; }

  public function get_request_type() { return $this->request_type; }

  /* Strips message of the day formatting characters */
  private function strip_motd()
  {
    if(isset($this->motd['text']))
      $this->stripped_motd = $this->motd['text'];
    else
      $this->stripped_motd = $this->motd;
    if(isset($this->motd['extra']))
    {
      $json_data = $this->motd['extra'];
      if(!empty($json_data))
      {
        foreach($json_data as &$nested_hash)
          $this->stripped_motd .= $nested_hash['text'];
      }
    }
    if(is_array($this->motd))
      $this->motd = json_encode($this->motd);
    $this->stripped_motd = preg_replace("/§./", "", $this->stripped_motd);
  }

  /* Connects to remote server */
  private function connect()
  {
    if($this->request_type == MineStat::REQUEST_BEDROCK || $this->request_type == "Bedrock/Pocket Edition")
    {
      if($this->port == MineStat::DEFAULT_TCP_PORT && $this->try_all)
        $this->port = MineStat::DEFAULT_BEDROCK_PORT;
      $this->socket = socket_create(AF_INET, SOCK_DGRAM, 0);
    }
    else
    {
      $this->socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
    }
    socket_set_option($this->socket, SOL_SOCKET, SO_RCVTIMEO, array('sec' => $this->timeout, 'usec' => 0));
    if($this->socket === false)
      return MineStat::RETURN_CONNFAIL;

    // Since socket_connect() does not respect timeout, we have to toggle non-blocking mode and enforce the timeout
    socket_set_nonblock($this->socket);
    $time = time();
    $start_time = microtime(true);
    while(!@socket_connect($this->socket, $this->address, $this->port))
    {
      if((time() - $time) >= $this->timeout)
      {
        socket_close($this->socket);
        return MineStat::RETURN_TIMEOUT;
      }
      usleep(0);
    }
    $result = @socket_connect($this->socket, $this->address, $this->port);
    $this->latency = round((microtime(true) - $start_time) * 1000);
    socket_set_block($this->socket);
    if($result === false && socket_last_error($this->socket) != SOCKET_EISCONN)
      return MineStat::RETURN_CONNFAIL;

    return MineStat::RETURN_SUCCESS;
  }

  /* Populates object fields after connecting */
  private function parse_data($delimiter, $is_beta = false)
  {
    if($this->request_type == "Bedrock/Pocket Edition")
    {
      socket_recv($this->socket, $response, 1, MSG_PEEK);
      $response = @unpack('C', $response);
    }
    else // SLP
    {
      $response = @unpack('C', socket_read($this->socket, 1));
    }

    if($this->request_type == "Bedrock/Pocket Edition" && !empty($response) && $response[1] == 0x1C) // unconnected pong packet
    {
      socket_recv($this->socket, $server_id_len, MineStat::BEDROCK_PACKET_OFFSET, MSG_PEEK);
      $server_id_len = unpack('n', substr($server_id_len, -2))[1];
      $raw_data = substr(socket_read($this->socket, MineStat::BEDROCK_PACKET_OFFSET + $server_id_len), MineStat::BEDROCK_PACKET_OFFSET);
      socket_close($this->socket);
    }
    elseif(!empty($response) && $response[1] == 0xFF) // kick packet (255)
    {
      $len = unpack('n', socket_read($this->socket, 2))[1];
      $raw_data = mb_convert_encoding(socket_read($this->socket, ($len * 2)), "UTF-8", "UTF-16BE");
      socket_close($this->socket);
    }
    else
    {
      socket_close($this->socket);
      return MineStat::RETURN_UNKNOWN;
    }

    if(isset($raw_data))
    {
      $server_info = explode($delimiter, $raw_data); // split on delimiter
      if($is_beta)
        $num_fields = MineStat::NUM_FIELDS_BETA;
      else
        $num_fields = MineStat::NUM_FIELDS;
      if(isset($server_info) && sizeof($server_info) >= $num_fields)
      {
        if($is_beta)
        {
          $this->version = ">=1.8b/1.3"; // since server does not return version, set it
          $this->motd = $server_info[0];
          $this->strip_motd();
          $this->current_players = (int)$server_info[1];
          $this->max_players = (int)$server_info[2];
          $this->online = true;
        }
        elseif($this->request_type == "Bedrock/Pocket Edition")
        {
          $this->protocol = (int)$server_info[2];
          $this->version = sprintf("%s %s (%s)", $server_info[3], $server_info[7], $server_info[0]);
          $this->mode = $server_info[8];
          $this->motd = $server_info[1];
          $this->strip_motd();
          $this->current_players = (int)$server_info[4];
          $this->max_players = (int)$server_info[5];
          $this->online = true;
        }
        else
        {
          // $server_info[0] contains the section symbol and 1
          $this->protocol = (int)$server_info[1]; // contains the protocol version (51 for 1.9 or 78 for 1.6.4 for example)
          $this->version = $server_info[2];
          $this->motd = $server_info[3];
          $this->strip_motd();
          $this->current_players = (int)$server_info[4];
          $this->max_players = (int)$server_info[5];
          $this->online = true;
        }
      }
      else
        return MineStat::RETURN_UNKNOWN;
    }
    else
      return MineStat::RETURN_UNKNOWN;

    return MineStat::RETURN_SUCCESS;
  }

  /*
   * 1.8b/1.3
   * 1.8 beta through 1.3 servers communicate as follows for a ping request:
   * 1. Client sends \xFE (server list ping)
   * 2. Server responds with:
   *   2a. \xFF (kick packet)
   *   2b. data length
   *   2c. 3 fields delimited by \u00A7 (section symbol)
   * The 3 fields, in order, are: message of the day, current players, and max players
   */
  public function beta_request()
  {
    try
    {
      $this->request_type = "SLP 1.8b/1.3 (beta)";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start the handshake and attempt to acquire data
      socket_write($this->socket, "\xFE");
      $retval = $this->parse_data("\xA7", true);
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }

    return $retval;
  }

  /*
   * 1.4/1.5
   * 1.4 and 1.5 servers communicate as follows for a ping request:
   * 1. Client sends:
   *   1a. \xFE (server list ping)
   *   1b. \x01 (server list ping payload)
   * 2. Server responds with:
   *   2a. \xFF (kick packet)
   *   2b. data length
   *   2c. 6 fields delimited by \x00 (null)
   * The 6 fields, in order, are: the section symbol and 1, protocol version,
   * server version, message of the day, current players, and max players.
   * The protocol version corresponds with the server version and can be the
   * same for different server versions.
   */
  public function legacy_request()
  {
    try
    {
      $this->request_type = "SLP 1.4/1.5 (legacy)";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start the handshake and attempt to acquire data
      socket_write($this->socket, "\xFE\x01");
      $retval = $this->parse_data("\x00");
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }

    return $retval;
  }

  /*
   * 1.6
   * 1.6 servers communicate as follows for a ping request:
   * 1. Client sends:
   *   1a. \xFE (server list ping)
   *   1b. \x01 (server list ping payload)
   *   1c. \xFA (plugin message)
   *   1d. \x00\x0B (11 which is the length of "MC|PingHost")
   *   1e. "MC|PingHost" encoded as a UTF-16BE string
   *   1f. length of remaining data as a short: remote address (encoded as UTF-16BE) + 7
   *   1g. arbitrary 1.6 protocol version (\x4E for example for 78)
   *   1h. length of remote address as a short
   *   1i. remote address encoded as a UTF-16BE string
   *   1j. remote port as an int
   * 2. Server responds with:
   *   2a. \xFF (kick packet)
   *   2b. data length
   *   2c. 6 fields delimited by \x00 (null)
   * The 6 fields, in order, are: the section symbol and 1, protocol version,
   * server version, message of the day, current players, and max players.
   * The protocol version corresponds with the server version and can be the
   * same for different server versions.
   */
  public function extended_legacy_request()
  {
    try
    {
      $this->request_type = "SLP 1.6 (extended legacy)";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start the handshake and attempt to acquire data
      socket_write($this->socket, "\xFE\x01\xFA");
      socket_write($this->socket, "\x00\x0B");                                     // 11 (length of "MC|PingHost")
      socket_write($this->socket, mb_convert_encoding("MC|PingHost", "UTF-16BE")); // requires PHP mbstring
      socket_write($this->socket, pack('n', (7 + 2 * strlen($this->address))));
      socket_write($this->socket, "\x4E");                                         // 78 (protocol version of 1.6.4)
      socket_write($this->socket, pack('n', strlen($this->address)));
      socket_write($this->socket, mb_convert_encoding($this->address, "UTF-16BE"));
      socket_write($this->socket, pack('N', $this->port));
      $retval = $this->parse_data("\x00");
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }

    return $retval;
  }

  /*
   * 1.7
   * 1.7 to current servers communicate as follows for a ping request:
   * 1. Client sends:
   *   1a. \x00 (handshake packet containing the fields specified below)
   *   1b. \x00 (request)
   * The handshake packet contains the following fields respectively:
   *   1. protocol version as a varint (\x00 suffices)
   *   2. remote address as a string
   *   3. remote port as an unsigned short
   *   4. state as a varint (should be 1 for status)
   * 2. Server responds with:
   *   2a. \x00 (JSON response)
   * An example JSON string contains:
   *   {'players': {'max': 20, 'online': 0},
   *   'version': {'protocol': 404, 'name': '1.13.2'},
   *   'description': {'text': 'A Minecraft Server'}}
   */
  public function json_request()
  {
    try
    {
      $this->request_type = "SLP 1.7 (JSON)";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start handshake
      $payload = "\x00\x00";
      $payload .= pack('c', strlen($this->address)) . $this->address;
      $payload .= pack('n', $this->port);
      $payload .= "\x01";
      $payload = pack('c', strlen($payload)) . $payload;
      socket_write($this->socket, $payload);
      socket_write($this->socket, "\x01\x00");

      // Acquire data
      $total_len = $this->unpack_varint();
      if($this->unpack_varint() != 0)
        return MineStat::RETURN_UNKNOWN;
      $json_len = $this->unpack_varint();
      socket_recv($this->socket, $response, $json_len, MSG_WAITALL);
      socket_close($this->socket);
      $json_data = json_decode($response, true);
      if(json_last_error() != 0)
      {
        //echo(json_last_error_msg());
        return MineStat::RETURN_UNKNOWN;
      }
      $this->json_data = $json_data;

      // Parse data
      //var_dump($json_data);
      $this->protocol = (int)@$json_data['version']['protocol'];
      $this->version = @$json_data['version']['name'];
      $this->motd = @$json_data['description'];
      $this->strip_motd();
      $this->current_players = (int)@$json_data['players']['online'];
      $this->max_players = (int)@$json_data['players']['max'];
      if(isset($this->version) && isset($this->motd) && isset($this->current_players) && isset($this->max_players))
        $this->online = true;
      else
        return MineStat::RETURN_UNKNOWN;
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }
    return MineStat::RETURN_SUCCESS;
  }

  /* Returns value of varint type */
  private function unpack_varint()
  {
    $vint = 0;
    for($i = 0; $i <= MineStat::MAX_VARINT_SIZE; $i++)
    {
      $data = socket_read($this->socket, 1);
      if(!$data)
        return 0;
      $data = ord($data);
      $vint |= ($data & 0x7F) << $i++ * 7;
      if(($data & 0x80) != 128)
        break;
    }
    return $vint;
  }

  /*
   * Bedrock/Pocket Edition servers communicate as follows for an unconnected ping request:
   * 1. Client sends:
   *   1a. \x01 (unconnected ping packet containing the fields specified below)
   *   1b. current time as a long
   *   1c. magic number
   *   1d. client GUID as a long
   * 2. Server responds with:
   *   2a. \x1c (unconnected pong packet containing the follow fields)
   *   2b. current time as a long
   *   2c. server GUID as a long
   *   2d. 16-bit magic number
   *   2e. server ID string length
   *   2f. server ID as a string
   * The fields from the pong response, in order, are:
   *   - edition
   *   - MotD line 1
   *   - protocol version
   *   - version name
   *   - current player count
   *   - maximum player count
   *   - unique server ID
   *   - MotD line 2
   *   - game mode as a string
   *   - game mode as a numeric
   *   - IPv4 port number
   *   - IPv6 port number
   */
  public function bedrock_request()
  {
    try
    {
      $this->request_type = "Bedrock/Pocket Edition";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Perform handshake and acquire data
      $payload = "\x01";                                                              // unconnected ping
      $payload .= pack('P', time());                                                  // current time
      $payload .= "\x00\xFF\xFF\x00\xFE\xFE\xFE\xFE\xFD\xFD\xFD\xFD\x12\x34\x56\x78"; // magic number
      $payload .= pack('P', 2);                                                       // client GUID
      socket_write($this->socket, $payload);
      $retval = $this->parse_data("\x3B"); // semicolon
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }
    return $retval;
  }
}
?>
