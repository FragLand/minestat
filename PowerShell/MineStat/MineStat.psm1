###
# MineStat.psm1
# Copyright (C) 2020-2024 Ajoro and MineStat contributors.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
###
<#
  .SYNOPSIS
  MineStat is a Minecraft server connection status checker.

  .EXAMPLE
  MineStat -Address 'minecraft.frag.land' -Port 25565 -Timeout 10

  .LINK
  https://github.com/FragLand/minestat
#>

function MineStat {
  [CmdletBinding()]
  param (
    # Addresss (domain or IP-address) of the server to connect to.
    # Input as str or str[]
    [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Server', 'Host', 'IP')]
    [string[]]$Address = "localhost",

    # Port of the server to connect to.
    [uint16]$Port = 25565,

    # SlpProtocol to use
    # Possible values: "BedrockRaknet", "Json", "Extendedlegacy", "Legacy", "Beta"
    # Can combine protocols to check more.
    # Defaults to check: "Json", "Extendedlegacy", "Legacy", "Beta"
    [ValidateSet("BedrockRaknet", "Json", "Extendedlegacy", "Legacy", "Beta", "Query")]
    [string[]]$Protocol = 31,

    # The time in seconds, after which a connection is timed out.
    [int]$Timeout = 5,

    [switch]$IgnoreSRV = $false
  )

  enum ConnStatus {
    # The specified SLP connection succeeded (Request & response parsing OK)
    Success = 1
    # The connection attempt failed for an unknown reason.
    Unknown = 0
    # If a connection was made but the server reponded with a invalid response for this protocol
    InvalidResponse = -1
    # The connection timed out. (Server under too much load? Firewall rules OK?)
    Timeout = -2
    # The socket to the server could not be established. Server offline, wrong hostname or port?
    ConnFail = -3
  }

  [Flags()]
  enum SlpProtocol {
    BedrockRaknet = 32
    Query = 16
    Json = 8
    ExtendedLegacy = 4
    Legacy = 2
    Beta = 1
    Unknown = 0
  }

  $ModuleInfos = Import-PowerShellDataFile -Path "$PsScriptRoot\MineStat.psd1"
  Write-Verbose "MineStat version: $($ModuleInfos.ModuleVersion.ToString())"

  try {
    function New-ServerStatus {
      param (
        [string]$Address,
        [uint16]$Port,
        [int]$Timeout,
        [SlpProtocol]$Protocol,
        [switch]$IgnoreSRV
      )

      $split = $Address -split ":"
      $port = if ($split.Count -gt 1) { $split[1] } else { $Port }
      $protocol = if ($split.Count -eq 3) { $split[2] } else { $Protocol }

      [ServerStatus]::new($split[0], $port, $Timeout, $protocol, $IgnoreSRV)
    }

    $returnArray = foreach ($Addr in $Address) {
      New-ServerStatus -Address $Addr -Port $Port -Timeout $Timeout -Protocol $Protocol -IgnoreSRV:$IgnoreSRV
    }
    
    return $returnArray
  }
  catch {
    throw $_
  }

  class ServerStatus {
    [string]$address = "localhost"
    [uint16]$port = 25565
    [bool]$online = $false
    [string]$version
    [string]$formatted_motd
    [int]$current_players = -1
    [int]$max_players = -1
    [int]$latency = -1
    [SlpProtocol]$slp_protocol

    # hidden values make a better looking return when running from the console
    hidden [int]$timeout
    hidden [string]$favicon
    hidden [string]$gamemode
    hidden [string[]]$playerList
    hidden [string]$motd
    hidden [string]$map
    hidden [string]$plugins
    hidden [string]$stripped_motd
    hidden [string]$connection_status = [ConnStatus]::Unknown

    ServerStatus($address, $port, $timeout, [SlpProtocol]$queryprotocol, $ignoresrv) {
      try {
        $resolved = Resolve-DnsName -type srv _minecraft._tcp.$address -ErrorAction Stop
        if ($ignoresrv -or $resolved.type -ne "SRV") {
          throw
        }
        $this.address = $resolved[0].NameTarget
        $this.port = $resolved[0].port
        Write-Verbose ("Found {0}:{1}" -f $this.address, $this.port)
      }
      catch {
        $this.address = $address
        $this.port = $port
      }
      $this.timeout = $timeout
      Write-Verbose "Checking SlpProtocol: $queryprotocol"

      # Minecraft Bedrock/Pocket/Education Edition (MCPE/MCEE)
      if ($queryprotocol.HasFlag([SlpProtocol]::BedrockRaknet)) {
        $this.connection_status = $this.RequestWithRaknetProtocol()
        Write-Verbose "BedrockRaknet - $($this.connection_status.ToString())"
      }
      # Minecraft 1.4 & 1.5 (legacy SLP)
      if ($queryprotocol.HasFlag([SlpProtocol]::Legacy) -and $this.connection_status -notin [ConnStatus]::ConnFail, [ConnStatus]::Success) {
        $this.connection_status = $this.RequestWithLegacyProtocol()
        Write-Verbose "Legacy - $($this.connection_status.ToString())"
      }
      # Minecraft Beta 1.8 to Release 1.3 (beta SLP)
      if ($queryprotocol.HasFlag([SlpProtocol]::Beta) -and $this.connection_status -notin [ConnStatus]::ConnFail, [ConnStatus]::Success) {
        $this.connection_status = $this.RequestWithBetaProtocol()
        Write-Verbose "Beta - $($this.connection_status.ToString())"
      }
      # Minecraft 1.6 (extended legacy SLP)
      if ($queryprotocol.HasFlag([SlpProtocol]::ExtendedLegacy) -and $this.connection_status -notin [ConnStatus]::ConnFail) {
        $result = $this.RequestWithExtendedLegacyProtocol()
        if ($result -ge $this.connection_status) {
          $this.connection_status = $result
        }
        Write-Verbose "ExtendedLegacy - $result"
      }
      # Minecraft 1.7+ (JSON SLP)
      if ($queryprotocol.HasFlag([SlpProtocol]::Json) -and $this.connection_status -notin [ConnStatus]::ConnFail) {
        $result = $this.RequestWithJsonProtocol()
        if ($result -ge $this.connection_status) {
          $this.connection_status = $result
        }
        Write-Verbose "Json - $result"
      }
      # Minecraft Query/GameSpot4/UT3 protocol.
      if ($queryprotocol.HasFlag([SlpProtocol]::Query) -and $this.connection_status -notin [ConnStatus]::ConnFail) {
        $this.connection_status = $this.FullstatQuery()
        Write-Verbose "Query - $($this.connection_status.ToString())"
      }
    }

    [string[]] generateMotds($rawmotd) {

      function strip_motd($rawmotd) {
        # Function for stripping all formatting codes from a motd.
        $stripped_motd = ""
        if ($rawmotd.gettype().name -eq "string") {
          $stripped_motd = $rawmotd -split "(?:\\u00A7|$([char]0x00A7))+[a-zA-Z0-9]" -join ""
        }
        else {
          $stripped_motd = $rawmotd.text
          if ($rawmotd.extra) {
            foreach ($sub in $rawmotd.extra) {
              $stripped_motd += strip_motd($sub)
            }
          }
          if ($stripped_motd -match [char]0x00A7) {
            $stripped_motd = strip_motd($stripped_motd)
          }
        }
        return $stripped_motd
      }

      function format_motd($rawmotd) {
        # Function for formating all formatting codes as escaped unicode characters from motd.
        $formatcodes = @{
          "$([char]0x00A7)0" = "$([char]27)[0;30m" # Black
          "$([char]0x00A7)1" = "$([char]27)[0;34m" # DarkBlue
          "$([char]0x00A7)2" = "$([char]27)[0;32m" # DarkGreen
          "$([char]0x00A7)3" = "$([char]27)[0;36m" # DarkCyan (Dark aqua)
          "$([char]0x00A7)4" = "$([char]27)[0;31m" # DarkRed
          "$([char]0x00A7)5" = "$([char]27)[0;35m" # DarkMagenta (Dark purple)
          "$([char]0x00A7)6" = "$([char]27)[0;33m" # DarkYellow (Gold)
          "$([char]0x00A7)7" = "$([char]27)[0;37m" # Gray
          "$([char]0x00A7)8" = "$([char]27)[0;90m" # DarkGray
          "$([char]0x00A7)9" = "$([char]27)[0;94m" # Blue
          "$([char]0x00A7)a" = "$([char]27)[0;92m" # Green
          "$([char]0x00A7)b" = "$([char]27)[0;96m" # Cyan (Aqua)
          "$([char]0x00A7)c" = "$([char]27)[0;91m" # Red
          "$([char]0x00A7)d" = "$([char]27)[0;95m" # Magenta (Light purple)
          "$([char]0x00A7)e" = "$([char]27)[0;93m" # Yellow
          "$([char]0x00A7)f" = "$([char]27)[0;97m" # White
          "$([char]0x00A7)g" = "$([char]27)[0;93m" # Yellow (Minecoin Gold)
          "$([char]0x00A7)k" = "$([char]27)[8m"    # obfuscated
          "$([char]0x00A7)l" = "$([char]27)[1m"    # bold
          "$([char]0x00A7)m" = "$([char]27)[9m"    # strikethrough
          "$([char]0x00A7)n" = "$([char]27)[4m"    # underline
          "$([char]0x00A7)o" = "$([char]27)[3m"    # italic
          "$([char]0x00A7)r" = "$([char]27)[0m"    # reset formating
        }

        $formats = @{
          "obfuscated"    = "$([char]27)[8m"
          "bold"          = "$([char]27)[1m"
          "strikethrough" = "$([char]27)[9m"
          "underline"     = "$([char]27)[4m"
          "italic"        = "$([char]27)[3m"
          "reset"         = "$([char]27)[0m"
        }

        $colorcodes = @{
          black         = "$([char]27)[0;30m"
          dark_blue     = "$([char]27)[0;34m"
          dark_green    = "$([char]27)[0;32m"
          dark_aqua     = "$([char]27)[0;36m"
          dark_red      = "$([char]27)[0;31m"
          dark_purple   = "$([char]27)[0;35m"
          gold          = "$([char]27)[0;33m"
          gray          = "$([char]27)[0;37m"
          dark_gray     = "$([char]27)[0;90m"
          blue          = "$([char]27)[0;94m"
          green         = "$([char]27)[0;92m"
          aqua          = "$([char]27)[0;96m"
          red           = "$([char]27)[0;91m"
          light_purple  = "$([char]27)[0;95m"
          yellow        = "$([char]27)[0;93m"
          white         = "$([char]27)[0;97m"
          minecoin_gold = "$([char]27)[0;93m" # Yellow (Minecoin Gold)
        }

        $formatted_motd = ""
        if ($rawmotd.gettype().name -eq "string") {
          $rawmotd = $rawmotd -replace "\\u00A7", "$([char]0x00A7)"
          foreach ($format in ($rawmotd -split "($([char]0x00A7)+[a-zA-Z0-9])")) {
            if ($format -in $formatcodes.Keys) {
              $formatted_motd += $formatcodes.$format
            }
            if ($format -match [char]0x00A7) {
              continue
            }
            else {
              $formatted_motd += $format
            }
          }
          return $formatted_motd + $formats.reset
        }
        else {
          foreach ($entry in $rawmotd) {
            $formatted_motd += $formats.reset
            if ($entry.keys.length -ge 2 -and $entry.text) {
              if ($entry.color) {
                $formatted_motd += $colorcodes.($entry.color)
              }
              foreach ($option in $formats.Keys) {
                if ($option -in $entry.keys) {
                  $formatted_motd += $formats.$option
                }
              }
            }
            $formatted_motd += $entry.text
            if ($entry.extra) {
              format_motd($entry.extra)
            }
          }
          if ($formatted_motd -match [char]0x00A7) {
            $formatted_motd = format_motd($formatted_motd)
          }
          return $formatted_motd + $formats.reset
        }
      }

      $stripped = strip_motd($rawmotd)
      $formatted = format_motd($rawmotd)
      return $stripped, $formatted
    }

    [ConnStatus] FullstatQuery() {
      <#
      Method for querying a Minecraft Java server using the fullstat Query / GameSpot4 / UT3 protocol.

      Needs to be enabled on the Minecraft server using:
      "enable-query=true"
      in the servers "server.properties" file.

      This method ONLY supports full stat querys.
      Documentation for this protocol: https://wiki.vg/Query
      #>

      $sock = New-Object System.Net.Sockets.UdpClient
      $sock.Client.ReceiveTimeout = $this.timeout * 1000
      $sock.Client.SendTimeout = $this.timeout * 1000

      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      try {
        $sock.Connect($this.address, $this.port)
      }
      catch {
        $this.latency = -1
        $stopwatch.Stop()
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }

      $querymagic = [byte[]]@(254, 253) # b"\xFE\xFD"
      $handshake_packettype = [byte[]]@(9)
      $stat_packettype = [byte[]]@(0)

      $session_id_int = Get-Random -Minimum 0 -Maximum 2147483647
      $session_id_bytes = [BitConverter]::GetBytes($session_id_int -band 0x0F0F0F0F)
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($session_id_bytes);
      }

      $handshake_packet = $querymagic + $handshake_packettype + $session_id_bytes

      try {
        $sock.Send($handshake_packet, $handshake_packet.Length)
        $handshake_res = $sock.Receive([ref]$null)

        $challenge_token = $handshake_res[5..$($handshake_res.Length - 1)]
        $challenge_token_int = [int][System.Text.Encoding]::UTF8.GetString($challenge_token)
        $challenge_token_bytes = [BitConverter]::GetBytes($challenge_token_int)
        if ([System.BitConverter]::IsLittleEndian) {
          [System.Array]::Reverse($challenge_token_bytes);
        }

        $req_packet = $querymagic + $stat_packettype + $session_id_bytes + $challenge_token_bytes + [byte[]](0, 0, 0, 0)

        $sock.Send($req_packet, $req_packet.Length)
        $raw_res = $sock.Receive([ref]$null)

        $sock.Close()

        return $this.ParseFullstatQuery($raw_res[($session_id_bytes.Length + 1)..($raw_res.Length - 1)])
      }
      catch [System.Net.Sockets.SocketException] {
        if ($_.Exception.Message -match "timed out") {
          return [ConnStatus]::Timeout
        }
        else {
          return [ConnStatus]::Unknown
        }
      }
      finally {
        $sock.Close()
      }
    }

    hidden [ConnStatus] ParseFullstatQuery([byte[]]$raw_res) {
      <#
      Helper method for parsing the reponse from a query request.

      See https://wiki.vg/Query for details.

      This implementation does not parse every value returned by the query protocol.
      #>
      try {
        # Remove unnecessary padding
        $res = $raw_res[11..($raw_res.Length - 1)]

        # Split stats from players
        $raw_stats, $raw_players = [Text.Encoding]::UTF8.GetString($res) -split [Text.Encoding]::UTF8.GetString(@(0x00, 0x00, 0x01, 0x70, 0x6C, 0x61, 0x79, 0x65, 0x72, 0x5F, 0x00, 0x00))

        # Split stat keys and values into individual elements and remove unnecessary padding
        $stat_list = $raw_stats -split "`0"

        # Move keys and values into a dictionary, the keys are also decoded
        $stats = @{}
        for ($i = 0; $i -lt $stat_list.Length; $i += 2) {
          $key = $stat_list[$i]
          $value = $stat_list[$i + 1]
          $stats[$key] = $value
        }

        # Extract motd (hostname) or MOTD
        $this.motd = $null
        if ($stats.ContainsKey("hostname")) {
          $this.motd = $stats["hostname"]
        }
        elseif ($stats.ContainsKey("MOTD")) {
          $this.motd = $stats["MOTD"]
        }
        $this.stripped_motd, $this.formatted_motd = $this.generateMotds($this.motd)

        # Extract the server's Minecraft version
        $this.version = $null
        if ($stats.ContainsKey("version")) {
          $this.version = $stats["version"]
        }

        # Extract list of plugins
        $this.plugins = @()
        if ($stats.ContainsKey("plugins")) {
          $raw_plugins = $stats["plugins"]
          if ($raw_plugins -ne "") {
            # The plugins are separated by " ;"
            $this.plugins = $raw_plugins -split " ;"

            # There may be information about the server software in the first plugin element
            if ($this.plugins[0] -match ":") {
              $this.version, $this.plugins[0] = $this.plugins[0] -split ": ", 2
            }
          }
        }

        # Extract the name of the map the server is running on
        if ($stats.ContainsKey("map")) {
          $this.map = $stats["map"]
        }

        # Extract number of online and maximum allowed players
        $this.current_players = 0
        $this.max_players = 0
        if ($stats.ContainsKey("numplayers")) {
          $this.current_players = [int]$stats["numplayers"]
          $this.max_players = [int]$stats["maxplayers"]
        }

        $this.playerList = $raw_players.TrimEnd("`0") -split "`0"
        $this.Slp_Protocol = "Query";
        $this.online = $true;
        $this.Gamemode = $stats.gametype

        return [ConnStatus]::Success

      }
      catch {
        return [ConnStatus]::Unknown
      }
    }

    [ConnStatus] RequestWithRaknetProtocol() {
      <#
      Method for querying a Bedrock server (Minecraft PE, Windows 10 or Education Edition).
      The protocol is based on the RakNet protocol.

      See https://wiki.vg/Raknet_Protocol#Unconnected_Ping

      Note: This method currently works as if the connection is handled via TCP (as if no packet loss might occur).
      Packet loss handling should be implemented (resending).
      #>
      function readbytestream([System.Collections.Generic.Queue[byte]]$que, [int]$count) {
        $resultBuffer = New-Object System.Collections.Generic.List[byte]
        for ($i = 0; $i -lt $count; $i++) {
          $resultBuffer.Add($que.Dequeue())
        }
        return $resultBuffer.ToArray()
      }

      $sock = New-Object System.Net.Sockets.UdpClient
      $sock.Client.ReceiveTimeout = $this.timeout * 1000
      $sock.Client.SendTimeout = $this.timeout * 1000

      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      try {
        $sock.Connect($this.address, $this.port)
      }
      catch {
        $this.latency = -1
        $stopwatch.Stop()
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }

      [byte[]]$raknetMagic = @(0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34, 0x56, 0x78)

      [System.Collections.Generic.List[byte]]$raknetPingHandshakePacket = 0x01

      $unixtime = [System.BitConverter]::GetBytes([DateTimeOffset]::Now.ToUnixTimemilliseconds())
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($unixtime);
      }
      $raknetPingHandshakePacket.AddRange($unixtime)
      $raknetPingHandshakePacket.AddRange($raknetmagic)
      $raknetPingHandshakePacket.AddRange([System.BitConverter]::GetBytes([Int64]0x02))

      $sendlen = $sock.Send($raknetPingHandshakePacket.ToArray(), $raknetPingHandshakePacket.Count)

      if ($sendlen -ne $raknetPingHandshakePacket.Count) {
        return [ConnStatus]::Unknown
      }
      try {
        [System.Collections.Generic.Queue[byte]]$response = $sock.Receive([ref]$null)

        if ($response.Dequeue() -ne 0x1c) {
          return [ConnStatus]::InvalidResponse
        }

        # responseTimeStamp (never used)
        [System.BitConverter]::ToInt64((readbytestream $response 8), 0)
        # responseServerGUID (never used)
        [System.BitConverter]::ToInt64((readbytestream $response 8), 0)

        [byte[]]$responseMagic = readbytestream $response 16

        if ($null -ne (Compare-Object $responseMagic $raknetMagic -CaseSensitive)) {
          return [ConnStatus]::Unknown
        }
        if ([System.BitConverter]::IsLittleEndian) {
          [System.Array]::Reverse($response);
        }

        # responseIdStringLength (never used)
        [System.BitConverter]::ToUInt16((readbytestream $response 2), 0)

        $temp = readbytestream $response $response.Count
        $responseIdString = [System.Text.Encoding]::UTF8.GetString($temp)
      }
      catch {
        $this.latency = -1
        $stopwatch.Stop()
        return [ConnStatus]::Timeout
      }
      finally {
        $sock.Close()
      }

      return $this.ParseBedrockPayload($responseIdString)
    }

    hidden [ConnStatus] ParseBedrockPayload([string]$payload) {
      $values = $payload -split ";"
      $keys = @("edition", "motd_1", "protocol_version", "version", "current_players", "max_players",
        "server_uid", "motd_2", "gamemode", "gamemode_numeric", "port_ipv4", "port_ipv6")

      $payload_obj = @{}
      for ($i = 0; $i -lt $keys.Count; $i++) {
        $payload_obj.Add($keys[$i], $values[$i])
      }
      $this.Slp_Protocol = "BedrockRaknet";
      $this.online = $true;
      $this.current_players = $payload_obj.current_players
      $this.max_players = $payload_obj.max_players
      $this.version = @($payload_obj.version, "($($payload_obj.edition))") -join " "
      $this.motd = $payload_obj.motd_1 + "`n" + $payload_obj.motd_2
      $this.stripped_motd, $this.formatted_motd = $this.generateMotds($this.motd)
      $this.Gamemode = $payload_obj.gamemode

      return [ConnStatus]::Success
    }

    [ConnStatus] RequestWithJsonProtocol() {
      <#
      Method for querying a modern (MC Java >= 1.7) server with the SLP protocol.
      This protocol is based on encoded JSON, see the documentation at wiki.vg below
      for a full packet description.

      See https://wiki.vg/Server_List_Ping#Current
      #>

      function WriteLeb128([int]$value) {
        [System.Collections.Generic.List[byte]]$byteList = @()
        if ($value -eq -1) {
          [uint32] $actual = [uint32]"0xffffffff"
        }
        else {
          [uint32] $actual = [uint32]$value
        }
        do {
          [byte]$temp = $actual -band 127
          $actual = $actual -shr 7
          if ($actual -ne 0) {
            $temp = $temp -bor 128
          }
          $byteList.Add($temp)
        } while ($actual -ne 0)

        return $byteList.ToArray()
      }

      function WriteLeb128Stream([System.Net.Sockets.NetworkStream]$stream, [int] $value) {
        if ($value -eq -1) {
          [uint32] $actual = [uint32]"0xffffffff"
        }
        else {
          [uint32] $actual = [uint32]$value
        }
        do {
          [byte]$temp = $actual -band 127
          $actual = $actual -shr 7
          if ($actual -ne 0) {
            $temp = $temp -bor 128
          }
          $stream.WriteByte($temp)
        } while ($actual -ne 0)
      }

      function ReadLeb128Stream([System.Net.Sockets.NetworkStream]$stream) {
        $numRead = 0
        $result = 0
        do {
          [int] $r = $stream.ReadByte()
          if ($r -eq -1) {
            break
          }
          [byte]$read = $r
          [int] $value = $read -band 127
          $result = $result -bor ($value -shl (7 * $numRead))

          $numRead++
          if ($numread -gt 5) {
            throw "VarInt is too big."
          }
        } while (
        ($read -band 128) -ne 0
        )
        if ($numRead -eq 0) {
          throw "Unexpected end of VarInt stream."
        }
        return $result
      }

      $tcpclient = New-Object System.Net.Sockets.tcpclient
      $tcpclient.ReceiveTimeout = $this.Timeout * 1000
      $tcpclient.SendTimeout = $this.Timeout * 1000
      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      $result = $tcpclient.BeginConnect($this.Address, $this.Port, $null, $null)
      $isResponsive = $result.AsyncWaitHandle.WaitOne([System.TimeSpan]::FromSeconds($this.Timeout))

      if (-not $isResponsive) {
        $this.latency = -1
        return [ConnStatus]::Timeout
      }
      try {
        $tcpclient.EndConnect($result)
      }
      catch [System.Net.Sockets.SocketException] {
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }
      $stream = $tcpclient.GetStream()

      [System.Collections.Generic.List[byte]]$jsonPingHandshakePacket = 0x00

      $jsonPingHandshakePacket.AddRange([byte[]] (WriteLeb128 -1))

      $serverAddr = [System.Text.Encoding]::UTF8.GetBytes($this.Address)
      $jsonPingHandshakePacket.AddRange([byte[]] (WriteLeb128 $serverAddr.Length))
      $jsonPingHandshakePacket.AddRange($serverAddr)

      $serverPort = [System.BitConverter]::GetBytes($this.Port)
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($serverPort);
      }
      $jsonPingHandshakePacket.AddRange($serverPort)
      $jsonPingHandshakePacket.AddRange([byte[]] (WriteLeb128 1))

      $jsonPingHandshakePacket.InsertRange(0, [byte[]] (WriteLeb128 $jsonPingHandshakePacket.Count))
      try {
        $stream.Write($jsonPingHandshakePacket.ToArray() , 0, $jsonPingHandshakePacket.Count)

        WriteLeb128stream $stream 1
        $stream.WriteByte(0x00)

        $responseSize = ReadLeb128Stream $stream
      }
      catch {
        return [ConnStatus]::Unknown
      }
      if ($responseSize -lt 3) {
        return [ConnStatus]::InvalidResponse
      }

      $responsePacketId = ReadLeb128Stream $stream

      if ($responsePacketId -ne 0x00) {
        return [ConnStatus]::InvalidResponse
      }

      $responsePayloadLength = ReadLeb128Stream $stream

      $responsePayload = $this.NetStreamReadExact($stream, $responsePayloadLength)

      return $this.ParseJsonProtocolPayload($responsePayload)
    }

    hidden [ConnStatus] ParseJsonProtocolPayload([byte[]]$rawPayload) {

      # Adds support for powershell version 5 since it dosn't support -Ashashtable tag on convertfrom-json
      # Thanks to Adam Bertram
      # https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/
      function ConvertTo-Hashtable {
        [CmdletBinding()]
        [OutputType('hashtable')]
        param (
          [Parameter(ValueFromPipeline)]
          $InputObject
        )
        process {
          ## Return null if the input is null. This can happen when calling the function
          ## recursively and a property is null
          if ($null -eq $InputObject) {
            return $null
          }
          ## Check if the input is an array or collection. If so, we also need to convert
          ## those types into hash tables as well. This function will convert all child
          ## objects into hash tables (if applicable)
          if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
              foreach ($object in $InputObject) {
                ConvertTo-Hashtable -InputObject $object
              }
            )
            ## Return the array but don't enumerate it because the object may be pretty complex
            Write-Output -InputObject $collection -NoEnumerate
          }
          elseif ($InputObject -is [psobject]) {
            ## If the object has properties that need enumeration
            ## Convert it to its own hash table and return it
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
              $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            $hash
          }
          else {
            ## If the object isn't an array, collection, or other object, it's already a hash table
            ## So just return it.
            $InputObject
          }
        }
      }

      try {
        $payload_obj = ConvertFrom-Json ([System.Text.Encoding]::UTF8.GetString($rawPayload)) | ConvertTo-Hashtable
      }
      catch {
        return [ConnStatus]::InvalidResponse
      }
      $this.version = $payload_obj.version.name
      $descriptionElement = $payload_obj.description

      if ($null -ne $descriptionElement -and $descriptionElement.GetType().name -eq "string") {
        $this.motd = $descriptionElement
      }
      else {
        $this.motd = ConvertTo-Json $descriptionElement
      }
      $this.stripped_motd, $this.formatted_motd = $this.generateMotds($descriptionElement)

      $playerSampleElement = $payload_obj.players.sample
      if ($null -ne $playerSampleElement -and $playerSampleElement.GetType().BaseType.Name -eq "array") {
        $this.PlayerList = $playerSampleElement.name
      }

      if ($null -eq $this.version -or $null -eq $this.motd) {
        return [ConnStatus]::InvalidResponse
      }

      $this.Favicon = $payload_obj.favicon
      # $this.Protocol = $payload_obj.version.protocol;
      $this.max_players = $payload_obj.players.max;
      $this.current_players = $payload_obj.players.online;
      $this.Slp_Protocol = "Json";
      $this.online = $true
      return [ConnStatus]::Success
    }

    [ConnStatus] RequestWithExtendedLegacyProtocol() {
      <#
      Minecraft 1.6 SLP query, extended legacy ping protocol.
      All modern servers are currently backwards compatible with this protocol.

      See https://wiki.vg/Server_List_Ping#1.6
      #>
      $tcpclient = New-Object System.Net.Sockets.tcpclient
      $tcpclient.ReceiveTimeout = $this.Timeout * 1000
      $tcpclient.SendTimeout = $this.Timeout * 1000
      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      $result = $tcpclient.BeginConnect($this.Address, $this.Port, $null, $null)
      $isResponsive = $result.AsyncWaitHandle.WaitOne([System.TimeSpan]::FromSeconds($this.Timeout))

      if (-not $isResponsive) {
        $this.latency = -1
        return [ConnStatus]::Timeout
      }
      try {
        $tcpclient.EndConnect($result)
      }
      catch [System.Net.Sockets.SocketException] {
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }
      $stream = $tcpclient.GetStream()

      [System.Collections.Generic.List[byte]]$extlegacyPingPacket = @(0xFE, 0x01, 0xFA, 0x00, 0x0B)

      $extlegacyPingPacket.AddRange([System.Text.Encoding]::BigEndianUnicode.GetBytes("MC|PingHost"))

      $reqByteLen = [System.BitConverter]::GetBytes([Int16](7 + $this.Address.Length * 2))
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($reqByteLen);
      }
      $extlegacyPingPacket.AddRange($reqByteLen)

      $extlegacyPingPacket.Add(0x4A)
      $addressLen = [System.BitConverter]::GetBytes([Int16]$this.Address.Length)
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($addressLen);
      }
      $extlegacyPingPacket.AddRange($addressLen)

      $extLegacyPingPacket.AddRange([System.Text.Encoding]::BigEndianUnicode.GetBytes($this.Address))

      $portbytes = [System.BitConverter]::GetBytes([int]$this.Port)
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($portbytes);
      }
      $extlegacyPingPacket.AddRange($portbytes)

      $stream.Write($extLegacyPingPacket.ToArray(), 0, $extLegacyPingPacket.Count);
      try {
        [byte[]] $responsePacketHeader = $this.NetStreamReadExact($stream, 3)
      }
      catch {
        return [ConnStatus]::Unknown
      }
      if ($responsePacketHeader[0] -ne 0xFF) {
        return [ConnStatus]::InvalidResponse
      }
      $responsePacketHeader
      $payloadLengthRaw = [System.Byte[]]::CreateInstance([System.Byte], $responsePacketHeader.Length - 1)

      [array]::Copy($responsePacketHeader, 1, $payloadLengthRaw, 0, ($responsePacketHeader.Length - 1))
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($payloadLengthRaw);
      }
      $payloadLength = [System.BitConverter]::ToUInt16($payloadLengthRaw, 0)
      [byte[]]$payload = $this.NetStreamReadExact($stream, ($payloadLength * 2))

      return $this.ParseLegacyProtocol($payload, "ExtendedLegacy")
    }

    [ConnStatus] RequestWithLegacyProtocol() {
      <#
      Minecraft 1.4-1.5 SLP query, server response contains more info than beta SLP

      See https://wiki.vg/Server_List_Ping#1.4_to_1.5
      #>
      $tcpclient = New-Object System.Net.Sockets.tcpclient
      $tcpclient.ReceiveTimeout = $this.Timeout * 1000
      $tcpclient.SendTimeout = $this.Timeout * 1000
      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      $result = $tcpclient.BeginConnect($this.Address, $this.Port, $null, $null)
      $isResponsive = $result.AsyncWaitHandle.WaitOne([System.TimeSpan]::FromSeconds($this.Timeout))

      if (-not $isResponsive) {
        $this.latency = -1
        return [ConnStatus]::Timeout
      }
      try {
        $tcpclient.EndConnect($result)
      }
      catch [System.Net.Sockets.SocketException] {
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }
      $stream = $tcpclient.GetStream()

      [byte[]] $legacyPingPacket = 0xFE, 0x01

      try {
        $stream.Write($legacyPingPacket, 0, $legacyPingPacket.Length);
        [byte[]] $responsePacketHeader = $this.NetStreamReadExact($stream, 3)
      }
      catch {
        return [ConnStatus]::Unknown
      }

      if ($responsePacketHeader[0] -ne 0xFF) {
        return [ConnStatus]::InvalidResponse
      }
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($responsePacketHeader);
      }

      $payloadLength = [System.BitConverter]::ToUInt16($responsePacketHeader, 0)
      if ($payloadLength -lt 3) {
        return [ConnStatus]::InvalidResponse
      }
      [byte[]]$payload = $this.NetStreamReadExact($stream , ($payloadLength * 2))

      return $this.ParseLegacyProtocol($payload, "Legacy")
    }

    hidden [ConnStatus] ParseLegacyProtocol([byte[]]$rawPayload, [SlpProtocol]$SlpProtocol) {
      $payloadString = [System.Text.Encoding]::BigEndianUnicode.GetString($rawPayload, 0, $rawPayload.Length)
      $payloadArray = $payloadString.Split([char]0x0000)
      if ($payloadArray.Length -ne 6) {
        return [ConnStatus]::InvalidResponse
      }
      $this.Version = $payloadArray[2]
      $this.max_players = $payloadArray[5]
      $this.current_players = $payloadArray[4]
      $this.motd = $payloadArray[3]
      $this.stripped_motd, $this.formatted_motd = $this.generateMotds($this.motd)
      $this.Slp_Protocol = $SlpProtocol
      $this.online = $true
      return [ConnStatus]::Success
    }

    [ConnStatus] RequestWithBetaProtocol() {
      <#
      Minecraft Beta 1.8 to Release 1.3 SLP protocol
      See https://wiki.vg/Server_List_Ping#Beta_1.8_to_1.3
      #>
      $tcpclient = New-Object System.Net.Sockets.tcpclient
      $tcpclient.ReceiveTimeout = $this.Timeout * 1000
      $tcpclient.SendTimeout = $this.Timeout * 1000
      $stopwatch = New-Object System.Diagnostics.Stopwatch
      $stopwatch.Start();

      $result = $tcpclient.BeginConnect($this.Address, $this.Port, $null, $null)
      $isResponsive = $result.AsyncWaitHandle.WaitOne([System.TimeSpan]::FromSeconds($this.Timeout))

      if (-not $isResponsive) {
        $this.latency = -1
        return [ConnStatus]::Timeout
      }
      try {
        $tcpclient.EndConnect($result)
      }
      catch [System.Net.Sockets.SocketException] {
        return [ConnStatus]::ConnFail
      }
      $stopwatch.Stop()
      if ($this.latency -eq -1) {
        $this.latency = $stopwatch.ElapsedMilliseconds
      }
      $stream = $tcpclient.GetStream()

      [byte[]] $betaPingPacket = 0xFE

      try {
        $stream.Write($betaPingPacket, 0, $betaPingPacket.Length)
        [byte[]] $responsePacketHeader = $this.NetStreamReadExact( $stream, 3)
      }
      catch {
        return [ConnStatus]::Unknown
      }

      if ($responsePacketHeader[0] -ne 0xFF) {
        return [ConnStatus]::InvalidResponse
      }
      if ([System.BitConverter]::IsLittleEndian) {
        [System.Array]::Reverse($responsePacketHeader);
      }
      $payloadLength = [System.BitConverter]::ToUInt16($responsePacketHeader, 0)
      [byte[]]$payload = $this.NetStreamReadExact($stream, ($payloadLength * 2))

      return $this.ParseBetaProtocol($payload)
    }

    hidden [ConnStatus] ParseBetaProtocol([byte[]]$rawPayload) {
      $payloadString = [System.Text.Encoding]::BigEndianUnicode.GetString($rawPayload, 0, $rawPayload.Length)
      $payloadArray = $payloadString.Split([char]0x00A7)
      if ($payloadArray.Length -lt 3) {
        return [ConnStatus]::InvalidResponse
      }

      $this.Version = "<= 1.3";
      $this.max_players = $payloadArray[$payloadArray.Length - 1];
      $this.current_players = $payloadArray[$payloadArray.Length - 2];
      $this.motd = $payloadArray[0..($payloadArray.Length - 3)] -join [char]0x00A7
      $this.stripped_motd, $this.formatted_motd = $this.generateMotds($this.motd)
      $this.Slp_Protocol = "Beta";
      $this.Online = $true

      return [ConnStatus]::Success
    }

    hidden [byte[]] NetStreamReadExact([System.Net.Sockets.NetworkStream]$stream, [int]$size) {
      $totalReadBytes = 0
      $resultBuffer = New-Object System.Collections.Generic.List[byte]

      do {
        $tempBuffer = [System.Byte[]]::CreateInstance([System.Byte], $size - $totalReadBytes)

        $readBytes = $stream.Read($tempBuffer, 0, $size - $totalReadBytes)

        if ($readBytes -eq 0) {
          throw [System.IO.IOException]
        }
        $resultBuffer.AddRange($tempBuffer)
        $totalReadBytes += $readBytes;
      } while ($totalReadBytes -lt $size)

      return $resultBuffer.ToArray();
    }
  }
}
