MineStat
========

### About

MineStat is a Minecraft server status checker.

You can use these classes/modules in a monitoring script to poll multiple Minecraft servers, include similar functionality in a Discord bot, or to let
visitors see the status of your server from their browser. MineStat has been ported to multiple languages for use with ASP.NET, FastCGI, mod_perl,
mod_php, mod_python, Node.js, Rails, Tomcat, and more.

### Installation

To install the gem: `gem install minestat`

### Example

```ruby
require 'minestat'

ms = MineStat.new("minecraft.frag.land", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Game mode: #{ms.mode}" if ms.mode
  puts "Message of the day: #{ms.motd}"
  puts "Message of the day without formatting: #{ms.stripped_motd}"
  puts "Latency: #{ms.latency}ms"
  puts "Connected using protocol: #{ms.request_type}"
else
  puts "Server is offline!"
end
```

### Constructor Arguments

To simply connect to an address:
```ruby
ms = MineStat.new("minecraft.frag.land")
```
Connect to an address on a certain TCP or UDP port:
```ruby
ms = MineStat.new("minecraft.frag.land", 25567)
```
Same as above example and additionally includes a timeout in seconds:
```ruby
ms = MineStat.new("minecraft.frag.land", 25567, 3)
```
Same as above example and additionally includes an explicit protocol to use:
```ruby
ms = MineStat.new("minecraft.frag.land", 25567, 3, MineStat::Request::QUERY)
```
Connect to a Bedrock server and enable debug mode:
```ruby
ms = MineStat.new("minecraft.frag.land", 19132, 3, MineStat::Request::BEDROCK, true)
```

### Support
* Discord: https://discord.frag.land
* GitHub: https://github.com/FragLand/minestat
