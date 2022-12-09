# MineStat.pm - A Minecraft server status checker
# Copyright (C) 2016-2022 Lloyd Dilley
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

our $VERSION = "1.0.2";        # MineStat version
our $NUM_FIELDS = 6;           # number of values expected from server
our $NUM_FIELDS_BETA = 3;      # number of values expected from a 1.8b/1.3 server
our $DEFAULT_TCP_PORT = 25565; # default TCP port
our $DEFAULT_TIMEOUT = 5;      # TCP connection timeout

use constant
{
  RETURN_SUCCESS => "Success", # connection was successful and the response data was parsed without problems
  RETURN_CONNFAIL => "Fail",   # connection failed due to an unknown hostname or incorrect port number
  RETURN_TIMEOUT => "Timeout", # connection timed out -- either the server is overloaded or it dropped our packets
  RETURN_UNKNOWN => "Unknown"  # connection was successful, but the response data could not be properly parsed
};

use constant
{
  REQUEST_NONE => -1,    # try everything
  REQUEST_BETA => 0,     # server versions 1.8b to 1.3
  REQUEST_LEGACY => 1,   # server versions 1.4 to 1.5
  REQUEST_EXTENDED => 2, # server version 1.6
  REQUEST_JSON => 3,     # server versions 1.7 to latest
  REQUEST_BEDROCK => 4   # Bedrock/Pocket Edition
};

sub init
{
  my %data;
  my $retval;  # return value
  my $try_all; # try all protocols if request type is REQUEST_NONE

  if(scalar(@_) >= 4)
  {
    $data{address} = shift;
    $data{port} = shift;
    $data{timeout} = shift;
    $data{request_type} = shift;
  }
  elsif(scalar(@_) == 3)
  {
    $data{address} = shift;
    $data{port} = shift;
    $data{timeout} = shift;
    $data{request_type} = REQUEST_NONE;
  }
  elsif(scalar(@_) == 2)
  {
    $data{address} = shift;
    $data{port} = shift;
    $data{timeout} = $DEFAULT_TIMEOUT;
    $data{request_type} = REQUEST_NONE;
  }
  else
  {
    $data{address} = shift;
    $data{port} = $DEFAULT_TCP_PORT;
    $data{timeout} = $DEFAULT_TIMEOUT;
    $data{request_type} = REQUEST_NONE;
  }
  $data{sock} = undef;
  $data{online} = undef;
  $data{version} = undef;
  $data{motd} = undef;
  $data{current_players} = undef;
  $data{max_players} = undef;
  $data{protocol} = undef;
  $data{latency} = undef;
  $data{connection_status} = undef;
  if($data{request_type} == REQUEST_NONE) { $try_all = 1; }

  if($data{request_type} == REQUEST_BETA) { $retval = beta_request(\%data); }
  elsif($data{request_type} == REQUEST_LEGACY) { $retval = legacy_request(\%data); }
  elsif($data{request_type} == REQUEST_EXTENDED) { $retval = extended_request(\%data); }
  elsif($data{request_type} == REQUEST_JSON) { $retval = json_request(\%data); }
  elsif($data{request_type} == REQUEST_BEDROCK) { $retval = bedrock_request(\%data); }
  else
  {
    $retval = legacy_request(\%data);                                                               # SLP 1.4/1.5
    if($retval ne RETURN_SUCCESS && $retval ne RETURN_CONNFAIL) { $retval = beta_request(\%data); } # SLP 1.8b/1.3
    #if($retval ne RETURN_CONNFAIL) { $retval = extended_request(\%data); }                         # SLP 1.6
    #if($retval ne RETURN_CONNFAIL) { $retval = json_request(\%data); }                             # SLP 1.7
    #if(!$data{online}) { $retval = bedrock_request(\%data); }                                      # Bedrock/Pocket Edition
  }

  if($data{online}) { set_connection_status(RETURN_SUCCESS, $data{connection_status}); }
  else { set_connection_status($retval, $data{connection_status}); }

  return \%data;
}

# Sets connection status
sub set_connection_status
{
  my $retval = shift;
  my $connection_status = shift;

  if($retval ne RETURN_SUCCESS) { $connection_status = "Success"; }
  elsif($retval ne RETURN_CONNFAIL) { $connection_status = "Fail"; }
  elsif($retval ne RETURN_TIMEOUT) { $connection_status = "Timeout"; }
  elsif($retval ne RETURN UNKNOWN) { $connection_status = "Unknown"; }
  else { $connection_status = "Unknown"; }
}

