<?php
require_once("settings.php");

function generate_box($ip, $port, $protocol)
{
  $urlParts = explode('.', $ip);
  end($urlParts);
  $urlParts = prev($urlParts);

  $runCMD = 'PowerShell.exe "(MineStat -Address ' . $ip . ' -Port ' . $port . ' -Protocol ' . $protocol . ' -Timeout 1 | ConvertTo-Json)"';
  $output = json_decode(mb_convert_encoding(shell_exec($runCMD), 'UTF-8', 'UTF-8'), true);

  // Check for JSON decoding errors
  if (json_last_error() !== JSON_ERROR_NONE || !isset($output["connection_status"])) {
    exit("Error occured");
    // Handle the error here, you can log it or return a custom error message
  }

  $status = false;
  $statusType = "Offline";
  switch ($output["connection_status"]) {
    case 'Success':
      $statusType = "Online";
      $status = true;
      break;
    case 'Connfail':
      $statusType = "Connection Failure";
      break;
    case 'Timeout':
      $statusType = "Timed Out";
      break;
  }

  $ip = $output["address"];
  $port = $output["port"];
  $version = $output["version"];
  $motd = $output["stripped_motd"];
  $current_players = $output["current_players"];
  $max_players = $output["max_players"];
  $latency = $output["latency"];
  //more available: https://github.com/FragLand/minestat/tree/master/PowerShell
  $output = "\n\naddress         : $ip\n"
    . "port            : $port\n"
    . "version         : $version\n"
    . "motd            : $motd\n"
    . "current_players : $current_players\n"
    . "max_players     : $max_players\n"
    . "latency         : $latency\n\n\n";

  if ($status != true)
    return '<div class="alert alert-danger">Server: ' . $ip . ':' . $port . ' is currently Offline!<br />Status Type: ' . $statusType . '</div>';
  else
    return "<pre class='item text-left'><center>$urlParts - $protocol</center>" . $output . "</pre><br />";
}
?>
<!DOCTYPE html>
<html lang="en">

<head>
  <title><?php echo $siteTitle; ?></title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet" integrity="sha384-T3c6CoIi6uLrA9TneNEoa7RxnatzjcDSCmG1MXxSR1GAsXEV/Dwwykc2MPK8M2HN" crossorigin="anonymous">
  <link rel="stylesheet" href="css/style.css" /> <!-- Extra Styling -->
  <link rel="icon" type="image/png" href="">
</head>

<body>
  <div class="container">
    <img src="" class="logo" />
    <div class="header"><?php echo $siteName; ?></div>
    <div class="list pull-left">
      <?php
      foreach ($javaIP as $ip) {
        echo generate_box($ip, 25565, 'Json');
      }
      ?>
    </div>
    <div class="list pull-right">
      <?php
      foreach ($bedrockIP as $ip) {
        echo generate_box($ip, 19132, 'BedrockRaknet');
      }
      ?>
    </div>
  </div>
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/js/bootstrap.bundle.min.js" integrity="sha384-C6RzsynM9kWDrMNeT87bh95OGNyZPhcTNXj1NW7RuBCsyN/o0jlpcV8Qyq46cDfL" crossorigin="anonymous"></script> <!-- Bootstrap JS -->
  <script src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.11.8/dist/umd/popper.min.js" integrity="sha384-I7E8VVD/ismYTF4hNIPjVp/Zjvgyol6VFvRkX/vR+Vc4jQkC+hVqc2pM8ODewa9r" crossorigin="anonymous"></script> <!-- Popper -->
  <script src="https://code.jquery.com/jquery-3.7.1.min.js" integrity="sha256-/JqT3SQfawRcv/BIHPThkBvs0OEvtFFmqPF/lYI/Cxo=" crossorigin="anonymous"></script> <!-- JQuery -->
</body>

</html>

