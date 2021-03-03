# MineStat.pm - A Minecraft server status checker
# Copyright (C) 2016-2021 Lloyd Dilley
# http://www.dilley.me/
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Minecraft::ServerStatus;

use strict;
use warnings;

use IO::Socket::INET;
use Time::HiRes qw(time);

our $VERSION = "1.0.2";   # MineStat version
our $NUM_FIELDS = 6;      # number of values expected from server
our $DEFAULT_TIMEOUT = 5; # TCP connection timeout

sub init
{
  my %data;
  if(scalar(@_) >= 3)
  {
    $data{"address"} = shift;
    $data{"port"} = shift;
    $data{"timeout"} = shift;
  }
  else
  {
    $data{"address"} = shift;
    $data{"port"} = shift;
    $data{"timeout"} = $DEFAULT_TIMEOUT;
  }
  $data{"online"} = undef;
  $data{"version"} = undef;
  $data{"motd"} = undef;
  $data{"current_players"} = undef;
  $data{"max_players"} = undef;
  $data{"latency"} = undef;

  # Connect to the server and get the data
  my $start_time = time;
  my $sock = new IO::Socket::INET(PeerHost => $data{"address"}, PeerPort => $data{"port"}, Proto => 'tcp', Timeout => $data{"timeout"});
  $data{"latency"} = (time - $start_time) * 1000;
  $data{"latency"} = int($data{"latency"} + 0.5);
  return \%data unless defined($sock);
  $sock->send("\xFE\x01");
  my $raw_data = <$sock>;
  close($sock);

  # Parse the received data
  return \%data unless defined($raw_data);
  my @mc_data = split('\x00\x00\x00', $raw_data);
  if(scalar(@mc_data) >= $NUM_FIELDS)
  {
    $data{"online"} = 1;
    $data{"version"} = $mc_data[2];
    $data{"motd"} = $mc_data[3];
    $data{"current_players"} = $mc_data[4];
    $data{"max_players"} = $mc_data[5];
  }
  return \%data;
}
1;

__END__

=head1 NAME

Minecraft::ServerStatus - A Minecraft server status checker

=head1 VERSION

Version 1.0.1

=head1 SYNOPSIS

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

=head1 DESCRIPTION

C<Minecraft::ServerStatus> provides an interface to query Minecraft servers. The data returned includes the remote server's
message of the day (MotD), current players, maximum players, version, and latency.

=head1 INSTALLATION

To install this module:

    perl Makefile.PL
    make
    make install
            
=head1 FUNCTIONS

=head2 init

    Minecraft::ServerStatus::init("minecraft.frag.land", 25565);

The above function connects to the specified Minecraft server using the address and port. You may also specify the TCP timeout:

    Minecraft::ServerStatus::init("minecraft.frag.land", 25565, 3);

The default TCP timeout value is 5 seconds.

=head1 SUPPORT

=over 4

=item Source code: L<https://github.com/FragLand/minestat>

=item Bug reports and feature requests: L<https://github.com/FragLand/minestat/issues>

=back

=head1 DEPENDENCIES

=over 4

=item L<IO::Socket::INET>

=item L<Time::HiRes>

=back

=head1 AUTHOR

=over 4

=item B<Lloyd Dilley> C<E<lt>ldilley@cpan.orgE<gt>>

=back

=head1 LICENSE

Copyright (C) 2016-2021 Lloyd Dilley

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
