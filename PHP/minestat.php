<?php
/*
 * minestat.php - A Minecraft server status checker
 * Copyright (C) 2014-2023 Lloyd Dilley
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
  const VERSION = "3.0.0";            // MineStat version
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
  /*
   * UT3/GS4 query handshake packet size in bytes (1 + 4 + 13)
   * Handshake (0x09) = 1 byte
   * Session ID = 4 bytes
   * Challenge token = variable null-terminated string up to 13 bytes(?)
   */
  const QUERY_HANDSHAKE_SIZE = 18;
  /*
   * UT3/GS4 query handshake packet offset for challenge token in bytes (1 + 4)
   * Handshake (0x09) = 1 byte
   * Session ID = 4 bytes
   */
  const QUERY_HANDSHAKE_OFFSET = 5;
  /*
   * UT3/GS4 query full stat packet offset in bytes (1 + 4 + 11)
   * Stat (0x00) = 1 byte
   * Session ID = 4 bytes
   * Padding = 11 bytes
   */
  const QUERY_STAT_OFFSET = 16;

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
  const REQUEST_QUERY = 5;            // Unreal Tournament 3/GameSpy 4 query

  private $address;                   // hostname or IP address of the Minecraft server
  private $port;                      // port number the Minecraft server accepts connections on
  private $srv_address;               // server address from DNS SRV record
  private $srv_port;                  // server TCP port from DNS SRV record
  private $online;                    // online or offline?
  private $version;                   // Minecraft server version
  private $mode;                      // game mode (Bedrock/Pocket Edition only)
  private $motd;                      // message of the day
  private $stripped_motd;             // message of the day without formatting
  private $current_players;           // current number of players online
  private $max_players;               // maximum player capacity
  private $player_list;               // list of players (UT3/GS4 query only)
  private $plugin_list;               // list of plugins (UT3/GS4 query only)
  private $protocol;                  // protocol level
  private $json_data;                 // JSON data for 1.7 queries
  private $favicon_b64;               // base64-encoded favicon possibly contained in JSON 1.7 responses
  private $favicon;                   // decoded favicon data
  private $latency;                   // ping time to server in milliseconds
  private $timeout;                   // timeout in seconds
  private $socket;                    // network socket
  private $request_type;              // protocol version
  private $connection_status;         // status of connection ("Success", "Fail", "Timeout", or "Unknown")
  private $try_all;                   // try all protocols?
  private $srv_enabled;               // enable SRV resolution?
  private $srv_succeeded;             // SRV resolution successful?

  public function __construct($address, $port = MineStat::DEFAULT_TCP_PORT, $timeout = MineStat::DEFAULT_TIMEOUT, $request_type = MineStat::REQUEST_NONE, $srv_enabled = true)
  {
    $this->address = $address;
    $this->port = $port;
    $this->timeout = $timeout;
    $this->online = false;
    if($request_type == MineStat::REQUEST_NONE)
      $this->try_all = true;
    $this->srv_enabled = $srv_enabled;
    $this->srv_succeeded = false;
    $retval = "";

    if($this->srv_enabled)
      $this->srv_succeeded = $this->resolve_srv();

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
      case MineStat::REQUEST_QUERY:
        $this->query_request();
        break;
      default:
        $retval = $this->legacy_request();            // SLP 1.4/1.5
        if($retval != MineStat::RETURN_SUCCESS && $retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->beta_request();            // SLP 1.8b/1.3
        if($retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->extended_legacy_request(); // SLP 1.6
        if($retval != MineStat::RETURN_CONNFAIL)
          $retval = $this->json_request();            // SLP 1.7
        if(!$this->is_online())
          $retval = $this->bedrock_request();         // Bedrock/Pocket Edition
        if(!$this->is_online())
          $retval = $this->query_request();           // UT3/GS4 query
    }
    if($this->is_online())
      $this->set_connection_status(MineStat::RETURN_SUCCESS);
    else
      $this->set_connection_status($retval);
  }

  public function get_address() { return $this->address; }

  public function get_port() { return $this->port; }

  public function get_srv_address() { return $this->srv_address; }

  public function get_srv_port() { return $this->srv_port; }

  public function is_online() { return $this->online; }

  public function get_version() { return $this->version; }

  public function get_mode() { return $this->mode; }

  public function get_motd() { return $this->motd; }

  public function get_stripped_motd() { return $this->stripped_motd; }

  public function get_current_players() { return $this->current_players; }

  public function get_max_players() { return $this->max_players; }

  public function get_player_list() { return $this->player_list; }

  public function get_plugin_list() { return $this->plugin_list; }

  public function get_protocol() { return $this->protocol; }

  public function get_json() { return $this->json_data; }

  public function get_favicon_b64() { return $this->favicon_b64; }

  public function get_favicon() { return $this->favicon; }

  public function get_latency() { return $this->latency; }

  public function get_request_type() { return $this->request_type; }

  public function get_connection_status() { return $this->connection_status; }

  public function is_srv_enabled() { return $this->srv_enabled; }

  public function is_srv_success() { return $this->srv_succeeded; }

  /* Attempts to resolve DNS SRV records */
  private function resolve_srv()
  {
    try
    {
      $result = dns_get_record("_minecraft._tcp." . $this->address, DNS_SRV);
      if(!empty($result))
      {
        if(isset($result[0]['target']) && isset($result[0]['port']))
        {
          $this->srv_address = $result[0]['target'];
          $this->srv_port = $result[0]['port'];
          return true;
        }
        else
          return false;
      }
      else
        return false;
    }
    catch(Exception $e)
    {
      return false;
    }
  }

  /* Sets connection status */
  private function set_connection_status($retval)
  {
    if($retval == MineStat::RETURN_SUCCESS)
      $this->connection_status = "Success";
    if($retval == MineStat::RETURN_CONNFAIL)
      $this->connection_status = "Fail";
    if($retval == MineStat::RETURN_TIMEOUT)
      $this->connection_status = "Timeout";
    if($retval == MineStat::RETURN_UNKNOWN)
      $this->connection_status = "Unknown";
  }

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
    if($this->request_type == MineStat::REQUEST_BEDROCK || $this->request_type == "Bedrock/Pocket Edition" || $this->request_type == "UT3/GS4 Query")
    {
      if($this->port == MineStat::DEFAULT_TCP_PORT && $this->request_type != "UT3/GS4 Query" && $this->try_all)
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
    $connect_address;
    $connect_port;
    if($this->request_type != MineStat::REQUEST_BEDROCK && $this->request_type != "Bedrock/Pocket Edition" && $this->srv_enabled && $this->srv_succeeded)
    {
      $connect_address = $this->srv_address;
      $connect_port = $this->srv_port;
    }
    else
    {
      $connect_address = $this->address;
      $connect_port = $this->port;
    }
    while(!@socket_connect($this->socket, $connect_address, $connect_port))
    {
      if((time() - $time) >= $this->timeout)
      {
        socket_close($this->socket);
        return MineStat::RETURN_TIMEOUT;
      }
      usleep(0);
    }
    $result = @socket_connect($this->socket, $connect_address, $connect_port);
    $this->latency = round((microtime(true) - $start_time) * 1000);
    socket_set_block($this->socket);
    if($result === false && socket_last_error($this->socket) != SOCKET_EISCONN)
      return MineStat::RETURN_CONNFAIL;

    return MineStat::RETURN_SUCCESS;
  }

  /* Populates object fields after connecting */
  private function parse_data($delimiter, $is_beta = false)
  {
    if($this->request_type == "Bedrock/Pocket Edition" || $this->request_type == "UT3/GS4 Query")
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
    elseif($this->request_type == "UT3/GS4 Query" && !empty($response) && $response[1] == 0x00) // stat packet
    {
      $raw_data = substr(socket_read($this->socket, 4096), MineStat::QUERY_STAT_OFFSET);
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
      // Split on delimiter
      if($this->request_type == "UT3/GS4 Query")
        $server_info = explode("\x00\x00\x01player_\x00\x00", $raw_data);
      else
        $server_info = explode($delimiter, $raw_data);
      if(isset($server_info))
      {
        if($is_beta && sizeof($server_info) >= MineStat::NUM_FIELDS_BETA)
        {
          $this->version = ">=1.8b/1.3"; // since server does not return version, set it
          $this->motd = trim($server_info[0], "§");
          $this->strip_motd();
          $this->current_players = (int)trim($server_info[1], "§");
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
        elseif($this->request_type == "UT3/GS4 Query")
        {
          if(isset($server_info[1]) && !empty($server_info[1]))
            $this->player_list = explode($delimiter, $server_info[1]);
          // Convert values into friendly key names and value pairs
          $values = explode($delimiter, $server_info[0]);
          $count = count($values);
          $server_info = [];
          if($count > MineStat::NUM_FIELDS)
          {
            for($i = 0; $i < $count / 2; $i++)
            {
              $idx = $i * 2;
              $server_info[$values[$idx]] = $values[$idx + 1];
            }
          }
          if(isset($server_info["version"]))
            $this->version = $server_info["version"];
          if(isset($server_info["hostname"]))
          {
            $this->motd = $server_info["hostname"];
            $this->strip_motd();
          }
          if(isset($server_info["numplayers"]))
            $this->current_players = (int)$server_info["numplayers"];
          if(isset($server_info["maxplayers"]))
            $this->max_players = (int)$server_info["maxplayers"];
          if(isset($server_info["plugins"]) && !empty($server_info["plugins"]))
          {
            // Vanilla servers do not send a list of plugins.
            // Bukkit and derivatives send plugins in the form: Paper on 1.19.3-R0.1-SNAPSHOT: Essentials 2.19.7; EssentialsChat 2.19.7
            $this->plugin_list = explode(':', $server_info["plugins"]);
            if(count($this->plugin_list) > 1)
              $this->plugin_list = array_map('trim', explode(';', $this->plugin_list[1])); // remove leading/trailing whitespace
          }
          $this->online = true;
        }
        else // SLP
        {
          if(sizeof($server_info) >= MineStat::NUM_FIELDS)
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
          else
            return MineStat::RETURN_UNKNOWN;
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
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start the handshake and attempt to acquire data
      socket_write($this->socket, "\xFE");
      $retval = $this->parse_data("\xA7", true); // section symbol (§)
      if($retval == MineStat::RETURN_SUCCESS)
        $this->request_type = "SLP 1.8b/1.3 (beta)";
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
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      // Start the handshake and attempt to acquire data
      socket_write($this->socket, "\xFE\x01");
      $retval = $this->parse_data("\x00");
      if($retval == MineStat::RETURN_SUCCESS)
        $this->request_type = "SLP 1.4/1.5 (legacy)";
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
      if($retval == MineStat::RETURN_SUCCESS)
        $this->request_type = "SLP 1.6 (extended legacy)";
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
      $this->favicon_b64 = @$json_data['favicon'];
      if(isset($this->favicon_b64))
      {
        $this->favicon_b64 = explode("base64,", $this->favicon_b64);
        $this->favicon_b64 = $this->favicon_b64[1];
        $this->favicon = base64_decode($this->favicon_b64);
      }
      if(isset($this->version) && isset($this->motd) && isset($this->current_players) && isset($this->max_players))
        $this->online = true;
      else
        return MineStat::RETURN_UNKNOWN;
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }
    $this->request_type = "SLP 1.7 (JSON)";
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

  /*
   * Unreal Tournament 3/GameSpy 4 (UT3/GS4) query protocol
   *   1. Client sends:
   *     1a. 0xFE 0xFD (query identifier)
   *     1b. 0x09 (handshake)
   *     1c. arbitrary session ID (4 bytes)
   *   2. Server responds with:
   *     2a. 0x09 (handshake)
   *     2b. session ID (4 bytes)
   *     2c. challenge token (variable null-terminated string)
   *   3. Client sends:
   *     3a. 0xFE 0xFD (query identifier)
   *     3b. 0x00 (stat)
   *     3c. arbitrary session ID (4 bytes)
   *     3d. challenge token (32-bit integer in network byte order)
   *     3e. padding (4 bytes -- 0x00 0x00 0x00 0x00); omit padding for basic stat (which does not supply the version)
   *   4. Server responds with:
   *     4a. 0x00 (stat)
   *     4b. session ID (4 bytes)
   *     4c. padding (11 bytes)
   *     4e. key/value pairs of multiple null-terminated strings containing the fields below:
   *         hostname, game type, game ID, version, plugin list, map, current players, max players, port, address
   *     4f. padding (10 bytes)
   *     4g. list of null-terminated strings containing player names
   */
  public function query_request()
  {
    try
    {
      $this->request_type = "UT3/GS4 Query";
      $retval = $this->connect();
      if($retval != MineStat::RETURN_SUCCESS)
        return $retval;
      $payload = "\xFE\xFD\x09\x0B\x03\x03\x0F";
      socket_write($this->socket, $payload);
      $start_byte = "";
      socket_recv($this->socket, $start_byte, 1, MSG_PEEK);
      if(isset($start_byte) && unpack('C', $start_byte)[1] == 0x09) // query handshake packet
      {
        // Session ID generated by the server is not used -- use a static session ID instead such as 0x0B 0x03 0x03 0x0F.
        //socket_recv($this->socket, $session_id, MineStat::QUERY_HANDSHAKE_OFFSET, MSG_PEEK);
        //$session_id = unpack('N', substr($session_id, 1));
        socket_recv($this->socket, $challenge_token, MineStat::QUERY_HANDSHAKE_SIZE, MSG_WAITALL);
        $challenge_token = substr($challenge_token, MineStat::QUERY_HANDSHAKE_OFFSET);
        $payload = "\xFE\xFD\x00\x0B\x03\x03\x0F";
        // Use the full stat below by stripping the null terminator from the challenge token and padding the end
        // of the payload with "\x00\x00\x00\x00". The basic stat response does not include the server version.
        $payload .= pack('N', $challenge_token);
        $payload .= "\x00\x00\x00\x00";
        socket_write($this->socket, $payload);
      }
      $retval = $this->parse_data("\x00"); // null
    }
    catch(Exception $e)
    {
      return MineStat::RETURN_UNKNOWN;
    }
    return $retval;
  }
}
?>
