MineStat
========

MineStat is a Minecraft server status checker.

Exposes two methods:

#### `ìnit`
- Fetches the server status asynchronously, with an optional timeout 
```typescript
init(address: string, port: number): Promise<Stats>;
init(address: string, port: number, timeout: number): Promise<Stats>;
```

#### `ìnitSync`
- Synchronously fetches the server status, using a callback, with an optional timeout 
```typescript
initSync(address: string, port: number, callback: (error?: Error, result: Stats) => void): void;
init(address: string, port: number, timeout: number, callback: (error?: Error, result: Stats) => void): void;
```

Returns a `Stats` object. For offline server statuses:
```typescript
{
  address: string; // The original address you provided
  port: number; // The original port you provided
  latency: number; // Ping to server in ms
  offline: false;
}
```

For online servers:
```typescript
{
  address: string;
  port: number;
  latency: number;
  online: true;
  version: string;
  max_players: number;
  current_players: number;
  motd: string; // Message of the day
}
```

### JavaScript async example
```javascript
const ms = require('minestat');
(async () => {
  try
  {
    const result = await ms.init({address: 'minecraft.frag.land', port: 25565});
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
  }
  catch(error)
  {
    throw error;
  }
})();
```

### JavaScript synchronous example
```javascript
var ms = require('minestat');
ms.initSync({address: 'minecraft.frag.land', port: 25565}, function(result)
{
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
```
