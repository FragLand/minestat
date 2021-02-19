MineStat
========

MineStat is a Minecraft server status checker.

You can use this module in a monitoring script to poll multiple Minecraft servers or to let visitors see the status of your server from their browser.
MineStat has been ported to multiple languages for use with ASP.NET, FastCGI, mod_perl, mod_php, mod_python, Node.js, Rails, Tomcat, and more.

If you are planning to host MineStat on a shared webhost, make sure that the provider allows outbound sockets.

### Python example

[![PyPI Version](https://badge.fury.io/py/minestat.png)](https://badge.fury.io/py/minestat)

To use the PyPI package: `pip install minestat`

```python
import minestat

ms = minestat.MineStat('minecraft.frag.land', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  print('Message of the day: %s' % ms.motd)
  print('Latency: %sms' % ms.latency)
else:
  print('Server is offline!')
```
