<?
$host="udp://".$_SERVER['REMOTE_ADDR'];
$timeout=1;

        // deal with exceptions thrown by fsockopen
        $handle = @fsockopen(
          $host,
          $_GET["p"],
          $errno,
          $errstr,
          2
        );
        if (!$handle) {
        //    echo "$errno : $errstr <br/>";
          echo "Error";
          return;
        }
        // TODO: verify that socket_set_timeout() is required
        socket_set_timeout($handle, $timeout);
        $write = fwrite($handle, "\x00");
        if (!$write) {
            echo "Closed";
            return;
        }
        $startTime = time();
        $header    = fread($handle, 1);
        $endTime   = time();
        $timeDiff  = $endTime - $startTime;
        if ($timeDiff >= $timeout) {
            fclose($handle);
            echo "Open";
        } else {
            fclose($handle);
            echo "Closed";
        }

?>
