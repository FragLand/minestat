package main

import "fmt"
import "github.com/ldilley/minestat/Go/minestat"

func main() {
  minestat.Init("minecraft.dilley.me", "25565")
  fmt.Printf("Minecraft server status of %s on port %s:\n", minestat.Address, minestat.Port)
  if minestat.Online {
    fmt.Printf("Server is online running version %s with %s out of %s players.\n", minestat.Version, minestat.Current_players, minestat.Max_players)
    fmt.Printf("Message of the day: %s\n", minestat.Motd)
    /* Latency may report a misleading value of >1s due to name resolution delay when using net.Dial().
       A workaround for this issue is to use an IP address instead of a hostname or FQDN. */
    fmt.Printf("Latency: %s\n", minestat.Latency)
  } else {
    fmt.Println("Server is offline!")
  }
}