# Connect to the server and get the data
sub connect_server
{
  my $data = shift;
  my $start_time = time;

  if($data->{request_type} eq REQUEST_BEDROCK)
  {
    $data->{sock} = new IO::Socket::INET(PeerHost => $data->{address}, PeerPort => $data->{port}, Proto => 'udp', Timeout => $data->{timeout});
  }
  else
  {
    $data->{sock} = new IO::Socket::INET(PeerHost => $data->{address}, PeerPort => $data->{port}, Proto => 'tcp', Timeout => $data->{timeout});
  }
  $data->{latency} = (time - $start_time) * 1000;
  $data->{latency} = int($data->{latency} + 0.5);
  if(!defined($data->{sock})) { return RETURN_CONNFAIL; }
  else { return RETURN_SUCCESS; }
}

# Parse the received data
sub parse_data
{
  my $data;
  my $delimiter;
  my $is_beta;
  my $raw_data;
  my $data_length;
  my @mc_data;

  if(scalar(@_) >= 3)
  {
    $data = shift;
    $delimiter = shift;
    $is_beta = shift;
  }
  else
  {
    $data = shift;
    $delimiter = shift;
    $is_beta = 0;
  }

  $data->{sock}->recv($raw_data, 1);
  $raw_data = unpack("C", $raw_data);
  if($raw_data != 255) { return RETURN_UNKNOWN; } # not the expected kick packet (0xFF)
  $data->{sock}->recv($raw_data, 2);
  $data_length = unpack("n", $raw_data);
  $data->{sock}->recv($raw_data, $data_length * 2);
  close($data->{sock});
  if(!defined($raw_data)) { return RETURN_UNKNOWN; } # not the expected data
  @mc_data = split($delimiter, $raw_data);

  if($is_beta)
  {
    if(scalar(@mc_data) >= $NUM_FIELDS_BETA)
    {
      $data->{online} = 1;
      $data->{version} = ">=1.8b/1.3";
      $data->{motd} = $mc_data[0];
      $data->{current_players} = $mc_data[1];
      $data->{max_players} = $mc_data[2];
    }
    else { return RETURN_UNKNOWN; }
  }
  else
  {
    if(scalar(@mc_data) >= $NUM_FIELDS)
    {
      $data->{online} = 1;
      $data->{protocol} = $mc_data[1]; # contains the protocol version (51 for 1.9 or 78 for 1.6.4 for example)
      $data->{version} = $mc_data[2];
      $data->{motd} = $mc_data[3];
      $data->{current_players} = $mc_data[4];
      $data->{max_players} = $mc_data[5];
    }
    else { return RETURN_UNKNOWN; }
  }

  return RETURN_SUCCESS;
}

# 1.8b/1.3
# 1.8 beta through 1.3 servers communicate as follows for a ping request:
# 1. Client sends \xFE (server list ping)
# 2. Server responds with:
#   2a. \xFF (kick packet)
#   2b. data length
#   2c. 3 fields delimited by \u00A7 (section symbol)
# The 3 fields, in order, are: message of the day, current players, and max players
sub beta_request
{
  my $data = shift;
  my $retval = connect_server($data);
  if($retval ne RETURN_SUCCESS) { return $retval; }
  # Start the handshake and attempt to acquire data
  $data->{sock}->send("\xFE");
  $retval = parse_data($data, "\xA7", 1);
  #$retval = parse_data($data, "§", 1);
  if($retval eq RETURN_SUCCESS) { $data->{request_type} = "SLP 1.8b/1.3 (beta)"; }
  return $retval;
}

# 1.4/1.5
# 1.4 and 1.5 servers communicate as follows for a ping request:
# 1. Client sends:
#   1a. \xFE (server list ping)
#   1b. \x01 (server list ping payload)
# 2. Server responds with:
#   2a. \xFF (kick packet)
#   2b. data length
#   2c. 6 fields delimited by \x00 (null)
# The 6 fields, in order, are: the section symbol and 1, protocol version,
# server version, message of the day, current players, and max players.
# The protocol version corresponds with the server version and can be the
# same for different server versions.
sub legacy_request
{
  my $data = shift;
  my $retval = connect_server($data);
  if($retval ne RETURN_SUCCESS) { return $retval; }
  # Start the handshake and attempt to acquire data
  $data->{sock}->send("\xFE\x01");
  $retval = parse_data($data, "\x00\x00\x00");
  if($retval eq RETURN_SUCCESS) { $data->{request_type} = "SLP 1.4/1.5 (legacy)"; }
  return $retval;
}

# ToDo: Implement me.
sub extended_request
{
  #my $data = shift;
  #my $retval = connect_server($data);
}

# ToDo: Implement me.
sub json_request
{
  #my $data = shift;
  #my $retval = connect_server($data);
}

# ToDo: Implement me.
sub bedrock_request
{
  #my $data = shift;
  #my $retval = connect_server($data);
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
