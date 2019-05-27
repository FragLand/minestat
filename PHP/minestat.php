<?php
/*
 * minestat.php - A Minecraft server status checker
 * Copyright (C) 2014 Lloyd Dilley
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
  const DATA_SIZE = 512;    // this will hopefully suffice since the MotD should be <=59 characters
  const NUM_FIELDS = 6;     // number of values expected from server
  private $address;
  private $port;
  private $online;          // online or offline?
  private $version;         // Minecraft server version
  private $motd;            // message of the day
  private $current_players; // current number of players online
  private $max_players;     // maximum player capacity
  private $latency;         // ping time to server in milliseconds

  public function __construct($address, $port, $timeout = 5)
  {
    $this->address = $address;
    $this->port = $port;

    try
    {
      $socket = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
      socket_set_option($socket, SOL_SOCKET, SO_RCVTIMEO, array('sec' => $timeout, 'usec' => 0));
      if($socket === false)
      {
        $this->online = false;
        return;
      }
      $start_time = microtime();
      $result = socket_connect($socket, $address, $port);
      $this->latency = round((microtime() - $start_time) * 1000);
      if($result === false)
      {
        $this->online = false;
        return;
      }
      $payload = "\xFE\x01";
      socket_write($socket, $payload, strlen($payload));
      $raw_data = socket_read($socket, MineStat::DATA_SIZE);
      socket_close($socket);
    }
    catch(Exception $e)
    {
      $this->online = false;
      return;
    }

    if(isset($raw_data))
    {
      $server_info = explode("\x00\x00\x00", $raw_data);
      if(isset($server_info) && sizeof($server_info) >= MineStat::NUM_FIELDS)
      {
        $this->online = true;
        $this->version = $server_info[2];
        $this->motd = $server_info[3];
        $this->current_players = $server_info[4];
        $this->max_players = $server_info[5];
      }
      else
        $this->online = false;
    }
    else
      $this->online = false;
  }

  public function get_address()
  {
    return $this->address;
  }

  public function get_port()
  {
    return $this->port;
  }

  public function is_online()
  {
    return $this->online;
  }

  public function get_version()
  {
    return $this->version;
  }

  public function get_motd()
  {
    return $this->motd;
  }

  public function get_current_players()
  {
    return $this->current_players;
  }

  public function get_max_players()
  {
    return $this->max_players;
  }

  public function get_latency()
  {
    return $this->latency;
  }
}
?>
