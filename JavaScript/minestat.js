/*
 * minestat.js - A Minecraft server status checker
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

// For use with Node.js

const NUM_FIELDS = 6;   // number of values expected from server
address = null;
port = null;
online = null;          // online or offline?
version = null;         // server version
motd = null;            // message of the day
current_players = null; // current number of players online
max_players = null;     // maximum player capacity

module.exports =
{
  init: function(address, port, callback)
  {
    this.address = address;
    this.port = port;

    const net = require('net');
    // ToDo: Add timeout
    //client = new net.Socket();
    //client.setTimeout(7000);
    //client.connect(port, address, () =>
    const client = net.connect(port, address, () =>
    {
      var buff = new Buffer([ 0xFE, 0x01 ]);
      client.write(buff);
    });

    client.on('data', (data) =>
    {
      if(data != null && data != '')
      {
        var server_info = data.toString().split("\x00\x00\x00");
        if(server_info != null && server_info.length >= NUM_FIELDS)
        {
          this.online = true;
          this.version = server_info[2].replace(/\u0000/g,'');
          this.motd = server_info[3].replace(/\u0000/g,'');
          this.current_players = server_info[4].replace(/\u0000/g,'');
          this.max_players = server_info[5].replace(/\u0000/g,'');
        }
        else
        {
          this.online = false;
        }
      }
      callback();
      client.end();
    });

    client.on('end', () =>
    {
      // nothing needed here
    });

    client.on('error', (err) =>
    {
      console.log(err);
    });
  }
};
