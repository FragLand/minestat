require 'minestat'

# Below is an example using the MineStat class.
# If server is offline, other instance members will be nil.
ms = MineStat.new("minecraft.dilley.me", 25565)
puts "Minecraft server status of #{ms.address} on port #{ms.port}:"
if ms.online
  puts "Server is online running version #{ms.version} with #{ms.current_players} out of #{ms.max_players} players."
  puts "Message of the day: #{ms.motd}"
else
  puts "Server is offline!"
end
