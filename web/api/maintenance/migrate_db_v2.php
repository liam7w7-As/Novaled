<?php
require_once 'config.php';

try {
    // 1. Tabla articulos
    $pdo->exec("CREATE TABLE IF NOT EXISTS articulos (
        uuid VARCHAR(64) PRIMARY KEY,
        nombre VARCHAR(255) NOT NULL,
        precio DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        precioCaja DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        descripcion TEXT,
        finalArtId VARCHAR(64),
        proveedor VARCHAR(255),
        codCaja VARCHAR(64),
        stockJson TEXT,
        familia VARCHAR(255) DEFAULT '',
        subcategoria VARCHAR(255) DEFAULT '',
        unidad VARCHAR(64) DEFAULT 'Unidad',
        unidadDetalle VARCHAR(255) DEFAULT '',
        imagen VARCHAR(255) DEFAULT NULL,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 2. Tabla clientes
    $pdo->exec("CREATE TABLE IF NOT EXISTS clientes (
        uuid VARCHAR(64) PRIMARY KEY,
        nombreCompania VARCHAR(255) NOT NULL,
        telefono VARCHAR(64),
        correo VARCHAR(255),
        rn VARCHAR(64) DEFAULT '',
        direccion1 VARCHAR(255) DEFAULT '',
        direccion2 VARCHAR(255) DEFAULT '',
        direccion3 VARCHAR(255) DEFAULT '',
        direccionEnvio1 VARCHAR(255) DEFAULT '',
        direccionEnvio2 VARCHAR(255) DEFAULT '',
        direccionEnvio3 VARCHAR(255) DEFAULT '',
        infoAdicional TEXT,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 3. Tabla cotizaciones
    $pdo->exec("CREATE TABLE IF NOT EXISTS cotizaciones (
        uuid VARCHAR(64) PRIMARY KEY,
        clienteNombre VARCHAR(255),
        fecha VARCHAR(64),
        subtotal DECIMAL(10,2) DEFAULT 0.00,
        impuesto DECIMAL(10,2) DEFAULT 0.00,
        descuento DECIMAL(10,2) DEFAULT 0.00,
        descuentoPorcentaje DECIMAL(10,2) DEFAULT 0.00,
        total DECIMAL(10,2) DEFAULT 0.00,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa TINYINT(1) DEFAULT 0,
        incluyeFirmaCliente TINYINT(1) DEFAULT 0,
        mostrarTerminos TINYINT(1) DEFAULT 1,
        mostrarAhorro TINYINT(1) DEFAULT 0,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 4. Tabla notas_entrega
    $pdo->exec("CREATE TABLE IF NOT EXISTS notas_entrega (
        uuid VARCHAR(64) PRIMARY KEY,
        clienteNombre VARCHAR(255),
        fecha VARCHAR(64),
        subtotal DECIMAL(10,2) DEFAULT 0.00,
        impuesto DECIMAL(10,2) DEFAULT 0.00,
        descuento DECIMAL(10,2) DEFAULT 0.00,
        descuentoPorcentaje DECIMAL(10,2) DEFAULT 0.00,
        total DECIMAL(10,2) DEFAULT 0.00,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa TINYINT(1) DEFAULT 0,
        incluyeFirmaCliente TINYINT(1) DEFAULT 0,
        mostrarTerminos TINYINT(1) DEFAULT 1,
        mostrarAhorro TINYINT(1) DEFAULT 0,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 5. Tabla proformas
    $pdo->exec("CREATE TABLE IF NOT EXISTS proformas (
        uuid VARCHAR(64) PRIMARY KEY,
        clienteNombre VARCHAR(255),
        fecha VARCHAR(64),
        subtotal DECIMAL(10,2) DEFAULT 0.00,
        impuesto DECIMAL(10,2) DEFAULT 0.00,
        descuento DECIMAL(10,2) DEFAULT 0.00,
        descuentoPorcentaje DECIMAL(10,2) DEFAULT 0.00,
        total DECIMAL(10,2) DEFAULT 0.00,
        itemsJson TEXT,
        notas TEXT,
        terminos TEXT,
        incluyeFirmaEmpresa TINYINT(1) DEFAULT 0,
        incluyeFirmaCliente TINYINT(1) DEFAULT 0,
        mostrarTerminos TINYINT(1) DEFAULT 1,
        mostrarAhorro TINYINT(1) DEFAULT 0,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 6. Tabla tiendas
    $pdo->exec("CREATE TABLE IF NOT EXISTS tiendas (
        uuid VARCHAR(64) PRIMARY KEY,
        nombre VARCHAR(255) NOT NULL,
        ubicacion VARCHAR(255),
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 7. Tabla unidades_medida
    $pdo->exec("CREATE TABLE IF NOT EXISTS unidades_medida (
        uuid VARCHAR(64) PRIMARY KEY,
        nombre VARCHAR(255) UNIQUE NOT NULL,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 8. Tabla proveedores
    $pdo->exec("CREATE TABLE IF NOT EXISTS proveedores (
        uuid VARCHAR(64) PRIMARY KEY,
        nombre VARCHAR(255) NOT NULL,
        telefono VARCHAR(64),
        correo VARCHAR(255),
        direccion VARCHAR(255),
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 9. Tabla usuarios
    $pdo->exec("CREATE TABLE IF NOT EXISTS usuarios (
        username VARCHAR(255) PRIMARY KEY,
        passwordHash VARCHAR(255) NOT NULL,
        role VARCHAR(64) NOT NULL DEFAULT 'seller',
        createdAt VARCHAR(64),
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // 10. Tabla sub_ubicaciones
    $pdo->exec("CREATE TABLE IF NOT EXISTS sub_ubicaciones (
        uuid VARCHAR(64) PRIMARY KEY,
        nombre VARCHAR(255) NOT NULL,
        tienda_nombre VARCHAR(255) NOT NULL,
        imagen VARCHAR(255) DEFAULT NULL,
        last_modified TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        deleted TINYINT(1) DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;");

    // Verificar si está vacía la tabla usuarios e insertar por defecto
    $countUsers = $pdo->query("SELECT COUNT(*) FROM usuarios")->fetchColumn();
    if ($countUsers == 0) {
        $defaultUsers = [
            ["username" => "almir", "passwordHash" => "8705589bfb1e156ce82ffa2cbc9a2199faf7ca38287bc2a9902f9183e017611a", "role" => "admin"],
            ["username" => "joel", "passwordHash" => "60a17bff3ae55cd213357b7ee72e29526cc8b0403f1a9a6139f8a5a501b50b3c", "role" => "admin"],
            ["username" => "victor", "passwordHash" => "89dc8dae72704d08ec537e9ad97145ac915225b7509dade9bdc5a701daa66aaf", "role" => "designer"],
            ["username" => "gustavo", "passwordHash" => "4cb84e8f8162613a30347c28c1f2c4e1a3bcb81edef09d70524c7d59a00a96bf", "role" => "seller"],
            ["username" => "dani", "passwordHash" => "6cd3e30b0df83c623fb6a602a34979d0f1a1d438efd43c0cf98157b599a7b4c9", "role" => "seller"]
        ];
        $stmtInsert = $pdo->prepare("INSERT INTO usuarios (username, passwordHash, role, createdAt) VALUES (:username, :passwordHash, :role, :createdAt)");
        foreach ($defaultUsers as $u) {
            $stmtInsert->execute([
                ':username' => $u['username'],
                ':passwordHash' => $u['passwordHash'],
                ':role' => $u['role'],
                ':createdAt' => date('c') // ISO 8601 string
            ]);
        }
    }

    try {
        $pdo->exec("ALTER TABLE articulos ADD COLUMN imagen VARCHAR(255) DEFAULT NULL AFTER unidadDetalle");
    } catch (PDOException $e) {
        // Ignorar si la columna ya existe
    }

    $documentTables = ['cotizaciones', 'notas_entrega', 'proformas'];
    foreach ($documentTables as $table) {
        try {
            $pdo->exec("ALTER TABLE $table ADD COLUMN mostrarAhorro TINYINT(1) DEFAULT 0 AFTER mostrarTerminos");
        } catch (PDOException $e) {
            // Ignorar si la columna ya existe
        }
        try {
            $pdo->exec("ALTER TABLE $table ADD COLUMN comprobado TINYINT(1) DEFAULT 0");
        } catch (PDOException $e) {
            // Ignorar si la columna ya existe
        }
        try {
            $pdo->exec("ALTER TABLE $table ADD COLUMN estado_pago VARCHAR(64) DEFAULT 'por_cobrar'");
        } catch (PDOException $e) {
            // Ignorar si la columna ya existe
        }
    }

    echo json_encode(["success" => true, "message" => "Tablas creadas/verificadas exitosamente en MySQL."]);
} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["error" => "Error al inicializar la base de datos: " . $e->getMessage()]);
}
?>
