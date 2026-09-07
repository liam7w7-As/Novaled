<?php
if (file_exists('sync_debug.log')) {
    echo file_get_contents('sync_debug.log');
} else {
    echo 'No log';
}
?>