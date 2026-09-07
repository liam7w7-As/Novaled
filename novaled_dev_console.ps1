# ==============================================================================
# Script: novaled_dev_console.ps1
# Descripción: Consola interactiva para depuración inalámbrica en Novaled.
#              Permite:
#              - Conectar por ADB al puerto e IP actual.
#              - Re-compilar e instalar la última versión (opción 'r').
#              - Vincular el dispositivo por primera vez (opción 'v').
#              - Sacar capturas de pantalla del celular (opción 's').
#              - Configurar IP y puerto del celular (opción 't').
#              - Reconectar el dispositivo rápidamente (opción 'q').
#              - Salir del script (opción 'exit').
# ==============================================================================

$adbPath = "C:\Users\UnseR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$appPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$packageId = "com.example.novaled_app"
$mainActivity = "com.example.novaled_app.MainActivity"

# Guardar último puerto e IP utilizados
$puertoFile = Join-Path $appPath ".last_adb_port"
$ipFile = Join-Path $appPath ".last_adb_ip"
$currentPort = "33431"
$currentIp = "192.168.18.15"

if (Test-Path $puertoFile) {
    $currentPort = (Get-Content $puertoFile).Trim()
}
if (Test-Path $ipFile) {
    $currentIp = (Get-Content $ipFile).Trim()
}

function Connect-Adb {
    param([string]$ip, [string]$port)
    Write-Host "Conectando al celular inalámbricamente (${ip}:${port})..." -ForegroundColor Cyan
    $res = & $adbPath connect "${ip}:${port}"
    Write-Host $res -ForegroundColor Gray
    
    # Guardar puerto e IP
    $port > $puertoFile
    $ip > $ipFile
}

function Get-TargetDevice {
    $devices = & $adbPath devices
    # 1. Buscar si hay algún dispositivo con la IP y el puerto actual
    foreach ($line in $devices) {
        if ($line -match "^(${currentIp}:${currentPort})\s+device$") {
            return $matches[1]
        }
    }
    # 2. Buscar cualquier dispositivo inalámbrico (empieza con adb-)
    foreach ($line in $devices) {
        if ($line -match "^(adb-[^\s]+)\s+device$") {
            return $matches[1]
        }
    }
    # 3. Si no hay ninguno, retornar la IP:puerto actual por defecto
    return "${currentIp}:${currentPort}"
}

# Limpiar pantalla e iniciar
Clear-Host
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host "       N O V A L E D   S I S T E M A   -   C O N S O L A   D E V" -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Última conexión guardada: ${currentIp}:${currentPort}" -ForegroundColor Gray
Write-Host "Intentando conectar automáticamente..." -ForegroundColor Gray
Write-Host ""

Connect-Adb $currentIp $currentPort

function Mostrar-Menu {
    $target = Get-TargetDevice
    Write-Host ""
    Write-Host "Consola lista para recibir comandos:" -ForegroundColor Green
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host " [r]    - Re-compilar APK e Instalar/Re-iniciar en el celular" -ForegroundColor Cyan
    Write-Host " [v]    - Vincular dispositivo por primera vez (ADB Pair)" -ForegroundColor Cyan
    Write-Host " [q]    - Reconectar dispositivo (${currentIp}:${currentPort})" -ForegroundColor Cyan
    Write-Host " [t]    - Cambiar IP y puerto del celular" -ForegroundColor Cyan
    Write-Host " [x]    - Sacar captura y guardar en portapapeles (solo Ctrl+V)" -ForegroundColor Cyan
    Write-Host " [s]    - Sacar captura de pantalla y abrir editor para recortar" -ForegroundColor Cyan
    Write-Host " [exit] - Salir de la consola" -ForegroundColor Red
    Write-Host "---------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " Dispositivo detectado actual: $target" -ForegroundColor Gray
    Write-Host "=====================================================================" -ForegroundColor Yellow
    Write-Host ""
}

