MineStat :chart_with_upwards_trend:
========

[![AppVeyor build status](https://img.shields.io/appveyor/ci/ldilley/minestat?label=AppVeyor%20build%20status)](https://ci.appveyor.com/project/ldilley/minestat)
[![CodeQL build status](https://github.com/FragLand/minestat/actions/workflows/CodeQL.yml/badge.svg?branch=master)](https://github.com/FragLand/minestat/actions/workflows/CodeQL.yml)
[![CodeFactor grade](https://img.shields.io/codefactor/grade/github/FragLand/minestat?label=CodeFactor%20quality)](https://www.codefactor.io/repository/github/fragland/minestat)
[![Matrix](https://img.shields.io/matrix/fragland%3Amatrix.org?label=Matrix)](https://matrix.frag.land/)

MineStat is a Minecraft server status checker.

You can use these classes/modules in a monitoring script to poll multiple Minecraft servers, include similar functionality in a Discord bot, or to let
visitors see the status of your server from their browser. MineStat has been ported to multiple languages for use with ASP.NET, FastCGI, mod_perl, mod_php, mod_python, Node.js, Rails, Tomcat, and more.

If you are planning to host MineStat on a shared webhost, make sure that the provider allows outbound sockets.

## Protocol Support :telephone_receiver:
**Note:** The Go, JavaScript, and Perl implementations are currently under development.

|Protocol|C#|Go|Java|JavaScript|Perl|PHP|PowerShell|Python|Ruby|
|-|--|--|----|----------|----|---|------|----|--|
|**1.8b/1.3 (beta)**|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:x:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|
|**1.4/1.5 (legacy)**|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|
|**1.6 (extended legacy)**|:heavy_check_mark:|:x:|:heavy_check_mark:|:x:|:x:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|
|**>=1.7 (JSON)**|:heavy_check_mark:|:x:|:heavy_check_mark:|:x:|:x:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|
|**Bedrock/PE/RakNet**|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:x:|:x:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|
|**UT3/GS4 Query**|:x:|:x:|:x:|:x:|:x:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|:heavy_check_mark:|

## Examples :memo:

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
      if(ms.Gamemode != null)
        Console.WriteLine("Game mode: {0}", ms.Gamemode);
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

To use the Go package: `go get github.com/FragLand/minestat/Go/minestat`

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
  # Bedrock specific attribute:
  if ms.gamemode:
    print('Game mode: %s' % ms.gamemode)
  print('Message of the day: %s' % ms.motd)
  print('Message of the day without formatting: %s' % ms.stripped_motd)
  print('Latency: %sms' % ms.latency)
  print('Connected using protocol: %s' % ms.slp_protocol)
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
  puts "Game mode: #{ms.mode}" if ms.mode
  puts "Message of the day: #{ms.motd}"
  puts "Message of the day without formatting: #{ms.stripped_motd}"
  puts "Latency: #{ms.latency}ms"
  puts "Connected using protocol: #{ms.request_type}"
else
  puts "Server is offline!"
end
```

## Contributing and Support :octocat:
Feel free to [submit an issue](https://github.com/FragLand/minestat/issues/new/choose) if you require assistance or would like to make a feature request. You are also welcome to [join us on Matrix](https://matrix.frag.land/). Any contributions such as build testing, creating bug reports or feature requests, and submitting pull requests are appreciated. Our code style guidelines can be found in the "Coding Convention" section of [CONTRIBUTING.md](https://github.com/FragLand/minestat/blob/master/.github/CONTRIBUTING.md). Please see the [fork and pull guide](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork) if you are not certain how to submit a pull request.

## Contributors
* [**@Ajoro**](https://github.com/ajoro): C#, PowerShell, and GitHub Actions/automation [_2020 - present_]
* **Annukka Törmälä** ([**@nukka**](https://github.com/nukka)): Java [_2017_]
* **Arne Sacnussem** ([**@arnesacnussem**](https://github.com/arnesacnussem)): Java [_2018_]
* [**@BlueTree242**](https://github.com/BlueTree242): Java issue report [_2021_]
* [**@braulio-dev**](https://github.com/braulio-dev): Feature request [_2021_]
* [**@c0m4r**](https://github.com/c0m4r): PHP [_2020_]
* [**@Chew**](https://github.com/Chew): Ruby issue report [_2020_]
* [**@Conanap**](https://github.com/Conanap): JavaScript issue report [_2022_]
* [**@DeadlineEm**](https://github.com/Deadlineem): PHP and PowerShell [_2023_]
* **Felix Ern** ([**@MindSolve**](https://github.com/mindsolve)): C#, Java, PHP, Python, and GitHub Actions/automation [_2019 - present_]
* [**@grimsi**](https://github.com/grimsi): Java issue report [_2020, 2021_]
* **Hojeong Go** ([**@seia-soto**](https://github.com/seia-soto)): JavaScript [_2018_]
* **Isaac Kogan** ([**@isaackogan**](https://github.com/isaackogan)): Feature request [_2021_]
* [**@ItsVinnyX**](https://github.com/ItsVinnyX): Java issue report [_2018, 2020_]
* [**@Jcodeerd**](https://github.com/Jcodeerd): Python issue report [_2021_]
* [**@Joly0**](https://github.com/Joly0): Java issue report [_2021_]
* [**@Jordan9232**](https://github.com/Jordan9232): Feature request [_2023_]
* [**@jrdiver**](https://github.com/jrdiver): C# [_2022_]
* [**@Junai22**](https://github.com/Junai22): Python issue report [_2021_]
* **Kolya Venturi** ([**@kolyaventuri**](https://github.com/kolyaventuri)): JavaScript [_2023_]
* [**@KyleighD**](https://github.com/kyleighd): Ideas and code review [_2014 - 2020_]
* **Lewis L. Foster** ([**@sniff122**](https://github.com/sniff122)): Python issue report [_2018_]
* **Lloyd Dilley** ([**@ldilley**](https://github.com/ldilley)): Lead developer [_2014 - present_]
* **Lukas Kolletzki** ([**@kolletzki**](https://github.com/kolletzki)): C# [_2017_]
* **Marko Pilipovicc** ([**@marko-pilipovicc**](https://github.com/marko-pilipovicc)): Java issue report [_2020_]
* [**@matahombres**](https://github.com/matahombres): PHP issue report [_2019_]
* [**@MegaNarwhal**](https://github.com/MegaNarwhal): Java issue report [_2017_]
* [**@mio9**](https://github.com/mio9): JavaScript issue report [_2017_]
* [**@molanp**](https://github.com/molanp): PHP and Python [_2023 - present_]
* **Nate Bendall** ([**@nbendall34**](https://github.com/nbendall34)): Java issue report [_2021_]
* [**@Nortank12**](https://github.com/Nortank12): Python issue report [_2019_]
* [**@Norway174**](https://github.com/Norway174): JavaScript issue report [_2017_]
* [**@Osiris-Team**](https://github.com/Osiris-Team): Java issue report [_2021_]
* **Ozan Kurt** ([**@OzanKurt**](https://github.com/OzanKurt)): PHP issue report [_2019_]
* **Pavel Fedin** ([**@amorphine**](https://github.com/amorphine)): Go and JavaScript issue report [_2018_]
* **Phil Rimer**: IRC server hosting [_2014 - 2020_]
* [**@Pronner**](https://github.com/Pronner): C# issue report [_2022_]
* [**@Raideerke**](https://github.com/Raideerke): Go and JavaScript issue report [_2019_]
* **Rawora Ramin** ([**@rawora-rg**](https://github.com/rawora-rg)): Java issue report [_2020_]
* [**@RealDrPuc**](https://github.com/RealDrPuc): Python issue report [_2020_]
* [**@rey-dev**](https://github.com/rey-dev): Feature request [_2021_]
* [**@RunTheBot**](https://github.com/RunTheBot): JavaScript [_2023_]
* [**@samdotnet**](https://github.com/samdotnet): Java issue report [_2020_]
* [**@Sch8ill**](https://github.com/sch8ill): Go and Python [_2022 - present_]
* **SeongHoon Ryu** ([**@ryush00**](https://github.com/ryush00)): Ruby [_2024_]
* [**@sinhpn92**](https://github.com/sinhpn92): Go and JavaScript issue report [_2020_]
* [**@skybird23333**](https://github.com/skybird23333): Java issue report [_2020_]
* **Sondre Batalden** ([**@Pomdre**](https://github.com/Pomdre)): PHP issue report [_2019_]
* [**@Spongecade**](https://github.com/Spongecade): Python documentation [_2023_]
* **Stepan Melnikov** ([**@unn4m3d**](https://github.com/unn4m3d)): Ruby [_2016_]
* **Steven Polglase** ([**@swpolgla**](https://github.com/swpolgla)): Ruby [_2021_]
* [**@TENIOS**](https://github.com/TENIOS): Java [_2024_]
* **ThisTNTSquid**: JavaScript [_2017_]
* **Tony Publiski** ([**@Tonster**](https://github.com/tonster)): Minecraft and IRC server hosting [_2014 - present_]
* **Vikas Dongre** ([**@zvikasdongre**](https://github.com/zvikasdongre)): Java issue report [_2022_]
* **wangyw15**: C# [_2017_]
* [**@xXBuilderBXx**](https://github.com/xXBuilderBXx): C# issue report [_2017_] 
