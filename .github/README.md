MineStat
========

[![AppVeyor build status](https://img.shields.io/appveyor/ci/ldilley/minestat?label=AppVeyor%20build%20status)](https://ci.appveyor.com/project/ldilley/minestat)
[![CodeQL build status](https://github.com/FragLand/minestat/actions/workflows/CodeQL.yml/badge.svg?branch=master)](https://github.com/FragLand/minestat/actions/workflows/CodeQL.yml)
[![CodeFactor grade](https://img.shields.io/codefactor/grade/github/FragLand/minestat?label=CodeFactor%20quality)](https://www.codefactor.io/repository/github/fragland/minestat)

MineStat is a Minecraft server status checker.

You can use these classes/modules in a monitoring script to poll multiple Minecraft servers or to let
visitors see the status of your server from their browser. MineStat has been ported to multiple languages for use with ASP.NET, FastCGI, mod_perl, mod_php, mod_python, Node.js, Rails, Tomcat, and more.

If you are planning to host MineStat on a shared webhost, make sure that the provider allows outbound sockets.

### C# example

[![Nuget](https://img.shields.io/nuget/v/minestat?label=NuGet%20package&style=plastic)](https://www.nuget.org/packages/MineStat/)

```cs
using System;
using MineStatLib;

class Example
{
  public static void Main()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    Console.WriteLine("Minecraft server status of {0} on port {1}:", ms.Address, ms.Port);
    if(ms.ServerUp)
    {
      Console.WriteLine("Server is online running version {0} with {1} out of {2} players.", ms.Version, ms.CurrentPlayers, ms.MaximumPlayers);
      Console.WriteLine("Message of the day: {0}", ms.Stripped_Motd);
      Console.WriteLine("Latency: {0}ms", ms.Latency);
      Console.WriteLine("Connected using protocol: {0}", ms.Protocol);
    }
    else
      Console.WriteLine("Server is offline!");
  }
}
```

### Go example

[![Go Reference](https://pkg.go.dev/badge/github.com/FragLand/minestat/Go/minestat.svg)](https://pkg.go.dev/github.com/FragLand/minestat/Go/minestat)

**Note:** MineStat for Go requires UTF-16 string support to handle character encoding conversion. To install this dependency:\
`go get golang.org/x/text/encoding/unicode`

```go
package main

import "fmt"
import "github.com/FragLand/minestat/Go/minestat"

func main() {
  minestat.Init("minecraft.frag.land")
  fmt.Printf("Minecraft server status of %s on port %d:\n", minestat.Address, minestat.Port)
  if minestat.Online {
    fmt.Printf("Server is online running version %s with %d out of %d players.\n", minestat.Version, minestat.Current_players, minestat.Max_players)
    fmt.Printf("Message of the day: %s\n", minestat.Motd)
    fmt.Printf("Latency: %dms\n", minestat.Latency)
    fmt.Printf("Connected using protocol: %s\n", minestat.Protocol)
  } else {
    fmt.Println("Server is offline!")
  }
}
```

### Java example

[![Maven](https://img.shields.io/maven-central/v/io.github.fragland/MineStat?label=Maven%20package&style=plastic)](https://search.maven.org/search?q=a:MineStat)

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
     System.out.println("Message of the day without formatting: " + ms.getStrippedMotd());
     System.out.println("Latency: " + ms.getLatency() + "ms");
     System.out.println("Connected using protocol: " + ms.getRequestType());
    }
    else
      System.out.println("Server is offline!");
  }
}
```

### JavaScript example

[![npm](https://img.shields.io/npm/v/minestat?color=purple&label=npm%20package&style=plastic)](https://www.npmjs.com/package/minestat)

To use the npm package: `npm install minestat`

```javascript
var ms = require('minestat');
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

[![CPAN](https://img.shields.io/cpan/v/Minecraft-ServerStatus?color=yellow&label=CPAN%20module&style=plastic)](https://metacpan.org/release/Minecraft-ServerStatus)

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

[![Packagist Version](https://img.shields.io/packagist/v/fragland/minestat?color=orange&label=Packagist%20package&style=plastic)](https://packagist.org/packages/fragland/minestat)

**Note:** MineStat for PHP requires multi-byte string support to handle character encoding conversion. Enabling `mbstring` support can be as simple as installing the `php-mbstring` package for your platform. If building PHP from source, see https://www.php.net/manual/en/mbstring.installation.php. To validate, `phpinfo()` output will reference `mbstring` if the feature is enabled.

```php
<?php
require_once('minestat.php');

$ms = new MineStat("minecraft.frag.land", 25565);
printf("Minecraft server status of %s on port %s:<br>", $ms->get_address(), $ms->get_port());
if($ms->is_online())
{
  printf("Server is online running version %s with %s out of %s players.<br>", $ms->get_version(), $ms->get_current_players(), $ms->get_max_players());
  if($ms->get_request_type() == "Bedrock/Pocket Edition")
    printf("Game mode: %s<br>", $ms->get_mode());
  printf("Message of the day: %s<br>", $ms->get_motd());
  printf("Message of the day without formatting: %s<br>", $ms->get_stripped_motd());
  printf("Latency: %sms<br>", $ms->get_latency());
  printf("Connected using protocol: %s<br>", $ms->get_request_type());
}
else
{
  printf("Server is offline!<br>");
}
?>
```

### PowerShell example

[![Gallery](https://img.shields.io/powershellgallery/v/MineStat?color=blue&label=PowerShell%20module&style=plastic)](https://www.powershellgallery.com/packages/MineStat/)

To install the module: `Install-Module -Name MineStat`

```powershell
Import-Module MineStat
$ms = MineStat -Address "minecraft.frag.land" -port 25565
"Minecraft server status of '{0}' on port {1}:" -f $ms.Address, $ms.Port

if ($ms.Online) {
  "Server is online running version {0} with {1} out of {2} players." -f $ms.Version, $ms.Current_Players, $ms.Max_Players
  "Message of the day: {0}" -f $ms.Stripped_Motd
  "Latency: {0}ms" -f $ms.Latency
  "Connected using SLP protocol '{0}'" -f $ms.Slp_Protocol
}else {
  "Server is offline!"
}
```

### Python example

[![PyPI](https://img.shields.io/pypi/v/minestat?color=green&label=PyPI%20package&style=plastic)](https://pypi.org/project/minestat/)

To use the PyPI package: `pip install minestat`

```python
import minestat

ms = minestat.MineStat('minecraft.frag.land', 25565)
print('Minecraft server status of %s on port %d:' % (ms.address, ms.port))
if ms.online:
  print('Server is online running version %s with %s out of %s players.' % (ms.version, ms.current_players, ms.max_players))
  print('Message of the day: %s' % ms.motd)
  print('Message of the day without formatting: %s' % ms.stripped_motd)
  print('Latency: %sms' % ms.latency)
  print('Connected using protocol: %s' % ms.slp_protocol)
  # Bedrock specific attribute:
  if ms.slp_protocol is minestat.SlpProtocols.BEDROCK_RAKNET:
    print('Game mode: %s' % ms.gamemode)
else:
  print('Server is offline!')
```

**See [the Python specific readme \(Python/README.md\)](../Python/README.md) for a full list of all supported attributes.**

### Ruby example

[![Gem](https://img.shields.io/gem/v/minestat?color=red&label=Ruby%20gem&style=plastic)](https://rubygems.org/gems/minestat)

To use the gem: `gem install minestat`

```ruby
require 'minestat'

ms = MineStat.new("minecraft.frag.land", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Game mode: #{ms.mode}" if ms.request_type == "Bedrock/Pocket Edition"
  puts "Message of the day: #{ms.motd}"
  puts "Message of the day without formatting: #{ms.stripped_motd}"
  puts "Latency: #{ms.latency}ms"
  puts "Connected using protocol: #{ms.request_type}"
else
  puts "Server is offline!"
end
```
