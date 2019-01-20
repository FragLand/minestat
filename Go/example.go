package main

import "fmt"
import "github.com/ldilley/minestat/Go/minestat"

func main() {
  minestat.Init("minecraft.dilley.me", "25565")
  fmt.Printf("Minecraft server status of %s on port %s:\n", minestat.Address, minestat.Port)
  if minestat.Online {
    fmt.Printf("Server is online running version %s with %s out of %s players.\n", minestat.Version, minestat.Current_players, minestat.Max_players)
    fmt.Printf("Message of the day: %s\n", minestat.Motd)
  } else {
    fmt.Println("Server is offline!")
  }
}