while ($true) {
    Mostrar-Menu
    $inputVal = Read-Host "Selecciona una opción"
    if ($null -eq $inputVal) {
        # Si la entrada está redirigida o sin consola interactiva, salir para evitar bucles
        try {
            if ([Console]::IsInputRedirected) { break }
        } catch { break }
        continue
    }
    $cmd = $inputVal.Trim().ToLower()
    
    if ($cmd -eq 'r') {
        Write-Host ""
        Write-Host "=== [1/3] Iniciando compilación de Flutter APK Release... ===" -ForegroundColor Yellow
        
        # Ejecutar compilación de Flutter directamente de forma síncrona
        flutter build apk --release
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[Error] La compilación de Flutter falló." -ForegroundColor Red
            continue
        }
        Write-Host "[OK] Compilación finalizada con éxito." -ForegroundColor Green
        
        # Copiar APK a la carpeta de artefactos
        $apkSource = Join-Path $appPath "build\app\outputs\flutter-apk\app-release.apk"
        $apkDest = "C:\Users\UnseR\AppData\Local\Android\Sdk\platform-tools\app-release.apk"
        # Asegurar carpeta de artefactos en el bot
        $botArtifacts = "C:\Users\UnseR\.gemini\antigravity\brain\26a222f6-3034-428e-bad9-71fd527826d5\app-release.apk"
        try {
            Copy-Item $apkSource -Destination $botArtifacts -Force
        } catch {}

        Write-Host "=== [2/3] Conectando e instalando APK en tu HONOR X5b... ===" -ForegroundColor Yellow
        
        $targetDevice = Get-TargetDevice
        # Asegurar conexión
        & $adbPath connect "${currentIp}:${currentPort}" | Out-Null
        
        # Instalar con flags de reinstalación y permisos automáticos
        $installRes = & $adbPath -s $targetDevice install -r -d -g $apkSource
        Write-Host $installRes -ForegroundColor Gray
        
        if ($installRes -match "Success") {
            Write-Host "=== [3/3] Iniciando aplicación en el celular... ===" -ForegroundColor Yellow
            & $adbPath -s $targetDevice shell am start -n "$packageId/$mainActivity" | Out-Null
            Write-Host "[ÉXITO] La app fue actualizada e iniciada en tu celular." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] No se pudo instalar la aplicación. Asegúrate de tener el celular encendido y con depuración inalámbrica activa." -ForegroundColor Red
            Write-Host "Si el error persiste, intenta desinstalar versiones anteriores manualmente en tu celular." -ForegroundColor Yellow
        }
        
    } elseif ($cmd -eq 'v') {
        Write-Host ""
        Write-Host "=== Vincular dispositivo por primera vez (ADB Pair) ===" -ForegroundColor Yellow
        $pairingAddress = Read-Host "Introduce la IP y puerto de vinculación (ej. 192.168.18.15:45687)"
        $pairingCode = Read-Host "Introduce el código de vinculación de 6 dígitos"
        
        if (-not [string]::IsNullOrWhiteSpace($pairingAddress) -and -not [string]::IsNullOrWhiteSpace($pairingCode)) {
            Write-Host "Vinculando dispositivo..." -ForegroundColor Cyan
            $pairRes = & $adbPath pair $pairingAddress.Trim() $pairingCode.Trim()
            Write-Host $pairRes -ForegroundColor Gray
            
            # Guardar automáticamente la IP para ahorrarle trabajo al conectar
            if ($pairingAddress -match "^([^:]+):(\d+)$") {
                $currentIp = $matches[1]
                $currentIp > $ipFile
                Write-Host "Se ha guardado la IP de vinculación ($currentIp) como IP activa." -ForegroundColor Green
            }
        } else {
            Write-Host "Operación cancelada o datos incompletos." -ForegroundColor Yellow
        }
        
    } elseif ($cmd -eq 'q') {
        Write-Host ""
        Write-Host "=== Reconectando al celular... ===" -ForegroundColor Yellow
        Connect-Adb $currentIp $currentPort
        
    } elseif ($cmd -eq 't') {
        Write-Host ""
        Write-Host "=== Configurar IP y Puerto de Depuración Inalámbrica ===" -ForegroundColor Yellow
        $inputIp = Read-Host "Introduce la IP del celular (ENTER para usar $currentIp)"
        if (-not [string]::IsNullOrWhiteSpace($inputIp)) {
            $currentIp = $inputIp.Trim()
        }
        $inputPort = Read-Host "Introduce el puerto (ENTER para usar $currentPort)"
        if (-not [string]::IsNullOrWhiteSpace($inputPort)) {
            $currentPort = $inputPort.Trim()
        }
        Connect-Adb $currentIp $currentPort
        
    } elseif ($cmd -eq 'x') {
        Write-Host ""
        Write-Host "=== Tomando captura y guardando en el portapapeles... ===" -ForegroundColor Yellow
        
        $targetDir = Join-Path $appPath "capturas"
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $localPath = Join-Path $targetDir "captura_$timestamp.png"
        $latestPath = Join-Path $appPath "captura_actual.png"

        $targetDevice = Get-TargetDevice
        try {
            & $adbPath connect "${currentIp}:${currentPort}" | Out-Null
            & $adbPath -s $targetDevice shell screencap -p /sdcard/screen_temp.png
            & $adbPath -s $targetDevice pull /sdcard/screen_temp.png $localPath | Out-Null
            
            if (Test-Path $localPath) {
                Copy-Item $localPath $latestPath -Force
                & $adbPath -s $targetDevice shell rm /sdcard/screen_temp.png
                
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    Add-Type -AssemblyName System.Drawing
                    $img = [System.Drawing.Image]::FromFile($localPath)
                    [System.Windows.Forms.Clipboard]::SetImage($img)
                    $img.Dispose()
                    Write-Host "[ÉXITO] Captura copiada al portapapeles. ¡Listo para pegar con Ctrl + V!" -ForegroundColor Green
                } catch {
                    Write-Host "[ERROR] No se pudo copiar al portapapeles: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "[ERROR] No se pudo descargar la captura de pantalla." -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERROR] No se pudo realizar la captura inalámbrica: $_" -ForegroundColor Red
        }
        
    } elseif ($cmd -eq 's') {
        Write-Host ""
        Write-Host "=== Tomando captura de pantalla inalámbrica... ===" -ForegroundColor Yellow
        
        # Asegurar directorio de capturas
        $targetDir = Join-Path $appPath "capturas"
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir | Out-Null
        }
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $localPath = Join-Path $targetDir "captura_$timestamp.png"
        $latestPath = Join-Path $appPath "captura_actual.png"

        $targetDevice = Get-TargetDevice
        try {
            & $adbPath connect "${currentIp}:${currentPort}" | Out-Null
            & $adbPath -s $targetDevice shell screencap -p /sdcard/screen_temp.png
            & $adbPath -s $targetDevice pull /sdcard/screen_temp.png $localPath | Out-Null
            
            if (Test-Path $localPath) {
                Copy-Item $localPath $latestPath -Force
                & $adbPath -s $targetDevice shell rm /sdcard/screen_temp.png
                
                Write-Host "Captura guardada en: $localPath" -ForegroundColor Green
                Write-Host "Cargando en el portapapeles y abriendo herramienta para recortar..." -ForegroundColor Cyan
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    Add-Type -AssemblyName System.Drawing
                    $img = [System.Drawing.Image]::FromFile($localPath)
                    [System.Windows.Forms.Clipboard]::SetImage($img)
                    $img.Dispose()
                } catch {}

                try {
                    Start-Process "mspaint.exe" -ArgumentList "`"$localPath`""
                } catch {
                    Start-Process $localPath
                }
            } else {
                Write-Host "[ERROR] No se pudo descargar la captura. El archivo no se generó. Verifica la conexión inalámbrica." -ForegroundColor Red
            }
        } catch {
            Write-Host "[ERROR] No se pudo realizar la captura inalámbrica: $_" -ForegroundColor Red
        }
        
    } elseif ($cmd -eq 'exit') {
        Write-Host ""
        Write-Host "Cerrando consola de depuración. ¡Hasta luego!" -ForegroundColor Red
        break
    } else {
        Write-Host "Opción no reconocida: '$cmd'. Por favor selecciona [r, v, q, t, x, s, exit]." -ForegroundColor Yellow
    }
}
