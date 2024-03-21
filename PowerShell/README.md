# MineStat

MineStat is a Minecraft server status checker.

### PowerShell example

[![Gallery](https://img.shields.io/powershellgallery/v/MineStat?color=blue&label=PowerShell%20module&style=plastic)](https://www.powershellgallery.com/packages/MineStat/)

To install the module: `Install-Module -Name MineStat`

```powershell
Import-Module MineStat
$ms = MineStat -Address "minecraft.frag.land" -port 25565
"Minecraft server status of '{0}' on port {1}:" -f $ms.Address, $ms.Port

if ($ms.Online) {
  "Server is online running version {0} with {1} out of {2} players." -f $ms.Version, $ms.Current_Players, $ms.Max_Players
  "Message of the day: {0}" -f $ms.Stripped_Motd
  "Latency: {0}ms" -f $ms.Latency
  "Connected using SLP protocol '{0}'" -f $ms.Slp_Protocol
}else {
  "Server is offline!"
}
```

### Commandline Example

```powershell
PS C:\> MineStat -Address "localhost","hypixel.net" -Port 25568 -Protocol Extendedlegacy,Json,Query -Timeout 2 -verbose
VERBOSE: MineStat version: 3.0.0
VERBOSE: _minecraft._tcp.localhost
VERBOSE: Checking SlpProtocol: ExtendedLegacy, Json, Query
VERBOSE: ExtendedLegacy - Success
VERBOSE: Json - Unknown
VERBOSE: Query - Success
VERBOSE: _minecraft._tcp.hypixel.net
VERBOSE: Found mc.hypixel.net:25565
VERBOSE: Checking SlpProtocol: ExtendedLegacy, Json, Query
VERBOSE: ExtendedLegacy - Unknown
VERBOSE: Json - Success
VERBOSE: Query - Unknown

address         : localhost
port            : 25568
online          : True
version         : 1.6.2
formatted_motd  : Hello!
current_players : 0
max_players     : 20
latency         : 1
slp_protocol    : Query

address         : mc.hypixel.net
port            : 25565
online          : True
version         : Requires MC 1.8 / 1.20
formatted_motd  :                 Hypixel Network [1.8-1.20]
                      DOUBLE COINS + EXP - SKYBLOCK 0.19.2
current_players : 46533
max_players     : 200000
latency         : 5
slp_protocol    : Json

PS C:\> MineStat mc.advancius.net:19132:BedrockRaknet -Protocol Json -IgnoreSRV

address         : mc.advancius.net
port            : 19132
online          : True
version         : 1.20.10 (MCPE)
formatted_motd  : Advancius Network
                  discord.advancius.net
current_players : 145
max_players     : 300
latency         : 24
slp_protocol    : BedrockRaknet
```
#### Inputs

- `Address`: str[] / str
  - Address (domain or IP-address) of the server to connect to. 
  - Can take array input and also take `address:port:protocol` as input which overwrites port and protocol.
  - Tries to detect address using SRV record first.
  - Default: localhost
- `Port`: uint
  - Port of the server to connect to.
  - Tries to detect port using SRV record first.
  - Default: 25565
- `Protocol`: int / str / array
  - SlpProtocol to use. ("BedrockRaknet", "Json", "Extendedlegacy", "Legacy", "Beta", "Query")
  - Dosn't use BedrockRaknet by default.
- `Timeout`: int
  - Time in seconds before timeout (for each SlpProtocol)
  - Default: 5
- `IgnoreSRV`: bool
  - Stops lookup of SRV record to autofill address and port.
  - Default: false

#### Available attributes

- `address`: str
  - Addresss (domain or IP-address) of the server to connect to.
- `port`: int
  - Port of the server to connect to.
- `online`: bool
  - Whether the server is online and reachable with the specified protocol. True if online.
- `version`: str
  - String describing the server Minecraft version. In vanilla servers the version number (e.g. 1.18.2),
    may be modified by the server (e.g. by ViaVersion). On Bedrock servers includes the Edition (MCEE/MCPE)
    and the server info.
- `formatted_motd`: str
  - The MOTD with all formatting as unicode escape characters.
- `current_players`: int
  - Count of players currently online on the server.
- `max_players`: int
  - Count of maximum allowed players as reported by the server.
- `latency`: int
  - Time in milliseconds the server took to respond to the information request.
- `slp_protocol`: minestat.SlpProtocol
  - Protocol used to retrieve information from the server.

#### Extra attributes

- `gamemode`: str (**_Bedrock & Query specific_**)
  - Gamemode currently active on the server (Creative/Survival/Adventure). None if the server is not a Bedrock server. Returns "gametype" with queryprotocol
- `playerlist`: str[] (**_Json & Query specific_**)
  - List of current playernames. \*Ignored by some servers.
- `favicon`: str (**_Json specific_**)
  - Server favicon in base64.
- `connection_status`: minestat.ConnStatus
  - Status of connection ("Success", "Connfail", "InvalidResponse", "Timeout", or "Unknown").
- `motd`: str
  - The raw MOTD returned by the server. May include formatting codes (§) or JSON chat components.
  - Examples (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890):
    - With formatting codes: `§6~~§r §3§lM§7§lA§2§lG§9§lI§4§lC§r1.16 v3§6~~§r`
    - JSON chat components: `{"extra": [{"color": "gold", "text": "~~"}, {"text": " "}, {"bold": true, "color": "dark_aqua", "text": "M"}, {"bold": true, "color": "gray", "text": "A"}, {"bold": true, "color": "dark_green", "text": "G"}, {"bold": true, "color": "blue", "text": "I"}, {"bold": true, "color": "dark_red", "text": "C"}, {"text": "1.16 v3"}, {"color": "gold", "text": "~~"}], "text": ""}`
- `stripped_motd`: str
  - The MOTD with all formatting removed ("human readable").
  - Example (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890)
    - Above MOTD example: `~~ MAGIC1.16 v3~~`
- `timeout`: int
  - Time in seconds before timeout (for each SlpProtocol) from input
- `map`: string (**_Query specific_**)
  - Name of the current map
- `plugins`: array (**_Query specific_**)
  - Array of the plugins on the server
