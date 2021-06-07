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
using System.Runtime.Serialization.Json;
using System.Xml.Linq;
using System.Xml.XPath;

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
    /// MineStat is a Minecraft server status checker.<br/>
    /// After object creation, the appropriate SLP (server list ping) protocol will be automatically chosen based on the
    /// server version and all fields will be populated.
    /// </summary>
    /// <example>
    /// <code>
    /// MineStat ms = new MineStat("minecraft.frag.land", 25565);
    /// Console.WriteLine("The server is" + ms.ServerUp ? "online!" : "offline!");
    /// </code>
    /// </example>
    /// <param name="address">Address (hostname or IP) of Minecraft server to connect to</param>
    /// <param name="port">Port to connect to on the address</param>
    /// <param name="timeout">(Optional) Timeout in seconds</param>
    /// <param name="protocol">(Optional) SLP protocol to use, defaults to automatic detection</param>
    public MineStat(string address, ushort port, int timeout = DefaultTimeout, SlpProtocol protocol = SlpProtocol.Automatic)
    {
      Address = address;
      Port = port;
      Timeout = timeout;
      
      // If the user manually selected a protocol, use that
      switch (protocol)
      {
        case SlpProtocol.Beta:
          RequestWithBetaProtocol();
          break;
        case SlpProtocol.Legacy:
          RequestWithLegacyProtocol();
          break;
        case SlpProtocol.ExtendedLegacy:
          RequestWithExtendedLegacyProtocol();
          break;
        case SlpProtocol.Json:
          RequestWithJsonProtocol();
          break;
        case SlpProtocol.Automatic:
          break;
        default:
          throw new ArgumentOutOfRangeException(nameof(protocol), "Invalid SLP protocol specified for parameter 'protocol'");
      }
      
      // If a protocol was chosen manually, return
      if (protocol != SlpProtocol.Automatic)
      {
        return;
      }
      
      // The order of protocols here is (sadly) important.
      // Some server versions (1.3, 1.4) seem to have trouble with newer protocols and stop responding for a few seconds.
      // If, for example, the ext.-legacy protocol triggers this problem, the following connections are dropped/reset
      // even if they would have worked individually/normally.
      // For more information, see https://github.com/FragLand/minestat/issues/70
      //
      // 1.: Legacy (1.4, 1.5)
      // 2.: Beta (b1.8-rel1.3)
      // 3.: Extended Legacy (1.6)
      // 4.: JSON (1.7+)
      
      var result = RequestWithLegacyProtocol();
      
      if (result != ConnStatus.Connfail && result != ConnStatus.Success)
      {
        result = RequestWithBetaProtocol();
        
        if (result != ConnStatus.Connfail)
          result = RequestWithExtendedLegacyProtocol();

        if (result != ConnStatus.Connfail && result != ConnStatus.Success)
          RequestWithJsonProtocol();
      }
    }

    /// <summary>
    /// Requests the server data with the Minecraft 1.7+ SLP protocol. In use by all modern Minecraft clients.
    /// Complicated to construct.<br/>
    /// See https://wiki.vg/Server_List_Ping#Current
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Json"/>
    public ConnStatus RequestWithJsonProtocol()
    {
      TcpClient tcpclient;
      
      try
      {
        tcpclient = TcpClientWrapper();
      }
      catch(Exception)
      {
        ServerUp = false;
        return ConnStatus.Connfail;
      }
      
      // Construct handshake packet
      // - The packet length (packet id + data) as VarInt [prepended at the end]
      // - The packet id 0x00
      var jsonPingHandshakePacket = new List<byte> { 0x00 };
      
      // - The protocol version of the client (by convention -1 if used to request the server version); as VarInt
      jsonPingHandshakePacket.AddRange(WriteLeb128(-1));
      
      // - The server address (after SRV redirect) as UTF8 string; prefixed by the byte count
      var serverAddr = Encoding.UTF8.GetBytes(Address);
      jsonPingHandshakePacket.AddRange(WriteLeb128(serverAddr.Length));
      jsonPingHandshakePacket.AddRange(serverAddr);
      
      // - The server port; as unsigned 16-bit integer (short)
      var serverPort = BitConverter.GetBytes(Port);
      // Convert to Big-Endian
      if (BitConverter.IsLittleEndian)
        Array.Reverse(serverPort);
      // Append to packet
      jsonPingHandshakePacket.AddRange(serverPort);
      
      // - Next state: 1 (status/ping); as VarInt
      jsonPingHandshakePacket.AddRange(WriteLeb128(1));
      
      // - Prepend the packet length (packet id + data) as VarInt
      jsonPingHandshakePacket.InsertRange(0, WriteLeb128(jsonPingHandshakePacket.Count));
      
      // Send handshake packet
      var stream = tcpclient.GetStream();
      stream.Write(jsonPingHandshakePacket.ToArray(), 0, jsonPingHandshakePacket.Count);

      // Send request packet (packet len as VarInt, empty packet with ID 0x00)
      WriteLeb128Stream(stream, 1);
      stream.WriteByte(0x00);
      
      // Receive response
      
      // Catch timeouts and other network exceptions
      // A timeout occurs if the server doesn't understand the ping packet
      // and tries to interpret it as something else
      int responseSize;
      try
      {
        responseSize = ReadLeb128Stream(stream);
      }
      catch (Exception)
      {
        return ConnStatus.Unknown;
      }

      // Check if full packet size is reasonable
      if (responseSize < 3)
      {
        return ConnStatus.Unknown;
      }

      // Receive response packet id (technically a VarInt)
      var responsePacketId = ReadLeb128Stream(stream);

      // Check for response packet id
      if (responsePacketId != 0x00)
      {
        return ConnStatus.Unknown;
      }
      
      // Receive payload-strings byte length as VarInt
      var responsePayloadLength = ReadLeb128Stream(stream);
      
      // Receive the full payload
      var responsePayload = NetStreamReadExact(stream, responsePayloadLength);

      return ParseJsonProtocolPayload(responsePayload);
    }

    /// <summary>
    /// Helper method for parsing the payload of the `json` SLP protocol
    /// </summary>
    /// <param name="rawPayload">The raw payload, without packet length and -id</param>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Json"/>
    private ConnStatus ParseJsonProtocolPayload(byte[] rawPayload)
    {
      try
      {
        var jsonReader = JsonReaderWriterFactory.CreateJsonReader(rawPayload, new System.Xml.XmlDictionaryReaderQuotas());
      
        var root = XElement.Load(jsonReader);

        // This payload contains a json string like this:
        // {"description":{"text":"A Minecraft Server"},"players":{"max":20,"online":0},"version":{"name":"1.16.5","protocol":754}}
        // {"description":{"text":"This is MC \"1.16\" §9§oT§4E§r§lS§6§o§nT"},"players":{"max":20,"online":0},"version":{"name":"1.16.5","protocol":754"}}
      
        // Extract version
        Version = root.XPathSelectElement("//version/name")?.Value;
        
        // the MOTD
        var descriptionElement = root.XPathSelectElement("//description");
        if (descriptionElement != null && descriptionElement.Attribute(XName.Get("type"))?.Value == "string")
        {
          Motd = descriptionElement.Value;
        }
        else if (root.XPathSelectElement("//description/text") != null)
        {
          Motd = root.XPathSelectElement("//description/text")?.Value;
        }
        
        // the online player count
        CurrentPlayersInt = Convert.ToInt32(root.XPathSelectElement("//players/online")?.Value);
        
        // the max player count
        MaximumPlayersInt = Convert.ToInt32(root.XPathSelectElement("//players/max")?.Value);
      }
      catch (Exception)
      {
        return ConnStatus.Unknown;
      }

      // Check if everything was filled
      if (Version == null || Motd == null)
      {
        return ConnStatus.Unknown;
      }
      
      // If we got here, everything is in order
      ServerUp = true;
      Protocol = SlpProtocol.Json;

      return ConnStatus.Success;
    }

    /// <summary>
    /// Requests the server data with the Minecraft 1.6 SLP protocol, nicknamed "extended legacy" ping protocol.
    /// All modern servers are currently backwards compatible with this protocol.<br/>
    /// 
    /// See https://wiki.vg/Server_List_Ping#1.6
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.ExtendedLegacy"/>
    public ConnStatus RequestWithExtendedLegacyProtocol()
    {
      TcpClient tcpclient;
      
      try
      {
        tcpclient = TcpClientWrapper();
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

      byte[] responsePacketHeader;
      
      // Catch timeouts and other network race conditions
      // A timeout occurs if the server doesn't understand the ping packet
      // and tries to interpret it as something else
      try
      {
        responsePacketHeader = NetStreamReadExact(stream, 3);
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
      var payload = NetStreamReadExact(stream, payloadLength*2);

      // Close socket
      tcpclient.Close();
      
      return ParseLegacyProtocol(payload, SlpProtocol.ExtendedLegacy);
    }

    /// <summary>
    /// Requests the server data with the Minecraft 1.4-1.5 SLP protocol version,
    /// server response contains more info than beta SLP (notably the server version).
    /// Quite simple to request, but contains all interesting information.
    /// Still works with (many) modern server implementations.<br/>
    /// 
    /// See https://wiki.vg/Server_List_Ping#1.4_to_1.5
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Legacy"/>
    public ConnStatus RequestWithLegacyProtocol()
    {
      TcpClient tcpclient;
      
      try
      {
        tcpclient = TcpClientWrapper();
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

      byte[] responsePacketHeader;
      
      // Catch timeouts or reset connections
      // This happens if the server doesn't understand the packet (unsupported protocol)
      try
      {
        responsePacketHeader = NetStreamReadExact(stream, 3);
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
      var payload = NetStreamReadExact(stream, payloadLength*2);

      // Close socket
      tcpclient.Close();

      return ParseLegacyProtocol(payload, SlpProtocol.Legacy);
    }

    /// <summary>
    /// Internal helper method for parsing the 1.4-1.5 ('Legacy') and 1.6 ('ExtendedLegacy') SLP protocol payloads.
    /// The (response) payload for both protocols is identical, only the request is different.
    /// </summary>
    /// <param name="rawPayload">The raw payload, without packet length and -id</param>
    /// <param name="protocol">The protocol that was used (either Legacy or ExtendedLegacy)</param>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Legacy"/>
    /// <seealso cref="SlpProtocol.ExtendedLegacy"/>
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

    /// <summary>
    /// Requests the server data with the Minecraft Beta 1.8 to Minecraft 1.3 (release) SLP protocol.
    /// This protocol is very simple; its response only contains the MOTD, the player count and the max players
    /// - not the server version.
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Beta"/>
    public ConnStatus RequestWithBetaProtocol()
    {
      TcpClient tcpclient;
      
      try
      {
        tcpclient = TcpClientWrapper();
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

      byte[] responsePacketHeader;
      try
      {
        responsePacketHeader = NetStreamReadExact(stream, 3);
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
      var payload = NetStreamReadExact(stream, payloadLength * 2);

      // Close socket
      tcpclient.Close();

      return ParseBetaProtocol(payload);
    }

    /// <summary>
    /// Internal helper method for parsing the `beta` SLP protocol payload.
    /// May be useful for unit tests and issue troubleshooting.
    /// </summary>
    /// <param name="rawPayload">The raw payload, without packet length and -id</param>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    private ConnStatus ParseBetaProtocol(byte[] rawPayload)
    {
      // Decode byte[] as UTF16BE
      var payloadString = Encoding.BigEndianUnicode.GetString(rawPayload, 0, rawPayload.Length);

      // The payload contains 3 parts, separated by '§' (section sign)
      // If the MOTD contains §, there may be more parts here (we take care of that later)
      var payloadArray = payloadString.Split('§');
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

    /// <summary>
    /// Internal helper method for connecting to a remote host, including a workaround for not
    /// existing "Connect timeout" in the synchronous TcpClient.Connect() method.
    /// Otherwise, it would hang for >10 seconds before throwing an exception.
    /// </summary>
    /// <returns>TcpClient object</returns>
    private TcpClient TcpClientWrapper()
    {
      var tcpclient = new TcpClient {ReceiveTimeout = Timeout * 1000, SendTimeout = Timeout * 1000};
      
      var stopWatch = new Stopwatch();
      stopWatch.Start();
      
      // Start async connection
      var result = tcpclient.BeginConnect(Address, Port, null, null);
      // wait "timeout" seconds
      var success = result.AsyncWaitHandle.WaitOne(TimeSpan.FromSeconds(1));
      // check if connection is established, error out if not
      if (!success)
      {
        throw new Exception("Failed to connect.");
      }

      // we have connected
      tcpclient.EndConnect(result);
      
      stopWatch.Stop();
      Latency = stopWatch.ElapsedMilliseconds;

      return tcpclient;
    }

    /// <summary>
    /// Wrapper for NetworkStream.<see cref="NetworkStream.Read"/>, which blocks until the full `size` amount of bytes has been read.
    /// </summary>
    /// <param name="stream">The network stream to read `size` bytes from</param>
    /// <param name="size">The number of bytes to receive.</param>
    /// <returns>An array of type <see cref="Byte"/> that contains the received data.</returns>
    private static byte[] NetStreamReadExact(NetworkStream stream, int size)
    {
      var totalReadBytes = 0;
      var resultBuffer = new List<byte>();

      do
      {
        var tempBuffer = new byte[size - totalReadBytes];
        var readBytes = stream.Read(tempBuffer, 0, size - totalReadBytes);

        // Socket is closed
        if (readBytes == 0)
        {
          throw new IOException();
        }

        resultBuffer.AddRange(tempBuffer.Take(readBytes));
        totalReadBytes += readBytes;
      } while (totalReadBytes < size);

      return resultBuffer.ToArray();
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

    #region LEB128_Utilities

    public static byte[] WriteLeb128(int value)
    {
      var byteList = new List<byte>();
      
      // Converting int to uint is necessary to preserve the sign bit
      // when performing bit shifting
      uint actual = (uint)value;
      do
      {
        byte temp = (byte)(actual & 0b01111111);
        // Note: >>= means that the sign bit is shifted with the
        // rest of the number rather than being left alone
        actual >>= 7;
        if (actual != 0)
        {
          temp |= 0b10000000;
        }
        byteList.Add(temp);
      } while (actual != 0);

      return byteList.ToArray();
    }
    
    public static void WriteLeb128Stream(Stream stream, int value)
    {
      // Converting int to uint is necessary to preserve the sign bit
      // when performing bit shifting
      uint actual = (uint)value;
      do
      {
        byte temp = (byte)(actual & 0b01111111);
        // Note: >>> means that the sign bit is shifted with the
        // rest of the number rather than being left alone
        actual >>= 7;
        if (actual != 0)
        {
          temp |= 0b10000000;
        }
        stream.WriteByte(temp);
      } while (actual != 0);
    }

    private static int ReadLeb128Stream (Stream stream) {
      int numRead = 0;
      int result = 0;
      byte read;
      do
      {
        int r = stream.ReadByte();
        if (r == -1)
        {
          break;
        }

        read = (byte)r;
        int value = read & 0b01111111;
        result |= (value << (7 * numRead));

        numRead++;
        if (numRead > 5)
        {
          throw new FormatException("VarInt is too big.");
        }
      } while ((read & 0b10000000) != 0);

      if (numRead == 0)
      {
        throw new InvalidOperationException("Unexpected end of VarInt stream.");
      }
      return result;
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
    /// Uses (wrapped) JSON as payload. Complex request, see above <see cref="MineStat.RequestWithJsonProtocol"/>
    /// for the protocol implementation. <br/>
    /// <i>Available since Minecraft 1.7.</i>
    /// </summary>
    Json,
    
    /// <summary>
    /// The previous SLP protocol.<br/>
    /// Used by Minecraft 1.6, it is still supported by all newer server versions.
    /// Complex request needed, see implementation <see cref="MineStat.RequestWithExtendedLegacyProtocol"/> for all protocol
    /// details.<br/>
    /// <i>Available since Minecraft 1.6</i>
    /// </summary>
    ExtendedLegacy,
    
    /// <summary>
    /// The legacy SLP protocol.<br/>
    /// Used by Minecraft 1.4 and 1.5, it is the first protocol to contain the server version number.
    /// Very simple protocol call (2 byte), simple response decoding.
    /// See <see cref="MineStat.RequestWithLegacyProtocol"/> for full implementation and protocol details.<br/>
    /// <i>Available since Minecraft 1.4</i>
    /// </summary>
    Legacy,
    
    /// <summary>
    /// The first SLP protocol.<br/>
    /// Used by Minecraft Beta 1.8 till Release 1.3, it is the first SLP protocol.
    /// It contains very few details, no server version info, only MOTD, max- and online player counts.<br/>
    /// <i>Available since Minecraft Beta 1.8</i>
    /// </summary>
    Beta,
    
    /// <summary>
    /// Not a protocol. Used for setting the default, automatic protocol detection.
    /// </summary>
    Automatic
  }
}