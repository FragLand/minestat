using System;
using MineStatLib;

class Example
{
  public static void Main()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    Console.WriteLine("Minecraft server status of {0} on port {1}:", ms.Address, ms.Port);
    if(ms.ServerUp)
    {
      Console.WriteLine("Server is online running version {0} with {1} out of {2} players.",
        ms.Version, ms.CurrentPlayers, ms.MaximumPlayers);
      Console.WriteLine("Message of the day: {0}", ms.Stripped_Motd);
      Console.WriteLine("Latency: {0}ms", ms.Latency);
      Console.WriteLine("Connected using SLP protocol '{0}'", ms.Protocol.ToString());
    }
    else
      Console.WriteLine("Server is offline!");
  }
}
