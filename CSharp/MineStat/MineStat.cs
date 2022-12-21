/*
 * MineStat.cs - A Minecraft server status checker
 * Copyright (C) 2014-2022 Lloyd Dilley, 2021-2022 Felix Ern (MindSolve), 2022 Ajoro
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
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.Serialization.Json;
using System.Xml;
using System.Xml.Linq;
using System.Xml.XPath;

namespace MineStatLib
{
  /// <summary>
  /// MineStat is a Minecraft server status checker.<br/>
  /// After object creation, the appropriate SLP (server list ping) protocol will be automatically chosen based on the
  /// server version and all fields will be populated.
  /// </summary>
  public class MineStat
  {
    /// <summary>
    /// The MineStat library version.
    /// </summary>
    public const string MineStatVersion = "3.0.1";
    /// <summary>
    /// Default TCP timeout in seconds.
    /// </summary>
    private const int DefaultTimeout = 5;
    /// <summary>
    /// The address of the Minecraft server to connect to.
    /// </summary>
    public string Address { get; set; }
    /// <summary>
    /// The port of the Minecraft server to connect to.
    /// </summary>
    public ushort Port { get; set; }
    /// <summary>
    /// The time in seconds, after which a connection is timed out. Defaults to <see cref="DefaultTimeout"/>.
    /// </summary>
    public int Timeout { get; set; }
    /// <summary>
    /// The message of the day, as returned by the server. May contain legacy formatting codes (§) or JSON chat components.
    /// </summary>
    /// <example>
    /// Legacy formatting codes:
    /// <code>§6~~§r §3§lM§7§lA§2§lG§9§lI§4§lC§r1.16 v3§6~~§r</code>
    /// JSON chat components:
    /// <code>
    /// {"extra": [{"color": "gold", "text": "Test"}, {"text": " "}, {"bold": true, "color": "dark_aqua", "text": "text"}], "text": ""}
    /// </code>
    /// </example>
    public string Motd { get; set; }
    /// <summary>
    /// The message of the day, with all formatting removed ("human readable").
    /// </summary>
    /// <example>
    /// The above motd with all formatting removed:
    /// <code>~~ MAGIC1.16 v3~~</code>
    /// </example>
    public string Stripped_Motd { get; set; }
    /// <summary>
    /// The version, as provided by the server. May contain freetext.
    /// </summary>
    /// <example>
    /// PaperMC 1.19 server:
    /// <code>Paper 1.18.2</code>
    /// PocketMine-MP Bedrock server:
    /// <code>1.18.30 PocketMine-MP(MCPE)</code>
    /// </example>
    public string Version { get; set; }
    /// <summary>
    /// The current online player count as string.
    /// For the integer representation use <see cref="CurrentPlayersInt"/>.
    /// </summary>
    public string CurrentPlayers => Convert.ToString(CurrentPlayersInt);
    /// <summary>
    /// The current online player count as integer.
    /// For the string representation use <see cref="CurrentPlayers"/>.
    /// </summary>
    public int CurrentPlayersInt { get; set; }
    /// <summary>
    /// The maximum online player count as string, as reported by the server.
    /// May be inaccurate (Server networks, BungeeCord/Velocity/Waterfall).<br/>
    /// For the integer representation use <see cref="MaximumPlayersInt"/>.
    /// </summary>
    public string MaximumPlayers => Convert.ToString(MaximumPlayersInt);
    /// <summary>
    /// The maximum online player count as int, as reported by the server.
    /// May be inaccurate (Server networks, BungeeCord/Velocity/Waterfall).<br/>
    /// For the string representation use <see cref="MaximumPlayers"/>.
    /// </summary>
    public int MaximumPlayersInt { get; set; }
    /// <summary>
    /// The sample list of online players.<br/>
    /// Only provided by modern servers (>=1.7), may contain freetext and formatting codes.
    /// </summary>
    public string[] PlayerList { get; set; }
    /// <summary>
    /// Whether the server is online and could be reached. True if online.
    /// </summary>
    public bool ServerUp { get; set; }
    /// <summary>
    /// The time it took the server to respond with the server information in milliseconds.
    /// </summary>
    public long Latency { get; set; }
    /// <summary>
    /// The protocol used to connect to the server. See <see cref="SlpProtocol"/> for all available protocols.
    /// </summary>
    public SlpProtocol Protocol { get; set; }
    /// <summary>
    /// Bedrock specific: The current gamemode (Creative/Survival/Adventure)
    /// </summary>
    public string Gamemode { get; set; }
    /// <summary>
    /// Favicon for the Minecraft server when returned by the server (In Base64 Format)
    /// </summary>
    public string Favicon { get; set; }

    /// <summary>
    /// Favicon decoded to byte array
    /// </summary>
    public byte[] FaviconBytes => !string.IsNullOrWhiteSpace(Favicon) && Favicon.Contains("base64,") ? Convert.FromBase64String(Favicon.Substring(Favicon.IndexOf(",") + 1)) : null;

    /// <inheritdoc cref="MineStat"/>
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
          RequestWrapper(RequestWithBetaProtocol);
          break;
        case SlpProtocol.Legacy:
          RequestWrapper(RequestWithLegacyProtocol);
          break;
        case SlpProtocol.ExtendedLegacy:
          RequestWrapper(RequestWithExtendedLegacyProtocol);
          break;
        case SlpProtocol.Json:
          RequestWrapper(RequestWithJsonProtocol);
          break;
        case SlpProtocol.Bedrock_Raknet:
          RequestWithRaknetProtocol();
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
      // 1.: Raknet (Bedrock)
      // 2.: Legacy (1.4, 1.5)
      // 3.: Beta (b1.8-rel1.3)
      // 4.: Extended Legacy (1.6)
      // 5.: JSON (1.7+)

      var result = RequestWithRaknetProtocol();
      if (result == ConnStatus.Connfail || result == ConnStatus.Success)
        return;

      result = RequestWrapper(RequestWithLegacyProtocol);

      if (result != ConnStatus.Connfail && result != ConnStatus.Success)
      {
        result = RequestWrapper(RequestWithBetaProtocol);
      }
      if (result != ConnStatus.Connfail)
        result = RequestWrapper(RequestWithExtendedLegacyProtocol);

      if (result != ConnStatus.Connfail /* && result != ConnStatus.Success */)
        RequestWrapper(RequestWithJsonProtocol);
    }
    
    /// <summary>
    /// Function for stripping all formatting codes from a motd.
    /// </summary>
    /// <returns>string with the stripped motd</returns>
    static private string strip_motd_formatting(string rawmotd)
    {
      return Regex.Replace(rawmotd, @"\u00A7+[a-zA-Z0-9]", string.Empty);
    }
    static private string strip_motd_formatting(XElement rawmotd)
    {
      if (rawmotd.FirstAttribute.Value == "string")
        return strip_motd_formatting(rawmotd.FirstNode.ToString());
      var stripped_motd = rawmotd.Element("text")?.Value;
      if (rawmotd.Elements("extra").Any())
      {
        var json_data = rawmotd.Element("extra").Elements();
        foreach (var item in json_data)
          stripped_motd += item.Element("text")?.Value;
      }
      return strip_motd_formatting(stripped_motd);
    }

    /// <summary>
    /// Method for querying a Bedrock server (Minecraft PE, Windows 10 or Education Edition).
    /// The protocol is based on the RakNet protocol.<br/>
    /// See https://wiki.vg/Raknet_Protocol#Unconnected_Ping<br/>
    /// Note: This method currently works as if the connection is handled via TCP (as if no packet loss might occur).
    /// Packet loss handling should be implemented (resending).
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Bedrock_Raknet"/>
    public ConnStatus RequestWithRaknetProtocol()
    {
      byte[] readbytestream(Queue<byte> que, int count)
      {
        var resultBuffer = new List<byte>();
        for (var i = 0; i < count; i++)
        {
          resultBuffer.Add(que.Dequeue());
        }
        return resultBuffer.ToArray();
      }

      string responsePayload;
      var sock = new UdpClient();
      sock.Client.ReceiveTimeout = Timeout * 1000;
      sock.Client.SendTimeout = Timeout * 1000;

      var stopWatch = new Stopwatch();
      stopWatch.Start();

      try
      {
        sock.Connect(Address, Port);
      }
      catch (SocketException)
      {
        return ConnStatus.Connfail;
      }
      stopWatch.Stop();
      Latency = stopWatch.ElapsedMilliseconds;

      var raknetMagic = new byte[] { 0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78 };

      var raknetPingHandshakePacket = new List<byte>() { 0x01 };

      var unixtime = BitConverter.GetBytes(DateTimeOffset.Now.ToUnixTimeMilliseconds());

      Int64 temp = 0x02;
      raknetPingHandshakePacket.AddRange(unixtime);
      raknetPingHandshakePacket.AddRange(raknetMagic);
      raknetPingHandshakePacket.AddRange(BitConverter.GetBytes(temp));

      var sendlen = sock.Send(raknetPingHandshakePacket.ToArray(), raknetPingHandshakePacket.Count());

      if (sendlen != raknetPingHandshakePacket.Count())
      {
        return ConnStatus.Unknown;
      }
      try
      {
        var endpoint = new System.Net.IPEndPoint(System.Net.IPAddress.Any, Port);
        var response = new Queue<byte>(sock.Receive(ref endpoint));

        if (response.Dequeue() != 0x1c)
          return ConnStatus.Unknown;

        // responseTimeStamp & responseServerGUID discarded
        var responseTimeStamp = BitConverter.ToInt64(readbytestream(response, 8), 0);
        var responseServerGUID = BitConverter.ToInt64(readbytestream(response, 8), 0);

        var responseMagic = readbytestream(response, 16);
        if (raknetMagic.SequenceEqual(responseMagic) == false)
          return ConnStatus.Unknown;

        //responsePayloadLength also discarded
        var responsePayloadLength = BitConverter.ToUInt16(readbytestream(response, 2), 0);

        responsePayload = Encoding.UTF8.GetString(readbytestream(response, response.Count));
      }
      catch
      {
        stopWatch.Stop();
        return ConnStatus.Timeout;
      }
      finally
      {
        sock.Close();
      }

      return ParseRaknetProtocolPayload(responsePayload);
    }
    /// <summary>
    /// Helper method for parsing the payload of the `bedrock_raknet` SLP protocol
    /// </summary>
    /// <param name="payload">The string payload</param>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Bedrock_Raknet"/>
    private ConnStatus ParseRaknetProtocolPayload(string payload)
    {
      var keys = new string[] {"edition", "motd_1", "protocol_version", "version", "current_players", "max_players",
      "server_uid", "motd_2", "gamemode", "gamemode_numeric", "port_ipv4", "port_ipv6"};

      var dic = keys.Zip(payload.Split((char)59), (k, v) => new { k, v })
              .ToDictionary(x => x.k, x => x.v);
      
      Protocol = SlpProtocol.Bedrock_Raknet;
      ServerUp = true;
      CurrentPlayersInt = Convert.ToInt32(dic["current_players"]);
      MaximumPlayersInt = Convert.ToInt32(dic["max_players"]);
      Version = dic["version"] + " " + dic["motd_2"] + " (" + dic["edition"] + ")";
      Motd = dic["motd_1"];
      Stripped_Motd = strip_motd_formatting(Motd);
      Gamemode = dic["gamemode"];
      return ConnStatus.Success;
    }
    /// <summary>
    /// Requests the server data with the Minecraft 1.7+ SLP protocol. In use by all modern Minecraft clients.
    /// Complicated to construct.<br/>
    /// See https://wiki.vg/Server_List_Ping#Current
    /// </summary>
    /// <returns>ConnStatus - See <see cref="ConnStatus"/> for possible values</returns>
    /// <seealso cref="SlpProtocol.Json"/>
    public ConnStatus RequestWithJsonProtocol(NetworkStream stream)
    {
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
      int responseSize;
      try
      {
        // Send handshake packet
        stream.Write(jsonPingHandshakePacket.ToArray(), 0, jsonPingHandshakePacket.Count);

        // Send request packet (packet len as VarInt, empty packet with ID 0x00)
        WriteLeb128Stream(stream, 1);
        stream.WriteByte(0x00);

        // Receive response

        // Catch timeouts and other network exceptions
        // A timeout occurs if the server doesn't understand the ping packet
        // and tries to interpret it as something else

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

        // Favicon
        Favicon = root.XPathSelectElement("//favicon")?.Value;

        // the MOTD
        var descriptionElement = root.XPathSelectElement("//description");
        // JsonWriter needs a XmlDocument with the root element "root"
        XmlDocument motdJsonDocument = new XmlDocument();
        descriptionElement.Name = "root";
        motdJsonDocument.LoadXml(descriptionElement.ToString());
        MemoryStream tempMotdJsonStream = new MemoryStream();
        using (XmlWriter jsonWriter = JsonReaderWriterFactory.CreateJsonWriter(tempMotdJsonStream))
          motdJsonDocument.WriteTo(jsonWriter);
        Motd = Encoding.UTF8.GetString(tempMotdJsonStream.ToArray());
        Stripped_Motd = strip_motd_formatting(descriptionElement);

        // the online player count
        CurrentPlayersInt = Convert.ToInt32(root.XPathSelectElement("//players/online")?.Value);

        // the max player count
        MaximumPlayersInt = Convert.ToInt32(root.XPathSelectElement("//players/max")?.Value);

        // the online player list, if provided by the server
        // inspired by https://github.com/lunalunaaaa
        var playerSampleElement = root.XPathSelectElement("//players/sample");
        if (playerSampleElement != null && playerSampleElement.Attribute(XName.Get("type"))?.Value == "array")
        {
          var playerSampleNameElements = root.XPathSelectElements("//players/sample/item/name");
          PlayerList = playerSampleNameElements.Select(playerNameElement => playerNameElement.Value).ToArray();
        }
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
    public ConnStatus RequestWithExtendedLegacyProtocol(NetworkStream stream)
    {
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
      var payload = NetStreamReadExact(stream, payloadLength * 2);

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
    public ConnStatus RequestWithLegacyProtocol(NetworkStream stream)
    {
      // Send ping packet with id 0xFE, and ping data 0x01
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
      var payload = NetStreamReadExact(stream, payloadLength * 2);

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
      Stripped_Motd = strip_motd_formatting(Motd);

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
    public ConnStatus RequestWithBetaProtocol(NetworkStream stream)
    {
      // Send empty packet with id 0xFE
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
      MaximumPlayersInt = Convert.ToInt32(payloadArray[payloadArray.Length - 1]);

      // Current player count is second-to-last element
      CurrentPlayersInt = Convert.ToInt32(payloadArray[payloadArray.Length - 2]);

      // Motd is first element, but may contain 'section sign' (the delimiter)
      Motd = String.Join("§", payloadArray.Take(payloadArray.Length - 2).ToArray());
      Stripped_Motd = strip_motd_formatting(Motd);

      // If we got here, everything is in order
      ServerUp = true;
      Protocol = SlpProtocol.Beta;

      // This protocol does not provide the server version.
      Version = "<= 1.3";

      return ConnStatus.Success;
    }

    /// <summary>
    /// Internal helper method for connecting to a remote host and setting timeouts.
    /// </summary>
    /// <remarks>
    /// Contains a workaround for not  existing "Connect timeout" in the synchronous <c>TcpClient.Connect()</c> method.
    /// Otherwise, the method would hang for >10 seconds before throwing an exception.
    /// </remarks>
    /// <returns><see cref="TcpClient"/> object or <c>null</c> if the connection failed</returns>
    private TcpClient TcpClientWrapper()
    {
      var tcpclient = new TcpClient { ReceiveTimeout = Timeout * 1000, SendTimeout = Timeout * 1000 };

      var stopWatch = new Stopwatch();
      stopWatch.Start();

      // Start async connection
      var result = tcpclient.BeginConnect(Address, Port, null, null);
      // wait "timeout" seconds
      var isResponsive = result.AsyncWaitHandle.WaitOne(TimeSpan.FromSeconds(Timeout));

      // Check if connection attempt hung longer than `timeout` seconds, error out if not
      // Note: Errors are a valid response and have to be caught later
      if (!isResponsive)
      {
        return null;
      }

      // The connection attempt returned something (error or success)
      try
      {
        tcpclient.EndConnect(result);
      }
      // "silence" only SocketExceptions, e.g. Host is down, port unreachable
      // but let everything else throw
      catch (SocketException)
      {
        return null;
      }

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

    /// <summary>
    /// Wrapper for any `Request` method. Handles graceful socket closure.
    /// </summary>
    /// <param name="toExecute">Request method to execute, e.g. <see cref="RequestWithJsonProtocol"/></param>
    /// <returns>The connection status returned by the method from `toExecute` or <see cref="ConnStatus.Connfail"/> on connection failure</returns>
    private ConnStatus RequestWrapper(Func<NetworkStream, ConnStatus> toExecute)
    {
      using (var tcpClient = TcpClientWrapper())
      {
        if (tcpClient == null)
        {
          ServerUp = false;
          return ConnStatus.Connfail;
        }

        var networkStream = tcpClient.GetStream();
        return toExecute(networkStream);
      }
    }

    // "Missing XML comment for publicly visible type or member" - Deprecated methods, no use for documentation.
#pragma warning disable CS1591

    #region Obsolete

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Address instead.")]
    public string GetAddress()
    {
      return Address;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Address instead.")]
    public void SetAddress(string address)
    {
      Address = address;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Port instead.")]
    public ushort GetPort()
    {
      return Port;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Port instead.")]
    public void SetPort(ushort port)
    {
      Port = port;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Motd instead.")]
    public string GetMotd()
    {
      return Motd;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Motd instead.")]
    public void SetMotd(string motd)
    {
      Motd = motd;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Version instead.")]
    public string GetVersion()
    {
      return Version;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Version instead.")]
    public void SetVersion(string version)
    {
      Version = version;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.CurrentPlayers/.CurrentPlayersInt instead.")]
    public string GetCurrentPlayers()
    {
      return CurrentPlayers;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.CurrentPlayers/.CurrentPlayersInt instead.")]
    public void SetCurrentPlayers(string currentPlayers)
    {
      CurrentPlayersInt = Convert.ToInt32(currentPlayers);
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.MaximumPlayers/.MaximumPlayersInt instead.")]
    public string GetMaximumPlayers()
    {
      return MaximumPlayers;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.MaximumPlayersInt instead.")]
    public void SetMaximumPlayers(string maximumPlayers)
    {
      MaximumPlayersInt = Convert.ToInt32(maximumPlayers);
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Latency instead.")]
    public long GetLatency()
    {
      return Latency;
    }

    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.Latency instead.")]
    public void SetLatency(long latency)
    {
      Latency = latency;
    }

    /// <inheritdoc cref="ServerUp"/>
    /// <seealso cref="ServerUp"/>
    [Obsolete("This method is deprecated and will be removed soon. Use MineStat.ServerUp instead.")]
    public bool IsServerUp()
    {
      return ServerUp;
    }

    #endregion

#pragma warning restore CS1591

    #region LEB128_Utilities

    /// <summary>
    /// Creates a LEB128 byte-array for sending over network from an integer.
    /// </summary>
    /// <param name="value">Value to convert</param>
    /// <returns>A LEB128 representation of the value as byte array</returns>
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

    /// <summary>
    /// Writes an integer as LEB128-encoded number to a (network-)stream.
    /// </summary>
    /// <param name="stream"></param>
    /// <param name="value"></param>
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

    /// <summary>
    /// Reads an LEB128-encoded integer from a (network-) stream and converts it to a normal int. 
    /// </summary>
    /// <param name="stream">Stream to read the data from</param>
    /// <returns>The integer representation of the read LEB128 number</returns>
    /// <exception cref="FormatException"></exception>
    /// <exception cref="InvalidOperationException"></exception>
    private static int ReadLeb128Stream(Stream stream)
    {
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
    /// The Bedrock SLP-equivalent using the RakNet `Unconnected Ping` packet.
    /// Currently experimental.
    /// </summary>
    Bedrock_Raknet,

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
