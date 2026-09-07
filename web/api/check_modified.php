<?php
require_once 'config.php';

try {
    // Count isCatalog=true on MySQL
    $stmt = $pdo->prepare("SELECT stockJson, last_modified FROM articulos");
    $stmt->execute();
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $catalog_count = 0;
    $pre_count = 0;
    $latest_modified = '1970-01-01 00:00:00';

    foreach ($rows as $row) {
        $stockJsonStr = $row['stockJson'];
        $last_modified = $row['last_modified'];
        if ($last_modified > $latest_modified) {
            $latest_modified = $last_modified;
        }

        $is_catalog = false;
        if (!empty($stockJsonStr)) {
            $extra = json_decode($stockJsonStr, true);
            if (is_array($extra) && isset($extra['isCatalog']) && $extra['isCatalog'] == true) {
                $is_catalog = true;
            }
        }

        if ($is_catalog) {
            $catalog_count++;
        } else {
            $pre_count++;
        }
    }

    echo json_encode([
        "success" => true,
        "mysql_catalog_count" => $catalog_count,
        "mysql_pre_count" => $pre_count,
        "latest_modified" => $latest_modified,
        "total_rows" => count($rows)
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["error" => $e->getMessage()]);
}
?>
