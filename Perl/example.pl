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
