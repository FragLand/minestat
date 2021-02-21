MineStat
========

[![Travis CI build status](https://img.shields.io/travis/com/FragLand/minestat?label=Travis%20CI%20build%20status)](https://travis-ci.com/FragLand/minestat)
[![CodeFactor grade](https://img.shields.io/codefactor/grade/github/FragLand/minestat?label=CodeFactor%20quality)](https://www.codefactor.io/repository/github/fragland/minestat)
[![Discord](https://img.shields.io/discord/540333638479380487?label=Discord)](https://discord.frag.land/)

MineStat is a Minecraft server status checker.

You can use these classes/modules in a monitoring script to poll multiple Minecraft servers or to let
visitors see the status of your server from their browser. MineStat has been ported to multiple languages for use with ASP.NET, FastCGI, mod_perl, mod_php, mod_python, Node.js, Rails, Tomcat, and more.

If you are planning to host MineStat on a shared webhost, make sure that the provider allows outbound sockets.

### C# example
```cs
using System;

class Example
{
  public static void Main()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    Console.WriteLine("Minecraft server status of {0} on port {1}:", ms.Address, ms.Port);
    if(ms.ServerUp)
    {
      Console.WriteLine("Server is online running version {0} with {1} out of {2} players.", ms.Version, ms.CurrentPlayers, ms.MaximumPlayers);
      Console.WriteLine("Message of the day: {0}", ms.Motd);
      Console.WriteLine("Latency: {0}ms", ms.Latency);
    }
    else
      Console.WriteLine("Server is offline!");
  }
}
```

### Go example
```go
package main

import "fmt"
import "github.com/FragLand/minestat/minestat"

func main() {
  minestat.Init("minecraft.frag.land", "25565")
  fmt.Printf("Minecraft server status of %s on port %s:\n", minestat.Address, minestat.Port)
  if minestat.Online {
    fmt.Printf("Server is online running version %s with %s out of %s players.\n", minestat.Version, minestat.Current_players, minestat.Max_players)
    fmt.Printf("Message of the day: %s\n", minestat.Motd)
    fmt.Printf("Latency: %s\n", minestat.Latency)
  } else {
    fmt.Println("Server is offline!")
  }
}
```

### Java example
```java
import land.Frag.MineStat;

class Example
{
  public static void main(String[] args)
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    System.out.println("Minecraft server status of " + ms.getAddress() + " on port " + ms.getPort() + ":");
    if(ms.isServerUp())
    {
     System.out.println("Server is online running version " + ms.getVersion() + " with " + ms.getCurrentPlayers() + " out of " + ms.getMaximumPlayers() + " players.");
     System.out.println("Message of the day: " + ms.getMotd());
     System.out.println("Latency: " + ms.getLatency() + "ms");
    }
    else
      System.out.println("Server is offline!");
  }
}
```

### JavaScript example
```javascript
// For use with Node.js
var ms = require('./minestat');
ms.init('minecraft.frag.land', 25565, function(result)
{
  console.log("Minecraft server status of " + ms.address + " on port " + ms.port + ":");
  if(ms.online)
  {
    console.log("Server is online running version " + ms.version + " with " + ms.current_players + " out of " + ms.max_players + " players.");
    console.log("Message of the day: " + ms.motd);
    console.log("Latency: " + ms.latency + "ms");
  }
  else
  {
    console.log("Server is offline!");
  }
});
```

### Perl example

[![CPAN Version](https://badge.fury.io/pl/Minecraft-ServerStatus.png)](https://badge.fury.io/pl/Minecraft-ServerStatus)

To use the CPAN module: `cpan Minecraft::ServerStatus`

```perl
use Minecraft::ServerStatus;

$ms = Minecraft::ServerStatus::init("minecraft.frag.land", 25565);

print "Minecraft server status of $ms->{address} on port $ms->{port}:\n";
if($ms->{online})
{
  print "Server is online running version $ms->{version} with $ms->{current_players} out of $ms->{max_players} players.\n";
  print "Message of the day: $ms->{motd}\n";
  print "Latency: $ms->{latency}ms\n";
}
else
{
  print "Server is offline!\n";
}
```

### PHP example

**Note:** MineStat for PHP requires multi-byte string support to handle character encoding conversion. Enabling `mbstring` support can be as simple as installing the `php-mbstring` package for your platform. If building PHP from source, see https://www.php.net/manual/en/mbstring.installation.php. To validate, `phpinfo()` output will reference `mbstring` if the feature is enabled.

```php
<?php
require_once('minestat.php');

$ms = new MineStat("minecraft.frag.land", 25565);
printf("Minecraft server status of %s on port %s:<br>", $ms->get_address(), $ms->get_port());
if($ms->is_online())
{
  printf("Server is online running version %s with %s out of %s players.<br>", $ms->get_version(), $ms->get_current_players(), $ms->get_max_players());
  printf("Message of the day: %s<br>", $ms->get_motd());
  printf("Latency: %sms<br>", $ms->get_latency());
}
else
{
  printf("Server is offline!<br>");
}
?>
```

### PowerShell example
```powershell
. .\ServerStatus.ps1

$ms = ServerStatus -Address "minecraft.frag.land" -port 25565
"Minecraft server status of {0} on port {1}:" -f $ms.address, $ms.port

if ($ms.online)
{
  "Server is online running with {0} out of {1} players." -f $ms.current_players, $ms.max_players
  "Message of the day: {0}" -f $ms.motd
  "Latency: {0}ms" -f $ms.latency
}
else
{
  "Server is offline!"
}
```

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

### Ruby example

[![Gem Version](https://badge.fury.io/rb/minestat.png)](https://badge.fury.io/rb/minestat)

To use the gem: `gem install minestat`

```ruby
require 'minestat'

ms = MineStat.new("minecraft.frag.land", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Message of the day: #{ms.motd}"
  puts "Latency: #{ms.latency}ms"
else
  puts "Server is offline!"
end
```
