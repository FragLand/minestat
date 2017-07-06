// For use with Node.js
var ms = require('./minestat');
ms.init('minecraft.frag.land', 25565, function(result)
{
  console.log("Minecraft server status of " + ms.address + " on port " + ms.port + ":");
  if(ms.online)
  {
    console.log("Server is online running version " + ms.version + " with " + ms.current_players + " out of " + ms.max_players + " players.");
    console.log("Message of the day: " + ms.motd);
  }
  else
  {
    console.log("Server is offline!");
  }
});
