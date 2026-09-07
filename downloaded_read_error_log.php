<?php
$log_paths = ['error_log', '../error_log', '../../error_log', '../../../error_log'];
$found = false;
foreach ($log_paths as $path) {
    if (file_exists($path)) {
        $found = true;
        echo "=== LOG: $path ===\n";
        // Show last 50 lines to keep it readable
        $lines = file($path);
        $last_lines = array_slice($lines, -50);
        echo implode("", $last_lines);
        echo "\n";
    }
}
if (!$found) {
    echo "No error log files found.";
}
?>
