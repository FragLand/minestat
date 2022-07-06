# MineStat

MineStat is a Minecraft server status checker.

### Powershell example

```powershell
$ms = ./ServerStatus.ps1 -Address "minecraft.frag.land" -port 25565
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
PS C:\> ./ServerStatus.ps1 -Address "localhost","mc.hypixel.net" -Port 25565 -Protocol Beta,Extendedlegacy,Json -Timeout 2 -verbose
VERBOSE: Beta, ExtendedLegacy, Json
VERBOSE: Beta - Success
VERBOSE: ExtendedLegacy - Success
VERBOSE: Json - Unknown
VERBOSE: Beta, ExtendedLegacy, Json
VERBOSE: Beta - Unknown
VERBOSE: ExtendedLegacy - Unknown
VERBOSE: Json - Success

address         : localhost
port            : 25565
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
                    SUMMER EVENT - LEVEL UP, NEW COSMETICS
slp_protocol    : Json

PS C:\> ./ServerStatus.ps1 "mc.advancius.net" 19132 BedrockRaknet

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
  - Addresss (domain or IP-address) of the server to connect to.
- `Port`: uint
  - Port of the server to connect to.
- `Protocol`: int / str / array
  - SlpProtocol to use. 
- `Timeout`: int
  - Time in seconds before timeout (for each SlpProtocol)

#### Available attributes

- `online`: bool
  - Whether the server is online and reachable with the specified protocol. True if online.
- `address`: str
  - Addresss (domain or IP-address) of the server to connect to.
- `port`: int
  - Port of the server to connect to.
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
- `slp_protocol`: SlpProtocol
  - Protocol used to retrieve information from the server.

#### Extra attributes

- `gamemode`: str (**_Bedrock specific_**)
  - Gamemode currently active on the server (Creative/Survival/Adventure). None if the server is not a Bedrock server.
- `playerlist`: str[] (**_Json specific_**)
  - List of current playernames. \*Ignored by some servers.
- `favicion`: str (**_Json specific_**)
  - Server favicon in base64.
- `motd`: str
  - The raw MOTD returned by the server. May include formatting codes (§) or JSON chat components.
  - Examples (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890):
    - With formatting codes: `§6~~§r §3§lM§7§lA§2§lG§9§lI§4§lC§r1.16 v3§6~~§r`
    - JSON chat components: `{"extra": [{"color": "gold", "text": "~~"}, {"text": " "}, {"bold": true, "color": "dark_aqua", "text": "M"}, {"bold": true, "color": "gray", "text": "A"}, {"bold": true, "color": "dark_green", "text": "G"}, {"bold": true, "color": "blue", "text": "I"}, {"bold": true, "color": "dark_red", "text": "C"}, {"text": "1.16 v3"}, {"color": "gold", "text": "~~"}], "text": ""}`
- `stripped_motd`: str
  - The MOTD with all formatting removed ("human readable").
  - Example (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890)
    - Above MOTD example: `~~ MAGIC1.16 v3~~`