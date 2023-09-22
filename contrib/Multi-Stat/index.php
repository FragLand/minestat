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
<html>

<head>
  <title><?php echo $siteTitle; ?></title>
  <script src="https://kit.fontawesome.com/97c7e13229.js" crossorigin="anonymous"></script>
  <!-- Latest compiled and minified bootstrap CSS -->
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">
  <!-- Latest compiled and minified Jquery -->
  <script src="https://code.jquery.com/jquery-3.7.1.slim.min.js" integrity="sha256-kmHvs0B+OpCW5GVHUNjv9rOmY0IvSIRcf7zGUDTDQM8=" crossorigin="anonymous"></script>
  <!-- Latest compiled and minified bootstrap JavaScript -->
  <script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
  <link rel="stylesheet" href="css/style.css" />
  <link rel="icon" type="image/png" href="">
</head>

<body>
  <center>
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
  </center>
</body>

</html>

