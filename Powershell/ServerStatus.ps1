function ServerStatus {
  [CmdletBinding()]
  param (
    [string]$address = "localhost",
    [System.Uint16]$port = 25565,
    [int]$timeout = 5
  )
  function returner {
    param (
      $motd, $current_players, $max_players, $latency
    )
    if (!$motd) {
      return @{
        online=$false
        address=$address
        port=$port
      }
    } else {
      return @{
        port=$port
        current_players=$current_players
        motd=$motd
        online=$true
        address=$address
        max_players=$max_players
        latency="$latency"
      }
    }
  }

  [System.Uint16]$dataSize = 512
  [System.Uint16]$numFields = 3

  $rawserverData = [System.Byte[]]::CreateInstance([System.Byte],$dataSize)
  
  try {
    $stopwatch = New-Object System.Diagnostics.Stopwatch
    $tcpclient = New-Object System.Net.Sockets.tcpclient
    $tcpclient.ReceiveTimeout = $timeout * 1000
    $stopwatch.Start()
    $tcpclient.Connect($address, $port)
    $stopwatch.Stop()
    $latency = $stopwatch.ElapsedMilliseconds
    $stream = $tcpclient.GetStream()
    #$payload = [byte[]]@(0xFE, 0x01) //TODO
    $payload = [byte[]]@(0xFE)
    $stream.Write($payload, 0, $payload.Length)
    $stream.Read($rawserverData, 0, $dataSize) > $null
    $tcpclient.Close()
  } catch {
    Write-Verbose "Connection Failed: $($_.Exception.GetType().Name)"
    return returner
  }
  if(($null -eq $rawserverData) -or ($rawserverData.Length -eq 0)){
    return returner
  } else {
    $serverData = [System.Text.Encoding]::BigEndianUnicode.GetString($rawserverData, 3, $dataSize - 4).Split('§') -replace '\x00',''
    if (($null -ne $serverData) -and ($serverData.length -ge $numFields)) {
      return returner $serverData[0] $serverData[1] $serverData[2] "$latency"
    } else {
      Write-Verbose "Unknown response type"
      return returner
    }
  }
}
