require 'minestat'

# Below is an example using the MineStat class.
# If server is offline, other instance members will be nil.
ms = MineStat.new("minecraft.frag.land")
# Bedrock/Pocket Edition explicit query example
#ms = MineStat.new("minecraft.frag.land", 19132, 5, MineStat::Request::BEDROCK)
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
