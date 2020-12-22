. .\ServerStatus.ps1

$ms = ServerStatus -Address "minecraft.frag.land" -port 25565
"Minecraft server status of {0} on port {1}:" -f $ms.address, $ms.port

if ($ms.online) {
  "Server is online running with {0} out of {1} players." -f $ms.current_players, $ms.max_players
  "Message of the day: {0}" -f $ms.motd
  "Latency: {0}ms" -f $ms.latency
}else {
  "Server is offline!"
}
