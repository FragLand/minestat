/*
 * MineStat.java - A Minecraft server status checker
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

/**
 * @author Lloyd Dilley,Arne Sacnussem
 */

package me.dilley;

import java.io.*;
import java.net.*;

public class MineStat {
    final byte NUM_FIELDS = 6;

    /**
     * Hostname or IP address of the Minecraft server
     */
    private String address;

    /**
     * Port number the Minecraft server accepts connections on
     */
    private int port;

    /**
     * quarry timeout in millisecond.
     * default is 7000ms
     */
    private int[] timeout;

    /**
     * Is the server up? (true or false)
     */
    private boolean serverUp;

    /**
     * Message of the day from the server
     */
    private String motd;

    /**
     * Minecraft version the server is running
     */
    private String version;

    /**
     * Current number of players on the server
     */
    private String currentPlayers;

    /**
     * Maximum player capacity of the server
     */
    private String maximumPlayers;

    public MineStat(String address, int port, int... timeout) {
        setAddress(address);
        setPort(port);

        if (timeout.length == 0)
            setTimeout(new int[]{7000});
        else setTimeout(timeout);

        refresh();
    }

    /**
     * refresh state of the server
     *
     * @return <code>true</code> if the server is up;
     * <code>false</code> if the server is down;
     */
    public boolean refresh() {
        String[] serverData;
        String rawServerData;
        try {
            //Socket clientSocket = new Socket(getAddress(), getPort());
            Socket clientSocket = new Socket();
            clientSocket.connect(new InetSocketAddress(getAddress(), getPort()), timeout[0]);
            DataOutputStream dos = new DataOutputStream(clientSocket.getOutputStream());
            BufferedReader br = new BufferedReader(new InputStreamReader(clientSocket.getInputStream()));
            byte[] payload = {(byte) 0xFE, (byte) 0x01};
            //dos.writeBytes("\u00FE\u0001");
            dos.write(payload, 0, payload.length);
            rawServerData = br.readLine();
            clientSocket.close();
        } catch (Exception e) {
            serverUp = false;
            //e.printStackTrace();
            return false;
        }

        if (rawServerData == null)
            serverUp = false;
        else {
            serverData = rawServerData.split("\u0000\u0000\u0000");
            if (serverData != null && serverData.length >= NUM_FIELDS) {
                serverUp = true;
                setVersion(serverData[2].replace("\u0000", ""));
                setMotd(serverData[3].replace("\u0000", ""));
                setCurrentPlayers(serverData[4].replace("\u0000", ""));
                setMaximumPlayers(serverData[5].replace("\u0000", ""));
            } else
                serverUp = false;
        }
        return serverUp;
    }

    public String getAddress() {
        return address;
    }

    public void setAddress(String address) {
        this.address = address;
    }

    public int getPort() {
        return port;
    }

    public void setPort(int port) {
        this.port = port;
    }

    public int[] getTimeout() {
        return timeout;
    }

    public void setTimeout(int[] timeout) {
        this.timeout = timeout;
    }

    public String getMotd() {
        return motd;
    }

    public String getVersion() {
        return version;
    }

    public String getCurrentPlayers() {
        return currentPlayers;
    }

    public String getMaximumPlayers() {
        return maximumPlayers;
    }

    public void setMaximumPlayers(String maximumPlayers) {
        this.maximumPlayers = maximumPlayers;
    }

    public void setCurrentPlayers(String currentPlayers) {

        this.currentPlayers = currentPlayers;
    }

    public void setMotd(String motd) {

        this.motd = motd;
    }

    public void setVersion(String version) {

        this.version = version;
    }

    public boolean isServerUp() {
        return serverUp;
    }
}
