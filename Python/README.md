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
  print('Latency: %sms' % ms.latency)
  print('Connected using protocol: %s' % ms.slp_protocol)
else:
  print('Server is offline!')
```
