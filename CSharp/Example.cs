using System;
using MineStatLib;

class Example
{
  public static void Main()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    Console.WriteLine("Minecraft server status of {0} on port {1}:", ms.GetAddress(), ms.GetPort());
    if(ms.IsServerUp())
    {
      Console.WriteLine("Server is online running version {0} with {1} out of {2} players.", ms.GetVersion(), ms.GetCurrentPlayers(), ms.GetMaximumPlayers());
      Console.WriteLine("Message of the day: {0}", ms.GetMotd());
      Console.WriteLine("Latency: {0}ms", ms.GetLatency());
    }
    else
      Console.WriteLine("Server is offline!");
  }
}
