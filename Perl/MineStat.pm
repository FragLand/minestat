# MineStat.pm - A Minecraft server status checker
# Copyright (C) 2016 Lloyd Dilley
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

package MineStat;

use strict;
use warnings;

use IO::Socket::INET;
use Time::HiRes qw(time);

our $NUM_FIELDS = 6;          # number of values expected from server
our $address = undef;
our $port = undef;
our $online = undef;          # online or offline?
our $version = undef;         # server version
our $motd = undef;            # message of the day
our $current_players = undef; # current number of players online
our $max_players = undef;     # maximum player capacity
our $latency = undef;         # ping time to server in milliseconds
our $timeout = 5;             # TCP connection timeout

sub init
{
  if(scalar(@_) >= 3)
  {
    $address = shift;
    $port = shift;
    $timeout = shift;
  }
  else
  {
    $address = shift;
    $port = shift;
  }

  # Connect to the server and get the data
  my $start_time = time;
  my $sock = new IO::Socket::INET(PeerHost => $address, PeerPort => $port, Proto => 'tcp', Timeout => $timeout);
  $latency = (time - $start_time) * 1000;
  $latency = int($latency + 0.5);
  return unless defined($sock);
  $sock->send("\xFE\x01");
  my $raw_data = <$sock>;
  close($sock);

  # Parse the received data
  return unless defined($raw_data);
  my @data = split('\x00\x00\x00', $raw_data);
  if(scalar(@data) >= $NUM_FIELDS)
  {
    $online = 1;
    $version = $data[2];
    $motd = $data[3];
    $current_players = $data[4];
    $max_players = $data[5];
  }
}
1;
