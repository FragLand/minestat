MineStat
========

MineStat is a Minecraft server status checker library for Python, supporting a wide range of Minecraft servers:
- Java Edition since Minecraft version Beta 1.8 (September 2011),
- Bedrock Edition starting with Minecraft version 0.14 (March 2018), maybe earlier.

Supports [Minecraft SRV record resolution](https://minecraft.wiki/w/Tutorials/Setting_up_a_server#The_SRV_record),
which requires the package [`dnspython`](https://pypi.org/project/dnspython/).
This mechanism allows server operators to use a custom port or host without the player having to type it.
One common server utilizing this feature example is `2b2t`: The actual server is at `connect.2b2t.org`, while users simply use `2bt2.org`.
MineStat supports querying both, if `dnspython` is installed.

### Python example

[![PyPI](https://img.shields.io/pypi/v/minestat?color=green&label=PyPI%20package&style=plastic)](https://pypi.org/project/minestat/)

To use the PyPI package: `pip install minestat`

```python
import minestat

ms = minestat.MineStat('minecraft.frag.land', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  # Bedrock-specific attribute:
  if ms.gamemode:
    print('Game mode: %s' % ms.gamemode)
  print('Message of the day: %s' % ms.motd)
  print('Message of the day without formatting: %s' % ms.stripped_motd)
  print('Latency: %sms' % ms.latency)
  print('Connected using protocol: %s' % ms.slp_protocol)
else:
  print('Server is offline!')
```

#### Available parameters
The following parameters exist for the `MineStat` object:

- `address`: str,
  - Hostname or IP address of the Minecraft server.
- `port`: int = 0,
  - Optional port of the Minecraft server. Defaults to auto detection (25565 for Java Edition, 19132 for Bedrock/MCPE).
- `timeout`: int = DEFAULT_TIMEOUT,
  - Optional timeout in seconds for each connection attempt. Defaults to 5 seconds.
- `query_protocol`: SlpProtocols = SlpProtocols.ALL,
  - Optional protocol to use. See minestat.SlpProtocols for available choices. Defaults to auto detection.
- `resolve_srv`: Optional[bool] = None
  - Optional, whether to resolve Minecraft SRV records. Requires dnspython to be installed.


Minimal example with port auto-detection:
```python
import minestat
ms = minestat.MineStat('minecraft.frag.land')
print(f"Is online? {ms.online=}")
```

#### Available attributes
The following attributes are available on the `MineStat` object:

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
- `motd`: str
  - The raw MOTD returned by the server. May include formatting codes (§) or JSON chat components.
  - Examples (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890):
    - With formatting codes: `§6~~§r §3§lM§7§lA§2§lG§9§lI§4§lC§r1.16 v3§6~~§r`
    - JSON chat components: `{"extra": [{"color": "gold", "text": "~~"}, {"text": " "}, {"bold": true, "color": "dark_aqua", "text": "M"}, {"bold": true, "color": "gray", "text": "A"}, {"bold": true, "color": "dark_green", "text": "G"}, {"bold": true, "color": "blue", "text": "I"}, {"bold": true, "color": "dark_red", "text": "C"}, {"text": "1.16 v3"}, {"color": "gold", "text": "~~"}], "text": ""}`
- `stripped_motd`: str
  - The MOTD with all formatting removed ("human readable").
  - Example (See https://github.com/FragLand/minestat/issues/84#issuecomment-895375890)
    - Above MOTD example: `~~ MAGIC1.16 v3~~`
- `current_players`: int
  - Count of players currently online on the server.
- `max_players`: int
  - Count of maximum allowed players as reported by the server.
- `latency`: int
  - Time in milliseconds the server took to respond to the information request.
- `slp_protocol`: minestat.SlpProtocol
  - Protocol used to retrieve information from the server.
- `connection_status`: minestat.ConnStatus
  - Status of connection ("SUCCESS", "CONNFAIL", "TIMEOUT", or "UNKNOWN").
- `srv_record`: bool
  - wether the server has a SRV record.

#### Extra attributes
The following attributes are not availabe with every protocol.

- `player_list`: list[str] (***UT3/GS4 Query specific***)
  - List of online players, may be empty even if `current_players` is over 0.
- `plugins`: list[str] (***UT3/GS4 Query specific***)
  - List of plugins returned by the Query protcol.
- `map`: str (***UT3/GS4 Query specific***)
  - The name of the map the server is running on.
- `gamemode`: str (***Bedrock specific***)
  - Gamemode currently active on the server (Creative/Survival/Adventure).
- `favicon_b64`: str (***SLP 1.7/JSON specific***)
  - Base64-encoded favicon.
- `favicon`: str (***SLP 1.7/JSON specific***)
  - Decoded favicon data.
