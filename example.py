import minestat

# Below is an example using the MineStat class.
# If server is offline, other instance members will be None.
ms = minestat.MineStat('minecraft.dilley.me', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  print('Message of the day: %s' % ms.motd)
else:
  print('Server is offline!')
