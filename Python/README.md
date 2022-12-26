MineStat
========

MineStat is a Minecraft server status checker.

### Python example

[![PyPI](https://img.shields.io/pypi/v/minestat?color=green&label=PyPI%20package&style=plastic)](https://pypi.org/project/minestat/)

To use the PyPI package: `pip install minestat`

```python
import minestat

ms = minestat.MineStat('minecraft.frag.land', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  print('Message of the day: %s' % ms.motd)
  print('Message of the day without formatting: %s' % ms.stripped_motd)
  print('Latency: %sms' % ms.latency)
  print('Connected using protocol: %s' % ms.slp_protocol)
  # Bedrock specific attribute:
  if ms.slp_protocol is minestat.SlpProtocols.BEDROCK_RAKNET:
    print('Game mode: %s' % ms.gamemode)
else:
  print('Server is offline!')
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
- `gamemode`: str (***Bedrock specific***)
  - Gamemode currently active on the server (Creative/Survival/Adventure). None if the server is not a Bedrock server.
- `favicon_b64`: str
  - Base64-encoded favicon possibly contained in JSON 1.7 responses.
- `favicon`: str
  - Base64-decoded favicon data.
- `connection_status`: minestat.ConnStatus
  - Status of connection ("SUCCESS", "CONNFAIL", "TIMEOUT", or "UNKNOWN").
