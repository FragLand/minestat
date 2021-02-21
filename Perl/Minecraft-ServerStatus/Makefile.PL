use strict;
use warnings;
use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile
(
  NAME             => "Minecraft::ServerStatus",
  AUTHOR           => [q{Lloyd Dilley <ldilley@cpan.org>}],
  LICENSE          => "gpl_3",
  ABSTRACT         => "A Minecraft server status checker",
  VERSION_FROM     => "lib/Minecraft/ServerStatus.pm",
  MIN_PERL_VERSION => "5.010",
  PREREQ_PM        => { "IO::Socket::INET" => 0,
                        'Time::HiRes'      => 0 },
  META_MERGE       => {
                        resources => {
                                       "meta-spec" => { version => 2 },
                                       repository  => "https://github.com/FragLand/minestat.git",
                                       bugtracker  => "https://github.com/FragLand/minestat/issues",
                                       web         => "https://github.com/FragLand/minestat",
                                     },
                      },
);
