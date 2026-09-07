<?php
echo "CWD: " . getcwd() . "\n";
$dir = getcwd();
for ($i = 0; $i < 5; $i++) {
    echo "Scanning: $dir\n";
    $files = scandir($dir);
    foreach ($files as $f) {
        if (strpos(strtolower($f), 'log') !== false) {
            $path = "$dir/$f";
            if (is_file($path)) {
                echo "  Found file: $path (" . filesize($path) . " bytes)\n";
            } else {
                echo "  Found dir: $path\n";
            }
        }
    }
    $dir = dirname($dir);
}
?>
