/*
 * MineStat.java - A Minecraft server status checker
 * Copyright (C) 2014-2021 Lloyd Dilley
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

/**
 * @author Lloyd Dilley
 */

package me.dilley;

import com.google.gson.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Date;

public class MineStat
{
  public static final String VERSION = "3.0.0";         // MineStat version
  public static final byte NUM_FIELDS = 6;              // number of values expected from server
  public static final byte NUM_FIELDS_BETA = 3;         // number of values expected from a 1.8b/1.3 server
  public static final int DEFAULT_TIMEOUT = 5;          // default TCP/UDP timeout in seconds
  public static final int DEFAULT_SLP_PORT = 25565;     // default TCP port
  public static final int DEFAULT_BEDROCK_PORT = 19132; // default UDP port for Bedrock/Pocket Edition servers
  public static final int SERVER_ID_STRING_OFFSET = 35; // server ID string offset for Bedrock/Pocket Edition servers

  public enum Retval
  {
    SUCCESS(0), CONNFAIL(-1), TIMEOUT(-2), UNKNOWN(-3);

    private final int retval;

    private Retval(int retval) { this.retval = retval; }

    public int getRetval() { return retval; }
  }

  public enum Request
  {
    NONE(-1), BETA(0), LEGACY(1), EXTENDED(2), JSON(3), BEDROCK(4);

    private final int request;

    private Request(int request) { this.request = request; }

    public int getRequest() { return request; }
  }

  /**
   * Hostname or IP address of the Minecraft server
   */
  private String address;

  /**
   * Port number the Minecraft server accepts connections on
   */
  private int port;

  /**
   * TCP socket connection timeout in seconds
   */
  private int timeout;

  /**
   * Is the server up? (true or false)
   */
  private boolean serverUp;

  /**
   * Message of the day from the server
   */
  private String motd;

  /**
   * Message of the day from the server,
   * without any formatting (human-readable)
   * @since 2.1.0
   */
  private String strippedMotd;

  /**
   * Minecraft version the server is running
   */
  private String version;

  /**
   * Current number of players on the server
   */
  private int currentPlayers;

  /**
   * Maximum player capacity of the server
   */
  private int maximumPlayers;

  /**
   * Ping time to server in milliseconds
   */
  private long latency;

  /**
   * Protocol level
   * Note: Multiple Minecraft versions can share the same protocol level
   * @since 3.0.0
   */
  private int protocol;

  /**
   * Protocol version
   */
  private String requestType;

  public MineStat(String address)
  {
    this(address, DEFAULT_SLP_PORT, DEFAULT_TIMEOUT, Request.NONE);
  }

  public MineStat(String address, int port)
  {
    this(address, port, DEFAULT_TIMEOUT, Request.NONE);
  }

  public MineStat(String address, int port, int timeout)
  {
    this(address, port, timeout, Request.NONE);
  }

  public MineStat(String address, int port, int timeout, Request requestType)
  {
    setAddress(address);
    setPort(port);
    setTimeout(timeout);
    switch(requestType)
    {
      case BETA:
        betaRequest(address, port, getTimeout());
        break;
      case LEGACY:
        legacyRequest(address, port, getTimeout());
        break;
      case EXTENDED:
        extendedLegacyRequest(address, port, getTimeout());
        break;
      case JSON:
        jsonRequest(address, port, getTimeout());
        break;
      case BEDROCK:
        bedrockRequest(address, port, getTimeout());
        break;
      default:
        /*
         * Attempt various requests in a particular order. If the connection
         * fails, there is no reason to continue with subsequent requests.
         * Attempts should continue in the event of a timeout however
         * since it may be due to an issue during the handshake.
         * Note: Newer server versions may still respond to older SLP requests.
         */
        // SLP 1.4/1.5
        Retval retval = legacyRequest(address, port, getTimeout());
        // SLP 1.8b/1.3
        if(retval != Retval.SUCCESS && retval != Retval.CONNFAIL)
          retval = betaRequest(address, port, getTimeout());
        // SLP 1.6
        if(retval != Retval.CONNFAIL)
          retval = extendedLegacyRequest(address, port, getTimeout());
        // SLP 1.7
        if(retval != Retval.CONNFAIL)
          retval = jsonRequest(address, port, getTimeout());
        // Bedrock/Pocket Edition
        if(retval != Retval.CONNFAIL)
          retval = bedrockRequest(address, port, getTimeout());
    }
  }

