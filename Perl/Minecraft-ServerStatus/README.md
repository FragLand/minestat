# NAME

Minecraft::ServerStatus - A Minecraft server status checker

# VERSION

Version 1.1.0

# SYNOPSIS

```perl
  use Minecraft::ServerStatus;

  $ms = Minecraft::ServerStatus::init("minecraft.frag.land");

  print "Minecraft server status of $ms->{address} on port $ms->{port}:\n";
  if($ms->{online})
  {
    print "Server is online running version $ms->{version} with $ms->{current_players} out of $ms->{max_players} players.\n";
    print "Message of the day: $ms->{motd}\n";
    print "Latency: $ms->{latency}ms\n";
    print "Connected using protocol: $ms->{request_type}\n";
  }
  else
  {
    print "Server is offline!\n";
  }
```

# DESCRIPTION

`Minecraft::ServerStatus` provides an interface to query Minecraft servers. The data returned includes the remote server's
message of the day (MotD), current players, maximum players, version, and latency.

# INSTALLATION

To install this module:

```
  perl Makefile.PL
  make
  make install         
```

# FUNCTIONS

## init

```perl
  Minecraft::ServerStatus::init("minecraft.frag.land", 25565);
```

The above function connects to the specified Minecraft server using an address and port. If the port number is omitted, the
default port, 25565, is used. You may also specify the TCP timeout:

```perl
  Minecraft::ServerStatus::init("minecraft.frag.land", 25565, 3);
```

The default TCP timeout value is 5 seconds.

# SUPPORT

* [Source code](https://github.com/FragLand/minestat)
* [Bug reports and feature requests](https://github.com/FragLand/minestat/issues)

# DEPENDENCIES

* `IO::Socket::INET`
* `Time::HiRes`

# AUTHOR

**Lloyd Dilley** `<ldilley@cpan.org>`

# LICENSE

Copyright (C) 2016-2022 Lloyd Dilley

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
