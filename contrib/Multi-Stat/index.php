<?php require_once("settings.php"); ?>
<html>
<head>
<title><?php echo $siteTitle; ?></title>
<link rel="stylesheet" href="css/style.css" />
<link rel="icon" type="image/png" href="images/logo.png">
<script src="https://kit.fontawesome.com/97c7e13229.js" crossorigin="anonymous"></script>
       <!-- Latest compiled and minified CSS -->
<link rel="stylesheet" href="css/bootstrap.css">

<!-- Optional theme -->
<link rel="stylesheet" href="css/bootstrap-theme.min.css">

<!-- Latest compiled and minified JavaScript -->
<script src="js/bootstrap.min.js"></script>
	
</head>
<body>
<center>
<div class="container">
	<img src="images/logo.png" class="logo" />
	<div class="header"><?php echo $siteName; ?></div>
		<div class="list pull-left">
		<?php
		//Host information
		$serverIP = $javaIP;

		foreach ($serverIP as $ip)
		{
			$urlParts = explode('.', $ip);

			$port = "25565"; // Port for the server to listen on, bedrock is 19132 by default, Java is 25565

			// Valid Protocols: Unknown, Beta, Legacy, ExtendedLegacy, Json, BedrockRaknet
			// Use BedrockRakNet for Bedrock/Pocket Edition, The rest will not work with bedrock servers.  Also, BedrockRaknet does not output player usernames.
			// ExtendedLegacy does not seem to work.  This is a Minestat issue or a Server problem.  
			// For Java, use Json or Legacy, Json seems to be more accurate at locating online servers vs Legacy does.  Most likely because the servers are not using Geyser/Floodgate?
			
			$protocol = "Json";


			$runCMD = "MineStat -Address ".$ip." -Port ".$port." -Protocol ".$protocol." -Timeout 1";
			$output = shell_exec('powershell.exe '.$runCMD);
			$output = str_replace('}', ', ', str_replace('{.', '', $output)); //removes brackets and dots from usernames
			if(str_contains($output, "Offline") || str_contains($output, "Timeout"))
			{
				 $javaStatus = false; // Return Java server status
			}
			else
			{
				$javaStatus = true;
			}
			if($javaStatus != true)
			{
					echo '<div class="alert alert-danger">Java Server: '.$ip.':'.$port.' is currently Offline! </div>';
			}
			else
			{
				if(isset($urlParts[1]))
				{
					echo "<pre class='item text-left'><center>".ucfirst($urlParts[1])." - Java</center>".$output."</pre><br />";
				}
				else
				{
					echo "<pre class='item text-left'><center>".ucfirst($urlParts[0])." - Java</center>".$output."</pre><br />";
				}
			}
		}
?>
</div>
<div class="list pull-right">
<?php		
		// Bedrock Status
		//Host information
				$serverIP = $bedrockIP;

				foreach ($serverIP as $ip)
				{
					$urlParts = explode('.', $ip);

					$port = "19132"; // Port for the server to listen on, bedrock is 19132 by default, Java is 25565

					// Valid Protocols: Unknown, Beta, Legacy, ExtendedLegacy, Json, BedrockRaknet
					// Use BedrockRakNet for Bedrock/Pocket Edition, The rest will not work with bedrock servers.  Also, BedrockRaknet does not output player usernames.
					// ExtendedLegacy does not seem to work.  This is a Minestat issue or a Server problem.  
					// For Java, use Json or Legacy, Json seems to be more accurate at locating online servers vs Legacy does.  Most likely because the servers are not using Geyser/Floodgate?
					
					$protocol = "BedrockRaknet";


					$runCMD = "MineStat -Address ".$ip." -Port ".$port." -Protocol ".$protocol." -Timeout 1";
					$output = shell_exec('powershell.exe '.$runCMD);
					$output = str_replace('}', ', ', str_replace('{.', '', $output)); //removes brackets and dots from usernames
					if(str_contains($output, "Offline") || str_contains($output, "Timeout"))
					{
						$bedrockStatus = false; // Return Java server status
					}
					else
					{
						$bedrockStatus = true;
					}
					if($bedrockStatus != true)
					{
							echo '<div class="alert alert-danger">Bedrock Server: '.$ip.':'.$port.' is currently Offline! </div>';
					}
					else
					{
						if(isset($urlParts[1]))
						{
							echo "<pre class='item text-left'><center>".ucfirst($urlParts[1])." - Bedrock</center>".$output."</pre><br />";
						}
						else
						{
							echo "<pre class='item text-left'><center>".ucfirst($urlParts[0])." - Bedrock</center>".$output."</pre><br />";
						}
					}
				}
		?>
		</div>
</div>
</center>
</body>
</html>