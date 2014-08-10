/*
 * $Id$
 * MineStat - A Minecraft server status checker
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

using System;
using System.IO;
using System.Net.Sockets;
using System.Text;

public class MineStat
{
  const ushort dataSize = 512; // this will hopefully suffice since the MotD should be <=59 characters
  const ushort numFields = 6;  // number of values expected from server
  private string address;
  private ushort port;
  private bool serverUp;
  private string motd;
  private string version;
  private string currentPlayers;
  private string maximumPlayers;

  public MineStat(string address, ushort port)
  {
    byte[] rawServerData = new byte[dataSize];
    string[] serverData;

    SetAddress(address);
    SetPort(port);

    try
    {
      TcpClient tcpclient = new TcpClient();
      tcpclient.Connect(address, port);
      Stream stream = tcpclient.GetStream();
      byte[] payload = { 0xFE, 0x01 };
      stream.Write(payload, 0, payload.Length);
      stream.Read(rawServerData, 0, dataSize);
      tcpclient.Close();
    }
    catch(Exception)
    {
      serverUp = false;
    }

    if(rawServerData == null)
      serverUp = false;
    else
    {
      serverData = Encoding.Unicode.GetString(rawServerData).Split("\u0000\u0000\u0000".ToCharArray());
      if(serverData != null && serverData.Length >= numFields)
      {
        serverUp = true;
        SetVersion(serverData[2]);
        SetMotd(serverData[3]);
        SetCurrentPlayers(serverData[4]);
        SetMaximumPlayers(serverData[5]);
      }
      else
        serverUp = false;
    }
  }

  public string GetAddress()
  {
    return address;
  }

  public void SetAddress(string address)
  {
    this.address = address;
  }

  public ushort GetPort()
  {
    return port;
  }

  public void SetPort(ushort port)
  {
    this.port = port;
  }

  public string GetMotd()
  {
    return motd;
  }

  public void SetMotd(string motd)
  {
    this.motd = motd;
  }

  public string GetVersion()
  {
    return version;
  }

  public void SetVersion(string version)
  {
    this.version = version;
  }

  public string GetCurrentPlayers()
  {
    return currentPlayers;
  }

  public void SetCurrentPlayers(string currentPlayers)
  {
    this.currentPlayers = currentPlayers;
  }

  public string GetMaximumPlayers()
  {
    return maximumPlayers;
  }

  public void SetMaximumPlayers(string maximumPlayers)
  {
    this.maximumPlayers = maximumPlayers;
  }

  public bool IsServerUp()
  {
    return serverUp;
  }
}
