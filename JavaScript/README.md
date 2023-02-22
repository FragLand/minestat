MineStat
========

MineStat is a Minecraft server status checker.

### JavaScript example
```javascript
var ms = require('minestat');
ms.init('minecraft.frag.land', 25565, function(result)
{
  console.log("Minecraft server status of " + result.address + " on port " + result.port + ":");
  if(result.online)
  {
    console.log("Server is online running version " + result.version + " with " + result.current_players + " out of " + result.max_players + " players.");
    console.log("Message of the day: " + result.motd);
    console.log("Latency: " + result.latency + "result");
  }
  else
  {
    console.log("Server is offline!");
  }
});

```
