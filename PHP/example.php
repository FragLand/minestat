<?php
require_once('minestat.php');

$ms = new MineStat("minecraft.frag.land");
printf("Minecraft server status of %s on port %s:<br>", $ms->get_address(), $ms->get_port());
if($ms->is_online())
{
  printf("Server is online running version %s with %s out of %s players.<br>", $ms->get_version(), $ms->get_current_players(), $ms->get_max_players());
  printf("Message of the day: %s<br>", $ms->get_motd());
  printf("Latency: %sms<br>", $ms->get_latency());
}
else
{
  printf("Server is offline!<br>");
}
?>
