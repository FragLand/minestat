minestat
========

A Minecraft server status checker

You can use these classes in a monitoring script to poll multiple Minecraft servers or to let
visitors see the status of your server from their browser.

C# example:
```cs
using System;

class Example
{
  public static void Main()
  {
    MineStat ms = new MineStat("cubekingdom.net", 25565);
    Console.WriteLine("Minecraft server status of {0} on port {1}:", ms.GetAddress(), ms.GetPort());
    if(ms.IsServerUp())
    {
      Console.WriteLine("Server is online running version {0} with {1} out of {2} players.", ms.GetVersion(), ms.GetCurrentPlayers(), ms.GetMaximumPlayers());
      Console.WriteLine("Message of the day: {0}", ms.GetMotd());
    }
    else
      Console.WriteLine("Server is offline!");
  }
}
```

Java example:
```java
import org.devux.MineStat;

class Example
{
  public static void main(String[] args)
  {
    MineStat ms = new MineStat("cubekingdom.net", 25565);
    System.out.println("Minecraft server status of " + ms.getAddress() + " on port " + ms.getPort() + ":");
    if(ms.isServerUp())
    {
     System.out.println("Server is online running version " + ms.getVersion() + " with " + ms.getCurrentPlayers() + " out of " + ms.getMaximumPlayers() + " players.");
     System.out.println("Message of the day: " + ms.getMotd());
    }
    else
      System.out.println("Server is offline!");
  }
}
```

PHP example:
```php
<?php
require_once('minestat.php');

$ms = new MineStat("cubekingdom.net", 25565);
printf("Minecraft server status of %s on port %s:<br>", $ms->get_address(), $ms->get_port());
if($ms->is_online())
{
  printf("Server is online running version %s with %s out of %s players.<br>", $ms->get_version(), $ms->get_current_players(), $ms->get_max_players());
  printf("Message of the day: %s<br>", $ms->get_motd());
}
else
{
  printf("Server is offline!<br>");
}
?>
```

Python example:
```python
import minestat

ms = minestat.MineStat('minecraft.dilley.me', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  print('Message of the day: %s' % ms.motd)
else:
  print('Server is offline!')
```

Ruby example:
```ruby
require_relative 'minestat'

ms = MineStat.new("cubekingdom.net", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Message of the day: #{ms.motd}"
else
  puts "Server is offline!"
end
```