  public String getAddress() { return address; }

  public void setAddress(String address) { this.address = address; }

  public int getPort() { return port; }

  public void setPort(int port) { this.port = port; }

  public int getTimeout() { return timeout * 1000; } // convert to milliseconds

  public void setTimeout(int timeout) { this.timeout = timeout; }

  public String getMotd() { return motd; }

  public void setMotd(String motd) { this.motd = motd; }

  public String getStrippedMotd() {
    return strippedMotd;
  }

  public void setStrippedMotd(String strippedMotd) {
    this.strippedMotd = strippedMotd;
  }

  /**
   * Helper function for stripping any formatting from a motd.
   * @param motd A motd with formatting codes
   * @return A motd with all formatting codes removed
   * @since 2.1.0
   */
  public String stripMotdFormatting(String motd) {
    return motd.replaceAll("§.", "");
  }

  public String stripMotdFormatting(JsonObject motd) {
    StringBuilder strippedMotd = new StringBuilder();

    if (motd.isJsonPrimitive()) {
      return motd.getAsString();
    }

    JsonObject motdObj = motd.getAsJsonObject();
    if (motdObj.has("text")) {
      strippedMotd.append(motdObj.get("text").getAsString());
    }

    if (motdObj.has("extra") && motdObj.get("extra").isJsonArray()) {
      for (JsonElement extraElem : motdObj.get("extra").getAsJsonArray()) {
        strippedMotd.append(stripMotdFormatting(extraElem.getAsJsonObject()));
      }
    }

    return strippedMotd.toString();
  }

  public String getVersion() { return version; }

  public void setVersion(String version) { this.version = version; }

  public int getCurrentPlayers() { return currentPlayers; }

  public void setCurrentPlayers(int currentPlayers) { this.currentPlayers = currentPlayers; }

  public int getMaximumPlayers() { return maximumPlayers; }

  public void setMaximumPlayers(int maximumPlayers) { this.maximumPlayers = maximumPlayers; }

  public long getLatency() { return latency; }

  public void setLatency(long latency) { this.latency = latency; }

  public int getProtocol() { return protocol; }

  public void setProtocol(int protocol) { this.protocol = protocol; }

  public boolean isServerUp() { return serverUp; }

  public String getRequestType() { return requestType; }

