/*
 * MineStat.cs - A Minecraft server status checker
 * Copyright (C) 2014-2021 Lloyd Dilley, 2021 Felix Ern (MindSolve)
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
using System.Collections.Generic;
using System.Net.Sockets;
using System.Text;
using System.Diagnostics;
using System.IO;
using System.Linq;

using LEB128;

namespace MineStatLib
{
  public class MineStat
  {
    public const string MineStatVersion = "2.0.0";
    private const int DefaultTimeout = 5; // default TCP timeout in seconds

    public string Address { get; set; }
    public ushort Port { get; set; }
    public int Timeout { get; set; }
    public string Motd { get; set; }
    public string Version { get; set; }
    public string CurrentPlayers => Convert.ToString(CurrentPlayersInt);
    public int CurrentPlayersInt { get; set; }
    public string MaximumPlayers => Convert.ToString(MaximumPlayersInt);
    public int MaximumPlayersInt { get; set; }
    public bool ServerUp { get; set; }
    public long Latency { get; set; }
    public SlpProtocol Protocol { get; set; }

    /// <summary>
    /// TODO: Document
    /// </summary>
    /// <param name="address">Address (hostname or IP) of Minecraft server to connect to</param>
    /// <param name="port">Port to connect to on the address</param>
    /// <param name="timeout">Timeout in seconds</param>
    public MineStat(string address, ushort port, int timeout = DefaultTimeout)
    {
      Address = address;
      Port = port;
      Timeout = timeout;
      
      /*
       * 1. Try JSON protocol
       * 2. Try extended legacy protocol
       * 3. Try legacy protocol
       * 4. Try beta protocol
       */
      
      // The order of protocols here is (sadly) important.
      // Some server versions (1.4seem to have trouble with newer protocols and stop responding for a few seconds.
      // If, for example, the ext.-legacy protocol triggers this problem, the following connections are dropped/reset
      // even if they would have worked individually/normally.
      // This arrangement is quite safe, first try the best protocol (json), then the most supported protocol (beta)
      // then the "better" protocols legacy and extended legacy.

      var result = QueryWithJsonProtocol();
      
      if (result != ConnStatus.Connfail && result != ConnStatus.Success)
      {
        result = QueryWithBetaProtocol();
        
        if (result != ConnStatus.Connfail) 
          result = QueryWithLegacyProtocol();
      
        if (result != ConnStatus.Connfail)
          result = QueryWithExtendedLegacyProtocol();
      }
      
    }

    public ConnStatus QueryWithJsonProtocol()
    {
      // TODO: Implement
      return ParseJsonProtocolPayload(null);
    }

    private ConnStatus ParseJsonProtocolPayload(byte[] rawPayload)
    {
      // TODO: Implement
      return ConnStatus.Unknown;
    }

    /// <summary>
    /// Minecraft 1.6 SLP query, extended legacy ping protocol.
    /// All modern servers are currently backwards compatible with this protocol.<br/>
    /// 
    /// See https://wiki.vg/Server_List_Ping#1.6
    /// </summary>
    /// <returns></returns>
    public ConnStatus QueryWithExtendedLegacyProtocol()
    {

      var tcpclient = new TcpClient {ReceiveTimeout = Timeout * 1000};

      try
      {
        var stopWatch = new Stopwatch();
        stopWatch.Start();
        tcpclient.Connect(Address, Port);
        stopWatch.Stop();
        Latency = stopWatch.ElapsedMilliseconds;
      }
      catch(Exception)
      {
        ServerUp = false;
        return ConnStatus.Connfail;
      }
      
      // Send ping packet with id 0xFE, and ping data 0x01
      // Then 0xFA as packet id for a plugin message
      // Then 0x00 0x0B as strlen of the following (hardcoded) string
      
      var extLegacyPingPacket = new List<byte> { 0xFE, 0x01, 0xFA, 0x00, 0x0B };
      
      // the string 'MC|PingHost' as UTF-16BE encoded string
      extLegacyPingPacket.AddRange(Encoding.BigEndianUnicode.GetBytes("MC|PingHost"));
      
      // 0xXX 0xXX byte count of rest of data, 7+len(Address), as short
      var reqByteLen = BitConverter.GetBytes(Convert.ToInt16(7 + (Address.Length * 2)));
      // Convert to Big-Endian
      if (BitConverter.IsLittleEndian)
        Array.Reverse(reqByteLen);
      extLegacyPingPacket.AddRange(reqByteLen);
      
      // 0xXX [legacy] protocol version (before netty rewrite)
      // Used here: 74 (MC 1.6.2)
      extLegacyPingPacket.Add(0x4A);
      
      // strlen of Address (big-endian short)
      var addressLen = BitConverter.GetBytes(Convert.ToInt16(Address.Length));
      // Convert to Bit-Endian      
      if (BitConverter.IsLittleEndian)
        Array.Reverse(addressLen);
      extLegacyPingPacket.AddRange(addressLen);

      // the hostname of the server (encoded as UTF16-BE)
      extLegacyPingPacket.AddRange(Encoding.BigEndianUnicode.GetBytes(Address));
      
      // port of the server, as int (4 byte)
      var port = BitConverter.GetBytes(Convert.ToUInt32(Port));
      // Convert to Bit-Endian      
      if (BitConverter.IsLittleEndian)
        Array.Reverse(port);
      extLegacyPingPacket.AddRange(port);
      
      var stream = tcpclient.GetStream();
      stream.Write(extLegacyPingPacket.ToArray(), 0, extLegacyPingPacket.Count);

      var responsePacketHeader = new byte[3];
      
      // Catch timeouts and other network race conditions
      // A timeout occurs if the server doesn't understand the ping packet
      // and tries to interpret it as something else
      try
      {
        stream.Read(responsePacketHeader, 0, 3);
      }
      catch (Exception)
      {
        return ConnStatus.Unknown;
      }

      // Check for response packet id
      if (responsePacketHeader[0] != 0xFF)
      {
        return ConnStatus.Unknown;
      }

      var payloadLengthRaw = responsePacketHeader.Skip(1);
      
      // Received data is Big-Endian, convert to local endianness, if needed
      if (BitConverter.IsLittleEndian)
        payloadLengthRaw = payloadLengthRaw.Reverse();
      // Get Payload string length
      var payloadLength = BitConverter.ToUInt16(payloadLengthRaw.ToArray(), 0);

      // Receive payload
      var payload = new byte[payloadLength * 2];
      stream.Read(payload, 0, payloadLength*2);

      // Close socket
      tcpclient.Close();
      
      return ParseLegacyProtocol(payload, SlpProtocol.ExtendedLegacy);
      
    }

    /// <summary>
    /// Minecraft 1.4-1.5 SLP query, server response contains more info than beta SLP.
    /// Quite simple to request, but contains all interesting information.
    /// Still works with modern server implementations.<br/>
    /// 
    /// See https://wiki.vg/Server_List_Ping#1.4_to_1.5
    /// </summary>
    /// <returns>ConnStatus</returns>
    public ConnStatus QueryWithLegacyProtocol()
    {
      var tcpclient = new TcpClient {ReceiveTimeout = Timeout * 1000};


      try
      {
        var stopWatch = new Stopwatch();
        stopWatch.Start();
        tcpclient.Connect(Address, Port);
        stopWatch.Stop();
        Latency = stopWatch.ElapsedMilliseconds;
      }
      catch(Exception)
      {
        ServerUp = false;
        return ConnStatus.Connfail;
      }
      
      
      // Send ping packet with id 0xFE, and ping data 0x01
      var stream = tcpclient.GetStream();
      var legacyPingPacket = new byte[] { 0xFE, 0x01 };
      stream.Write(legacyPingPacket, 0, legacyPingPacket.Length);

      var responsePacketHeader = new byte[3];
      
      // Catch timeouts or reset connections
      // This happens if the server doesn't understand the packet (unsupported protocol)
      try
      {
        stream.Read(responsePacketHeader, 0, 3);
      }
      catch (Exception)
      {
        return ConnStatus.Unknown;
      }
      
      // Check for response packet id
      if (responsePacketHeader[0] != 0xFF)
      {
        return ConnStatus.Unknown;
      }

      // Change Endianness to Big-Endian, if needed
      if (BitConverter.IsLittleEndian)
        Array.Reverse(responsePacketHeader);
      // Get Payload string length (ToUInt16 ignores everything after the first 2 bytes)
      var payloadLength = BitConverter.ToUInt16(responsePacketHeader, 0);

      // Receive payload
      var payload = new byte[payloadLength * 2];
      stream.Read(payload, 0, payloadLength*2);

      // Close socket
      tcpclient.Close();

      return ParseLegacyProtocol(payload, SlpProtocol.Legacy);
    }

    /// <summary>
    /// TODO:
    /// </summary>
    /// <param name="rawPayload"></param>
    /// <param name="protocol"></param>
    /// <returns></returns>
    private ConnStatus ParseLegacyProtocol(byte[] rawPayload, SlpProtocol protocol = SlpProtocol.ExtendedLegacy)
    {
      
      // Decode byte[] as UTF16BE
      var payloadString = Encoding.BigEndianUnicode.GetString(rawPayload, 0, rawPayload.Length);

      // This "payload" contains six fields delimited by a NUL character, see below
      var payloadArray = payloadString.Split('\0');
      
      // Check if we got the right amount of parts, expected is 6 for this protocol version
      if (payloadArray.Length != 6)
      {
        return ConnStatus.Unknown;
      }

      // This "payload" contains six fields delimited by a NUL character:
      // - a fixed prefix '§1' (ignored)
      // - the protocol version (ignored)
      // - the server version
      Version = payloadArray[2];
      
      // - the MOTD
      Motd = payloadArray[3];
      
      // - the online player count
      CurrentPlayersInt = Convert.ToInt32(payloadArray[4]);
      
      // - the max player count
      MaximumPlayersInt = Convert.ToInt32(payloadArray[5]);
      
      
      // If we got here, everything is in order
      ServerUp = true;
      Protocol = protocol;

      return ConnStatus.Success;
    }

    public ConnStatus QueryWithBetaProtocol()
    {
      var tcpclient = new TcpClient {ReceiveTimeout = Timeout * 1000};

      try
      {
        var stopWatch = new Stopwatch();
        stopWatch.Start();
        tcpclient.Connect(Address, Port);
        stopWatch.Stop();
        Latency = stopWatch.ElapsedMilliseconds;
      }
      catch(Exception)
      {
        ServerUp = false;
        return ConnStatus.Connfail;
      }
      
      // Send empty packet with id 0xFE
      var stream = tcpclient.GetStream();
      var betaPingPacket = new byte[] { 0xFE };
      stream.Write(betaPingPacket, 0, betaPingPacket.Length);

      var responsePacketHeader = new byte[3];
      stream.Read(responsePacketHeader, 0, 3);

      // Check for response packet id
      if (responsePacketHeader[0] != 0xFF)
      {
        return ConnStatus.Unknown;
      }

      // Change Endianness to Big-Endian, if needed
      if (BitConverter.IsLittleEndian)
        Array.Reverse(responsePacketHeader);
      // Get Payload string length (ToUInt16 ignores everything after the first 2 bytes)
      var payloadLength = BitConverter.ToUInt16(responsePacketHeader, 0);

      // Receive payload
      var payload = new byte[payloadLength * 2];
      stream.Read(payload, 0, payloadLength*2);

      // Close socket
      tcpclient.Close();

      return ParseBetaProtocol(payload);
    }

    private ConnStatus ParseBetaProtocol(byte[] rawPayload)
    {
      // Decode byte[] as UTF16BE
      var payloadString = Encoding.BigEndianUnicode.GetString(rawPayload, 0, rawPayload.Length);

      var payloadArray = payloadString.Split('§');
      
      // The payload contains 3 parts, separated by '§' (section sign)
      // If the MOTD contains §, there may be more parts here (we take care of that later)
      if (payloadArray.Length < 3)
      {
        return ConnStatus.Unknown;
      }
        
      // Max player count is the last element
      MaximumPlayersInt = Convert.ToInt32(payloadArray[payloadArray.Length-1]);
        
      // Current player count is second-to-last element
      CurrentPlayersInt = Convert.ToInt32(payloadArray[payloadArray.Length-2]);
        
      // Motd is first element, but may contain 'section sign' (the delimiter)
      Motd = String.Join("§", payloadArray.Take(payloadArray.Length - 2).ToArray());
      
      // If we got here, everything is in order
      ServerUp = true;
      Protocol = SlpProtocol.Beta;
      
      // This protocol does not provide the server version.
      Version = "<= 1.3";
      
      
      return ConnStatus.Success;
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
      CurrentPlayersInt = Convert.ToInt32(currentPlayers);
    }

    [Obsolete]
    public string GetMaximumPlayers()
    {
      return MaximumPlayers;
    }

    [Obsolete]
    public void SetMaximumPlayers(string maximumPlayers)
    {
      MaximumPlayersInt = Convert.ToInt32(maximumPlayers);
    }

    [Obsolete]
    public long GetLatency()
    {
      return Latency;
    }

    [Obsolete]
    public void SetLatency(long latency)
    {
      Latency = latency;
    }

    [Obsolete]
    public bool IsServerUp()
    {
      return ServerUp;
    }

    #endregion
  }
  
  /// <summary>
  /// Contains possible connection states.
  /// </summary>
  /// <list type="bullet">
  ///   <item>
  ///     <term>Success: </term>
  ///     <description>The specified SLP connection succeeded (Request and response parsing OK)</description>
  ///   </item>
  ///   <item>
  ///     <term>Connfail: </term>
  ///     <description>The socket to the server could not be established. (Server offline, wrong hostname or port?)</description>
  ///   </item>
  ///   <item>
  ///     <term>Timeout: </term>
  ///     <description>The connection timed out. (Server under too much load? Firewall rules OK?)</description>
  ///   </item>
  ///   <item>
  ///     <term>Unknown: </term>
  ///     <description>The connection was established, but the server spoke an unknown/unsupported SLP protocol.</description>
  ///   </item>
  /// </list>
  public enum ConnStatus
  {
    /// <summary>
    /// The specified SLP connection succeeded (Request and response parsing OK)
    /// </summary>
    Success,
    
    /// <summary>
    /// The socket to the server could not be established. (Server offline, wrong hostname or port?)
    /// </summary>
    Connfail,
    
    /// <summary>
    /// The connection timed out. (Server under too much load? Firewall rules OK?)
    /// </summary>
    Timeout,
    
    /// <summary>
    /// The connection was established, but the server spoke an unknown/unsupported SLP protocol.
    /// </summary>
    Unknown
  }

  /// <summary>
  /// Enum of possible SLP (Server List Ping) protocol versions.
  /// </summary>
  public enum SlpProtocol
  {
    /// <summary>
    /// The newest and currently supported SLP protocol.<br/>
    /// Uses (wrapped) JSON as payload. Complex query, see above <see cref="MineStat.QueryWithJsonProtocol"/>
    /// for the protocol implementation. <br/>
    /// <i>Available since Minecraft 1.7.</i>
    /// </summary>
    Json,
    
    /// <summary>
    /// The previous SLP protocol.<br/>
    /// Used by Minecraft 1.6, it is still supported by all newer server versions.
    /// Complex query needed, see implementation <see cref="MineStat.QueryWithExtendedLegacyProtocol"/> for all protocol
    /// details.<br/>
    /// <i>Available since Minecraft 1.6</i>
    /// </summary>
    ExtendedLegacy,
    
    /// <summary>
    /// The legacy SLP protocol.<br/>
    /// Used by Minecraft 1.4 and 1.5, it is the first protocol to contain the server version number.
    /// Very simple protocol call (2 byte), simple response decoding.
    /// See <see cref="MineStat.QueryWithLegacyProtocol"/> for full implementation and protocol details.<br/>
    /// <i>Available since Minecraft 1.4</i>
    /// </summary>
    Legacy,
    
    /// <summary>
    /// The first SLP protocol.<br/>
    /// Used by Minecraft Beta 1.8 till Release 1.3, it is the first SLP protocol.
    /// It contains very few details, no server version info, only MOTD, max- and online player counts.<br/>
    /// <i>Available since Minecraft Beta 1.8</i>
    /// </summary>
    Beta
  }
  
}
