package main

import "fmt"
import "github.com/FragLand/minestat/Go/minestat"

func main() {
  minestat.Init("minecraft.frag.land")
  fmt.Printf("Minecraft server status of %s on port %d:\n", minestat.Address, minestat.Port)
  if minestat.Online {
    fmt.Printf("Server is online running version %s with %d out of %d players.\n", minestat.Version, minestat.Current_players, minestat.Max_players)
    fmt.Printf("Message of the day: %s\n", minestat.Motd)
    fmt.Printf("Latency: %dms\n", minestat.Latency)
    fmt.Printf("Connected using protocol: %s\n", minestat.Protocol)
  } else {
    fmt.Println("Server is offline!")
  }
}
