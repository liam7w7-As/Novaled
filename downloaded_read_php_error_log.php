<?php
$log = __DIR__ . '/php_error.log';
if (file_exists($log)) {
    echo file_get_contents($log);
} else {
    echo "No errors logged yet.";
}
?>
