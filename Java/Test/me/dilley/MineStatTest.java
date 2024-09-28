/*
 * JUnit tests for MineStat.java class
 * Contributed by Annukka Tormala (nukka)
 */

package me.dilley;

import static org.junit.Assert.*;
import org.junit.Test;

public class MineStatTest
{
  @Test
  // Tests if address is correct
  public void checkAddress()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setAddress("minecraft.frag.land");
    assertEquals("minecraft.frag.land", ms.getAddress());
  }

  @Test
  // Tests if port number is correct
  public void checkPort()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setPort(25565);
    assertEquals(25565, ms.getPort());
  }

  @Test
  // Tests if version number is correct
  public void checkVersion()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setVersion("BungeeCord 1.8.x-1.12.x");
    assertEquals("BungeeCord 1.8.x-1.12.x", ms.getVersion());
  }

  @Test
  // Tests if number of current players is correct
  public void checkNumberOfCurrentPlayers()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setCurrentPlayers(0);
    assertEquals(0, ms.getCurrentPlayers());
  }

  @Test
  // Tests if number of maximum players is correct
  public void checkNumberOfMaximumPlayers()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setMaximumPlayers(32);
    assertEquals(32, ms.getMaximumPlayers());
  }

  @Test
  // Tests if the message of the day is correct
  public void checkMessageOfTheDay()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    ms.setMotd("Frag Land");
    assertEquals("Frag Land", ms.getMotd());
  }

  @Test
  // Tests if the server is up
  public void checkThatServerIsUp()
  {
    MineStat ms = new MineStat("minecraft.frag.land", 25565);
    assertTrue(ms.isServerUp());
  }
}
