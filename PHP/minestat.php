<?php
/*
 * minestat.php - A Minecraft server status checker
 * Copyright (C) 2014-2021 Lloyd Dilley
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
  const VERSION = "2.0.1";   // MineStat version
  const NUM_FIELDS = 6;      // number of values expected from server
  const NUM_FIELDS_BETA = 3; // number of values expected from a 1.8b/1.3 server
  const MAX_VARINT_SIZE = 5; // maximum number of bytes a varint can be
  // No enums or class nesting in PHP, so this is our workaround for return values
  const RETURN_SUCCESS = 0;
  const RETURN_CONNFAIL = -1;
  const RETURN_TIMEOUT = -2;
  const RETURN_UNKNOWN = -3;
  private $address;         // hostname or IP address of the Minecraft server
  private $port;            // port number the Minecraft server accepts connections on
  private $online;          // online or offline?
  private $version;         // Minecraft server version
  private $motd;            // message of the day
  private $current_players; // current number of players online
  private $max_players;     // maximum player capacity
  private $protocol;        // protocol level
  private $json_data;       // JSON data for 1.7 queries
  private $latency;         // ping time to server in milliseconds
  private $timeout;         // timeout in seconds
  private $socket;          // network socket

  public function __construct($address, $port = 25565, $timeout = 5)
  {
    $this->address = $address;
    $this->port = $port;
    $this->timeout = $timeout;
    $this->online = false;

    $retval = $this->json_query();     // 1.7
    if($retval != MineStat::RETURN_SUCCESS && $retval != MineStat::RETURN_CONNFAIL)
      $retval = $this->new_query();    // 1.6
    if($retval != MineStat::RETURN_SUCCESS && $retval != MineStat::RETURN_CONNFAIL)
      $retval = $this->legacy_query(); // 1.4/1.5
    if($retval != MineStat::RETURN_SUCCESS && $retval != MineStat::RETURN_CONNFAIL)
      $retval = $this->beta_query();   // 1.8b/1.3
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

  public function get_motd() { return $this->motd; }

  public function get_current_players() { return $this->current_players; }

  public function get_max_players() { return $this->max_players; }

  public function get_protocol() { return $this->protocol; }

  public function get_json() { return $this->json_data; }

  public function get_latency() { return $this->latency; }

  /* Connects to remote server */
  private function connect()
  {
    $this->socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
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
    $response = @unpack('C', socket_read($this->socket, 1));
    //socket_recv($this->socket, $response, 2, MSG_PEEK);
    if(!empty($response) && $response[1] == 0xFF) // kick packet (255)
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
          $this->version = "1.8b/1.3"; // since server does not return version, set it
          $this->motd = $server_info[0];
          $this->current_players = (int)$server_info[1];
          $this->max_players = (int)$server_info[2];
          $this->online = true;
        }
        else
        {
          // $server_info[0] contains the section symbol and 1
          $this->protocol = (int)$server_info[1]; // contains the protocol version (51 for 1.9 or 78 for 1.6.4 for example)
          $this->version = $server_info[2];
          $this->motd = $server_info[3];
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
   * 1.8 beta through 1.3 servers communicate as follows for a ping query:
   * 1. Client sends \xFE (server list ping)
   * 2. Server responds with:
   *   2a. \xFF (kick packet)
   *   2b. data length
   *   2c. 3 fields delimited by \u00A7 (section symbol)
   * The 3 fields, in order, are: message of the day, current players, and max players
   */
  public function beta_query()
  {
    try
    {
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
   * 1.4 and 1.5 servers communicate as follows for a ping query:
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
  public function legacy_query()
  {
    try
    {
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
   * 1.6 servers communicate as follows for a ping query:
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
  public function new_query()
  {
    try
    {
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
   * 1.7 to current servers communicate as follows for a ping query:
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
  public function json_query()
  {
    try
    {
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
      $this->motd = @$json_data['description']['text'];
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
}
?>