  public void setRequestType(String requestType) { this.requestType = requestType; }

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
  public Retval betaRequest(String address, int port, int timeout)
  {
    try
    {
      String[] serverData = null;
      byte[] rawServerData = null;
      Socket clientSocket = new Socket();
      long startTime = System.currentTimeMillis();
      clientSocket.connect(new InetSocketAddress(getAddress(), getPort()), getTimeout());
      setLatency(System.currentTimeMillis() - startTime);
      DataOutputStream dos = new DataOutputStream(clientSocket.getOutputStream());
      DataInputStream dis = new DataInputStream(new BufferedInputStream(clientSocket.getInputStream()));
      dos.writeBytes("\u00FE");
      if(dis.readUnsignedByte() == 0xFF) // kick packet (255)
      {
        int dataLen = dis.readUnsignedShort();
        rawServerData = new byte[dataLen * 2];
        dis.readFully(rawServerData, 0, dataLen * 2);
        clientSocket.close();
      }
      else
      {
        clientSocket.close();
        return Retval.UNKNOWN;
      }

      if(rawServerData == null)
        return Retval.UNKNOWN;

      serverData = new String(rawServerData, StandardCharsets.UTF_16).split("\u00A7"); // section symbol
      if(serverData.length >= NUM_FIELDS_BETA)
      {
        setVersion(">=1.8b/1.3"); // since server does not return version, set it
        setMotd(serverData[0]);
        setStrippedMotd(stripMotdFormatting(serverData[0]));
        setCurrentPlayers(Integer.parseInt(serverData[1]));
        setMaximumPlayers(Integer.parseInt(serverData[2]));
        setProtocol(0);           // set to zero (unknown) since 1.8b/1.3 server does not provide protocol level
        serverUp = true;
        setRequestType("SLP 1.8b/1.3 (beta)");
      }
      else
        return Retval.UNKNOWN;
    }

    catch(ConnectException ce)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketException se)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketTimeoutException ste)
    {
      return Retval.TIMEOUT;
    }
    catch(IOException ioe)
    {
      return Retval.CONNFAIL;
    }
    catch(Exception e)
    {
      serverUp = false;
      return Retval.UNKNOWN;
    }
    return Retval.SUCCESS;
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
  public Retval legacyRequest(String address, int port, int timeout)
  {
    try
    {
      String[] serverData = null;
      byte[] rawServerData = null;
      Socket clientSocket = new Socket();
      long startTime = System.currentTimeMillis();
      clientSocket.connect(new InetSocketAddress(getAddress(), getPort()), getTimeout());
      setLatency(System.currentTimeMillis() - startTime);
      DataOutputStream dos = new DataOutputStream(clientSocket.getOutputStream());
      DataInputStream dis = new DataInputStream(new BufferedInputStream(clientSocket.getInputStream()));
      dos.writeShort(0xFE01);
      if(dis.readUnsignedByte() == 0xFF) // kick packet (255)
      {
        int dataLen = dis.readUnsignedShort();
        rawServerData = new byte[dataLen * 2];
        dis.readFully(rawServerData, 0, dataLen * 2);
        clientSocket.close();
      }
      else
      {
        clientSocket.close();
        return Retval.UNKNOWN;
      }

      if(rawServerData == null)
        return Retval.UNKNOWN;

      serverData = new String(rawServerData, StandardCharsets.UTF_16BE).split("\u0000"); // null
      if(serverData.length >= NUM_FIELDS)
      {
        // serverData[0] contains the section symbol and 1
        setProtocol(Integer.parseInt(serverData[1])); // 49 for 1.4.5 for example
        setVersion(serverData[2]);
        setMotd(serverData[3]);
        setStrippedMotd(stripMotdFormatting(serverData[3]));
        setCurrentPlayers(Integer.parseInt(serverData[4]));
        setMaximumPlayers(Integer.parseInt(serverData[5]));
        serverUp = true;
        setRequestType("SLP 1.4/1.5 (legacy)");
      }
      else
        return Retval.UNKNOWN;
    }

    catch(ConnectException ce)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketException se)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketTimeoutException ste)
    {
      return Retval.TIMEOUT;
    }
    catch(IOException ioe)
    {
      return Retval.CONNFAIL;
    }
    catch(Exception e)
    {
      serverUp = false;
      return Retval.UNKNOWN;
    }
    return Retval.SUCCESS;
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
  public Retval extendedLegacyRequest(String address, int port, int timeout)
  {
    try
    {
      String[] serverData = null;
      byte[] rawServerData = null;
      Socket clientSocket = new Socket();
      long startTime = System.currentTimeMillis();
      clientSocket.connect(new InetSocketAddress(getAddress(), getPort()), getTimeout());
      setLatency(System.currentTimeMillis() - startTime);
      DataOutputStream dos = new DataOutputStream(clientSocket.getOutputStream());
      DataInputStream dis = new DataInputStream(new BufferedInputStream(clientSocket.getInputStream()));
      dos.writeShort(0xFE01);
      dos.writeBytes("\u00FA");
      dos.writeBytes("\u0000\u000B");    // 11 (length of "MC|PingHost")
      byte[] payload = "MC|PingHost".getBytes(StandardCharsets.UTF_16BE);
      dos.write(payload, 0, payload.length);
      dos.writeShort(7 + 2 * address.length());
      dos.writeBytes("\u004E");          // 78 (protocol version of 1.6.4)
      dos.writeShort(address.length());
      payload = address.getBytes(StandardCharsets.UTF_16BE);
      dos.write(payload, 0, payload.length);
      dos.writeInt(port);
      if(dis.readUnsignedByte() == 0xFF) // kick packet (255)
      {
        int dataLen = dis.readUnsignedShort();
        rawServerData = new byte[dataLen * 2];
        dis.readFully(rawServerData, 0, dataLen * 2);
        clientSocket.close();
      }
      else
      {
        clientSocket.close();
        return Retval.UNKNOWN;
      }

      if(rawServerData == null)
        return Retval.UNKNOWN;

      serverData = new String(rawServerData, StandardCharsets.UTF_16BE).split("\u0000"); // null
      if(serverData.length >= NUM_FIELDS)
      {
        // serverData[0] contains the section symbol and 1
        setProtocol(Integer.parseInt(serverData[1])); // 78 for 1.6.4 for example
        setVersion(serverData[2]);
        setMotd(serverData[3]);
        setStrippedMotd(stripMotdFormatting(serverData[3]));
        setCurrentPlayers(Integer.parseInt(serverData[4]));
        setMaximumPlayers(Integer.parseInt(serverData[5]));
        serverUp = true;
        setRequestType("SLP 1.6 (extended legacy)");
      }
      else
        return Retval.UNKNOWN;
    }

    catch(ConnectException ce)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketException se)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketTimeoutException ste)
    {
      return Retval.TIMEOUT;
    }
    catch(IOException ioe)
    {
      return Retval.CONNFAIL;
    }
    catch(Exception e)
    {
      serverUp = false;
      return Retval.UNKNOWN;
    }
    return Retval.SUCCESS;
  }

  /*
   * Unpack an int from a varint
   */
  public int recvVarInt(DataInputStream dis)
  {
    try
    {
      int intData = 0, width = 0;
      while(true)
      {
        int varInt = dis.readByte();
        intData |= (varInt & 0x7F) << width++ * 7;
        if(width > 5)
          return Retval.UNKNOWN.getRetval(); // overflow
        if((varInt & 0x80) != 128)           // Little Endian Base 128 (LEB128)
          break;
      }
      return intData;
    }
    catch(IOException ioe)
    {
      return Retval.UNKNOWN.getRetval();
    }
  }

  /*
   * Pack a varint from an int
   */
  public Retval sendVarInt(DataOutputStream dos, int intData)
  {
    try
    {
      while(true)
      {
        if((intData & 0xFFFFFF80) == 0)
        {
          dos.writeByte(intData);
          return Retval.SUCCESS;
        }
        dos.writeByte(intData & 0x7F | 0x80);
        intData >>>= 7;
      }
    }
    catch(IOException ioe)
    {
      return Retval.UNKNOWN;
    }
  }

  /*
   * Check if MineStat object data is present
   */
  public boolean isDataValid()
  {
    // Do not check for empty motd in case server has none
    if(this.motd != null && this.version != null && !this.version.trim().isEmpty() && currentPlayers >= 0 && maximumPlayers >= 0)
      return true;
    else
      return false;
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
  public Retval jsonRequest(String address, int port, int timeout)
  {
    try
    {
      String[] serverData = null;
      byte[] rawServerData = null;
      Socket clientSocket = new Socket();
      long startTime = System.currentTimeMillis();
      clientSocket.connect(new InetSocketAddress(getAddress(), getPort()), getTimeout());
      setLatency(System.currentTimeMillis() - startTime);
      ByteArrayOutputStream baos = new ByteArrayOutputStream();
      DataOutputStream payload = new DataOutputStream(baos);
      DataOutputStream dos = new DataOutputStream(clientSocket.getOutputStream());
      DataInputStream dis = new DataInputStream(new BufferedInputStream(clientSocket.getInputStream()));
      payload.writeByte(0x00);               // handshake packet
      sendVarInt(payload, 0x00);             // protocol version
      sendVarInt(payload, address.length()); // packed remote address length as varint
      payload.writeBytes(address);           // remote address as string
      payload.writeShort(port);              // remote port as short
      sendVarInt(payload, 0x01);             // state packet
      sendVarInt(dos, baos.size());          // payload size as varint
      dos.write(baos.toByteArray());         // send payload
      dos.writeByte(0x01);                   // size
      dos.writeByte(0x00);                   // ping packet
      int totalLength = recvVarInt(dis);     // total response size
      int packetID = recvVarInt(dis);        // packet ID
      int jsonLength = recvVarInt(dis);      // JSON response size
      byte[] rawData = new byte[jsonLength]; // storage for JSON data

      dis.readFully(rawData);                     // fill byte array with JSON data

      // Close socket
      if(!clientSocket.isClosed())
        clientSocket.close();

      // Populate object from JSON data
      JsonObject jobj = new Gson().fromJson(new String(rawData), JsonObject.class);
      setProtocol(jobj.get("version").getAsJsonObject().get("protocol").getAsInt());
      setMotd(jobj.get("description").toString());
      setStrippedMotd(stripMotdFormatting(jobj.get("description").getAsJsonObject()));
      setVersion(jobj.get("version").getAsJsonObject().get("name").getAsString());
      setCurrentPlayers(jobj.get("players").getAsJsonObject().get("online").getAsInt());
      setMaximumPlayers(jobj.get("players").getAsJsonObject().get("max").getAsInt());
      serverUp = true;
      setRequestType("SLP 1.7 (JSON)");
      if(!isDataValid())
        return Retval.UNKNOWN;
    }
    catch(ConnectException ce)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketException se)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketTimeoutException ste)
    {
      return Retval.TIMEOUT;
    }
    catch(IOException ioe)
    {
      return Retval.CONNFAIL;
    }
    catch(Exception e)
    {
      serverUp = false;
      return Retval.UNKNOWN;
    }
    return Retval.SUCCESS;
  }

  /*
   * Convert long to byte array
   */
  public static byte[] toByteArr(long data)
  {
    return new byte[]
    {
      (byte)((data >> 56) & 0xff),
      (byte)((data >> 48) & 0xff),
      (byte)((data >> 40) & 0xff),
      (byte)((data >> 32) & 0xff),
      (byte)((data >> 24) & 0xff),
      (byte)((data >> 16) & 0xff),
      (byte)((data >> 8)  & 0xff),
      (byte)((data >> 0)  & 0xff),
    };
  }

  /*
   * Bedrock/Pocket Edition
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
  public Retval bedrockRequest(String address, int port, int timeout)
  {
    try
    {
      byte[] rawServerData = new byte[512];
      byte[] request = null;
      DatagramPacket requestPacket = null;
      DatagramPacket responsePacket = null;
      DatagramSocket clientSocket = new DatagramSocket();

      /* Connect */
      clientSocket.setSoTimeout(getTimeout());
      long startTime = System.currentTimeMillis();
      clientSocket.connect(new InetSocketAddress(getAddress(), getPort()));
      setLatency(System.currentTimeMillis() - startTime);

      /* Handshake */
      ByteArrayOutputStream baos = new ByteArrayOutputStream();
      baos.write(0x01);                             // unconnected ping
      baos.write(toByteArr(new Date().getTime()));  // current time as a long
      // magic number
      baos.write(new byte[] {(byte)0x00, (byte)0xFF, (byte)0xFF, (byte)0x00, (byte)0xFE, (byte)0xFE, (byte)0xFE, (byte)0xFE, (byte)0xFD,
                             (byte)0xFD, (byte)0xFD, (byte)0xFD, (byte)0x12, (byte)0x34, (byte)0x56, (byte)0x78});
      baos.write(toByteArr(2));                     // client GUID as a long
      request = baos.toByteArray();                 // concatenate all the bytes
      requestPacket = new DatagramPacket(request, request.length);
      clientSocket.send(requestPacket);

      /* Response */
      responsePacket = new DatagramPacket(rawServerData, rawServerData.length);  // unconnected pong
      clientSocket.receive(responsePacket);
      if(rawServerData[0] != 0x1C)
        return Retval.UNKNOWN;

      /* Close socket */
      if(!clientSocket.isClosed())
        clientSocket.close();

      /* Parse data */
      int serverIdLength = rawServerData[34]; // server ID string length
      String serverId = new String(Arrays.copyOfRange(rawServerData, SERVER_ID_STRING_OFFSET, SERVER_ID_STRING_OFFSET + serverIdLength), StandardCharsets.UTF_8);
      String[] splitData = serverId.split(";");
      serverUp = true;
      setProtocol(Integer.parseInt(splitData[2]));
      setCurrentPlayers(Integer.parseInt(splitData[4]));
      setMaximumPlayers(Integer.parseInt(splitData[5]));
      setMotd(splitData[1]);
      setStrippedMotd(stripMotdFormatting(splitData[1]));
      setVersion(splitData[3] + " " + splitData[7] + " (" + splitData[0] + ")");
      setRequestType("Bedrock/Pocket Edition");
    }
    catch(ConnectException ce)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketException se)
    {
      return Retval.CONNFAIL;
    }
    catch(SocketTimeoutException ste)
    {
      return Retval.TIMEOUT;
    }
    catch(IOException ioe)
    {
      return Retval.CONNFAIL;
    }
    catch(Exception e)
    {
      serverUp = false;
      return Retval.UNKNOWN;
    }
    return Retval.SUCCESS;
  }
}
