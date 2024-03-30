/*
 * minestat.js - A Minecraft server status checker
 * Copyright (C) 2016, 2022 Lloyd Dilley, 2023 Kolya Venturi
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

const VERSION = "2.0.0";    // MineStat version
const NUM_FIELDS = 6;       // number of values expected from server
const DEFAULT_PORT = 25565; // default TCP port of Minecraft server
const DEFAULT_TIMEOUT = 5;  // default TCP timeout in seconds

function func(opts, callback)
{
  const {address, port = DEFAULT_PORT, timeout = DEFAULT_TIMEOUT} = opts;
  var res = {};
  res.address = address;
  res.port = port;
  res.online = false;

  const net = require('net');
  var start_time = new Date();
  const client = net.connect(port, address, () =>
  {
    res.latency = Math.round(new Date() - start_time);
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
        res.online = true;
        res.version = server_info[2].replace(/\u0000/g,'');
        res.motd = server_info[3].replace(/\u0000/g,'');
        res.current_players = Number(server_info[4].replace(/\u0000/g,''));
        res.max_players = Number(server_info[5].replace(/\u0000/g,''));
      }
      else
      {
        res.online = false;
      }
    }
    callback(undefined, res);
    client.end();
  });

  client.on('timeout', () =>
  {
    callback(new Error('Client timed out during request'));
    client.end();
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
      console.log("Unable to resolve " + res.address + ".");
      return;
    }

    if(err.code == "ECONNREFUSED")
    {
      console.log("Unable to connect to port " + res.port + ".");
      return;
    }
    */

    callback(err);

    // Uncomment the line below for more details pertaining to network errors.
    //console.log(err);
  });
}

module.exports =
{
  VERSION: VERSION,
  init: async function(opts)
  {
    return new Promise(function(resolve, reject)
    {
      func(opts, (error, result) =>
      {
        if(error)
        {
          reject(error);
        }
        else
        {
          resolve(result);
        }
      });
    });
  },
  initSync: function(opts, callback)
  {
    return func(opts, callback);
  }
};