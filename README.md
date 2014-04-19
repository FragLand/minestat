minestat
========

A Minecraft server status checker

You can use the Ruby class for a Rails application, monitoring script, etc. or the Java class
for a JSP application that lets visitors see the status of your server.

I hope to port this to PHP soon to cover most web-based needs.

Ruby example:
```ruby
require_relative 'minestat'

# Below is an example using the MineStat class.
# If server is offline, other instance members will be nil.
ms = MineStat.new("cubekingdom.net", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Message of the day: #{ms.motd}"
else
  puts "Server is offline!"
end
```

Java example:
```java
import org.devux.MineStat;

class Example
{
  public static void main(String[] args)
  {
    MineStat ms=new MineStat("cubekingdom.net", 25565);
    ms.doQuery();
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
