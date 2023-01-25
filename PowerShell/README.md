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
PS C:\> MineStat -Address "localhost","hypixel.net" -Port 25568 -Protocol Extendedlegacy,Json -Timeout 2 -verbose
VERBOSE: MineStat version: 2.0.6
VERBOSE: _minecraft._tcp.localhost
VERBOSE: Checking SlpProtocol: ExtendedLegacy, Json
VERBOSE: ExtendedLegacy - Success
VERBOSE: Json - Unknown
VERBOSE: _minecraft._tcp.hypixel.net
VERBOSE: Found mc.hypixel.net:25565
VERBOSE: Checking SlpProtocol: ExtendedLegacy, Json
VERBOSE: ExtendedLegacy - Unknown
VERBOSE: Json - Success

address         : localhost
port            : 25568
online          : True
current_players : 3
max_players     : 20
latency         : 0
version         : 1.6
formatted_motd  : A Minecraft Server
slp_protocol    : ExtendedLegacy

address         : mc.hypixel.net
port            : 25565
online          : True
current_players : 59070
max_players     : 200000
latency         : 22
version         : Requires MC 1.8 / 1.19
formatted_motd  :                 Hypixel Network [1.8-1.19]
                    
slp_protocol    : Json

PS C:\> MineStat "mc.advancius.net:19132" -Protocol BedrockRaknet

address         : mc.advancius.net
port            : 19132
online          : True
current_players : 131
max_players     : 300
latency         : 42
version         : 1.19.0 discord.advancius.net (MCPE)
formatted_motd  : Advancius Network
slp_protocol    : BedrockRaknet
```
#### Inputs

- `Address`: str[] / str
  - Address (domain or IP-address) of the server to connect to. 
  - Can take array input and also take `address:port` as input.
  - Tries to detect address using SRV record first.
  - Default: localhost
- `Port`: uint
  - Port of the server to connect to.
  - Tries to detect port using SRV record first.
  - Default: 25565
- `Protocol`: int / str / array
  - SlpProtocol to use.
  - Dosn't use BedrockRaknet by default.
- `Timeout`: int
  - Time in seconds before timeout (for each SlpProtocol)
  - Default: 5

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

- `gamemode`: str (**_Bedrock specific_**)
  - Gamemode currently active on the server (Creative/Survival/Adventure). None if the server is not a Bedrock server.
- `playerlist`: str[] (**_Json specific_**)
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
