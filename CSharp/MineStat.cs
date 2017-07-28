/*
 * MineStat.cs - A Minecraft server status checker
 * Copyright (C) 2014, 2016 Lloyd Dilley
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

using System;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Diagnostics;

public class MineStat
{
  const ushort dataSize = 512; // this will hopefully suffice since the MotD should be <=59 characters
  const ushort numFields = 6;  // number of values expected from server

  public string Address { get; set; }
  public ushort Port { get; set; }
  public string Motd { get; set; }
  public string Version { get; set; }
  public string CurrentPlayers { get; set; }
  public string MaximumPlayers { get; set; }
  public bool ServerUp { get; set; }
  public long Delay { get; set; }

  public MineStat(string address, ushort port)
  {
    var rawServerData = new byte[dataSize];

    Address = address;
    Port = port;

    try
    {
      // ToDo: Add timeout
      var stopWatch = new Stopwatch();
      var tcpclient = new TcpClient();
      stopWatch.Start();
      tcpclient.Connect(address, port);
      stopWatch.Stop();
      var stream = tcpclient.GetStream();
      var payload = new byte[] { 0xFE, 0x01 };
      stream.Write(payload, 0, payload.Length);
      stream.Read(rawServerData, 0, dataSize);
      tcpclient.Close();
      Delay = stopWatch.ElapsedMilliseconds;
    }
    catch(Exception)
    {
      ServerUp = false;
      return;
    }

    if(rawServerData == null || rawServerData.Length == 0)
    {
      ServerUp = false;
    }
    else
    {
      var serverData = Encoding.Unicode.GetString(rawServerData).Split("\u0000\u0000\u0000".ToCharArray());
      if(serverData != null && serverData.Length >= numFields)
      {
        ServerUp = true;
        Version = serverData[2];
        Motd = serverData[3];
        CurrentPlayers = serverData[4];
        MaximumPlayers = serverData[5];
      }
      else
      {
        ServerUp = false;
      }
    }
  }

  #region Obsolete

  [Obsolete]
  public string GetAddress()
  {
    return Address;
  }

  [Obsolete]
  public void SetAddress(string address)
  {
    Address = address;
  }

  [Obsolete]
  public ushort GetPort()
  {
    return Port;
  }

  [Obsolete]
  public void SetPort(ushort port)
  {
    Port = port;
  }

  [Obsolete]
  public string GetMotd()
  {
    return Motd;
  }

  [Obsolete]
  public void SetMotd(string motd)
  {
    Motd = motd;
  }

  [Obsolete]
  public string GetVersion()
  {
    return Version;
  }

  [Obsolete]
  public void SetVersion(string version)
  {
    Version = version;
  }

  [Obsolete]
  public string GetCurrentPlayers()
  {
    return CurrentPlayers;
  }

  [Obsolete]
  public void SetCurrentPlayers(string currentPlayers)
  {
    CurrentPlayers = currentPlayers;
  }

  [Obsolete]
  public string GetMaximumPlayers()
  {
    return MaximumPlayers;
  }

  [Obsolete]
  public void SetMaximumPlayers(string maximumPlayers)
  {
    MaximumPlayers = maximumPlayers;
  }

  [Obsolete]
  public bool IsServerUp()
  {
    return ServerUp;
  }

  #endregion
}
