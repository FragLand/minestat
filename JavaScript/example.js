// Synchronous example (see example-async.js or example-async.mjs for asynchronous examples)
var ms = require('minestat');
ms.initSync({address: 'minecraft.frag.land', port: 25565}, function(error, result)
{
  if(error)
  {
    console.log('Error encountered during connection attempt.');
    throw error;
  }

  console.log("Minecraft server status of " + result.address + " on port " + result.port + ":");
  if(result.online)
  {
    console.log("Server is online running version " + result.version + " with " + result.current_players + " out of " + result.max_players + " players.");
    console.log("Message of the day: " + result.motd);
    console.log("Latency: " + result.latency + "ms");
  }
  else
  {
    console.log("Server is offline!");
  }
});
