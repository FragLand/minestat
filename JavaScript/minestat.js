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

const NUM_FIELDS = 6;      // number of values expected from server
const DEFAULT_TIMEOUT = 5; // default TCP timeout in seconds
address = null;
port = null;
online = null;             // online or offline?
version = null;            // server version
motd = null;               // message of the day
current_players = null;    // current number of players online
max_players = null;        // maximum player capacity
latency = null;            // ping time to server in milliseconds

module.exports =
{
  init: function(address, port, timeout, callback)
  {
    this.address = address;
    this.port = port;

    // if 3rd argument is a function, it's the callback (timeout is optional)
    if(typeof(timeout) === typeof(Function()))
    {
      callback = timeout;
      timeout = DEFAULT_TIMEOUT;
    }

    const net = require('net');
    var start_time = new Date();
    const client = net.connect(port, address, () =>
    {
      this.latency = Math.round(new Date() - start_time);
      var buff = Buffer.from([ 0xFE, 0x01 ]);
      client.write(buff);
    });

    client.setTimeout(timeout * 1000);

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

    client.on('timeout', () =>
    {
      callback();
      client.end();
      process.exit();
    });

    client.on('end', () =>
    {
      // nothing needed here
    });

    client.on('error', (err) =>
    {
      // Uncomment the lines below to handle error codes individually. Otherwise,
      // call callback() and simply report the remote server as being offline.

      /*
      if(err.code == "ENOTFOUND")
      {
        console.log("Unable to resolve " + this.address + ".");
        return;
      }

      if(err.code == "ECONNREFUSED")
      {
        console.log("Unable to connect to port " + this.port + ".");
        return;
      }
      */

      callback();

      // Uncomment the line below for more details pertaining to network errors.
      //console.log(err);
    });
  }
};
