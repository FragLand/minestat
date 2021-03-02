import me.dilley.MineStat;

class Example
{
  public static void main(String[] args)
  {
    MineStat ms = new MineStat("minecraft.frag.land");
    System.out.println("Minecraft server status of " + ms.getAddress() + " on port " + ms.getPort() + ":");
    if(ms.isServerUp())
    {
      System.out.println("Server is online running version " + ms.getVersion() + " with " + ms.getCurrentPlayers() + " out of " + ms.getMaximumPlayers() + " players.");
      System.out.println("Message of the day: " + ms.getMotd());
      System.out.println("Latency: " + ms.getLatency() + "ms");
      System.out.println("Connected using protocol: " + ms.getRequestType());
    }
    else
      System.out.println("Server is offline!");
  }
}
