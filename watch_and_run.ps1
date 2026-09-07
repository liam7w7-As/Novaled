# ==============================================================================
# Script: watch_and_run.ps1
# Descripción: Automatiza la compilación y Hot Reload simultáneo en Windows Desktop
#              y dispositivos/emuladores Android.
# ==============================================================================

# 1. Definir variables iniciales
$appPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$libPath = Join-Path $appPath "lib"
$androidId = $null
$lastDeviceCheck = [DateTime]::MinValue

# 2. Inicializar objeto COM para interacción con el teclado
$wshell = New-Object -ComObject Wscript.Shell

# Función para verificar de forma pasiva si una ventana CMD con un título específico está abierta
function Is-WindowOpen ($title) {
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.MainWindowTitle -like "*$title*") {
            return $true
        }
    }
    return $false
}

# Función para obtener un objeto de proceso CMD basado en el título de su ventana principal
function Get-ProcessByTitle ($title) {
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.MainWindowTitle -like "*$title*") {
            return $p
        }
    }
    return $null
}

# Función para buscar dispositivos Android o Emuladores conectados
function Get-AndroidDeviceId {
    Write-Host "Buscando dispositivos Android conectados..." -ForegroundColor Cyan
    try {
        $devices = flutter devices
        foreach ($line in $devices) {
            # Parsear línea por línea de forma robusta e insensible a codificaciones de terminal extrañas.
            # Normalizamos el separador de columnas (cualquier símbolo no ASCII rodeado de espacios) a "|"
            $cleanLine = $line -replace "\s+[^a-zA-Z0-9\s\(\)\.\-]+\s+", "|"
            $parts = $cleanLine -split "\|"
            if ($parts.Count -ge 3) {
                $deviceId = $parts[1].Trim()
                $platform = $parts[2].Trim()
                if ($platform -match "android") {
                    $deviceName = $parts[0].Trim()
                    Write-Host "-> [OK] Dispositivo Android detectado: $deviceId ($deviceName)" -ForegroundColor Green
                    return $deviceId
                }
            }
        }
    } catch {
        Write-Host "Advertencia al ejecutar 'flutter devices': $_" -ForegroundColor Yellow
    }
    Write-Host "-> No se detectó ningún dispositivo Android conectado." -ForegroundColor Gray
    return $null
}

# Limpiar pantalla y dar bienvenida
Clear-Host
Write-Host "=====================================================================" -ForegroundColor Blue
Write-Host "       N O V A L E D   S I S T E M A   -   W A T C H   &   R U N" -ForegroundColor Blue
Write-Host "=====================================================================" -ForegroundColor Blue
Write-Host "Ruta del Proyecto: $appPath" -ForegroundColor Gray
Write-Host "Ruta de Monitoreo: $libPath" -ForegroundColor Gray
Write-Host ""
# Intentar conectar de forma inalámbrica al celular
Write-Host "Intentando conectar al celular inalámbricamente (192.168.18.15:33431)..." -ForegroundColor Cyan
try {
    & 'C:\Users\UnseR\AppData\Local\Android\Sdk\platform-tools\adb.exe' connect 192.168.18.15:33431
} catch {
    Write-Host "Advertencia al conectar ADB inalámbricamente: $_" -ForegroundColor Yellow
}
Start-Sleep -Seconds 1

# Ejecutar la primera detección de dispositivos Android
$lastDeviceCheck = Get-Date
$detectedId = Get-AndroidDeviceId
if ($detectedId) {
    $androidId = $detectedId
}

$windowsProcess = Get-ProcessByTitle "FlutterWindows"
$androidProcess = Get-ProcessByTitle "FlutterAndroid"

# 3. Lanzamiento inicial de procesos en ventanas CMD independientes
if ($null -eq $windowsProcess) {
    Write-Host "Iniciando terminal para Windows Desktop..." -ForegroundColor Cyan
    $windowsProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "[Console]::Title = 'FlutterWindows'; Set-Location '$appPath'; flutter run -d windows" -PassThru
    Start-Sleep -Seconds 3
} else {
    Write-Host "[Info] La ventana 'FlutterWindows' (PID: $($windowsProcess.Id)) ya está abierta." -ForegroundColor Gray
}

if ($androidId) {
    if ($null -eq $androidProcess) {
        Write-Host "Iniciando terminal para Android ($androidId) en modo Debug..." -ForegroundColor Cyan
        $androidProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "[Console]::Title = 'FlutterAndroid'; Set-Location '$appPath'; flutter run -d $androidId" -PassThru
        Start-Sleep -Seconds 3
    } else {
        Write-Host "[Info] La ventana 'FlutterAndroid' (PID: $($androidProcess.Id)) ya está abierta." -ForegroundColor Gray
    }
}

# 4. Monitoreo en Segundo Plano (Watcher Loop)
$lastChecked = Get-Date
$manualRestartRequested = $false
Write-Host ""
Write-Host "Monitoreando cambios en archivos .dart... Presiona R para reinicio manual, Q para salir." -ForegroundColor Green
Write-Host "---------------------------------------------------------------------" -ForegroundColor Gray

while ($true) {
    # Comprobación de que las ventanas sigan abiertas (reabrir si se cerraron)
    if ($null -eq $windowsProcess -or -not (Get-Process -Id $windowsProcess.Id -ErrorAction SilentlyContinue)) {
        # Fallback: buscar por título si ya existe otra
        $windowsProcess = Get-ProcessByTitle "FlutterWindows"
        if ($null -eq $windowsProcess) {
            Write-Host "[!] La ventana 'FlutterWindows' se cerró. Intentando relanzar..." -ForegroundColor Yellow
            $windowsProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "[Console]::Title = 'FlutterWindows'; Set-Location '$appPath'; flutter run -d windows" -PassThru
            Start-Sleep -Seconds 2
        }
    }

    # Búsqueda diferida de dispositivos Android (cada 25 segundos máximo) para no saturar el CPU
    $now = Get-Date
    if (($null -eq $androidProcess -or -not (Get-Process -Id $androidProcess.Id -ErrorAction SilentlyContinue)) -and ($now - $lastDeviceCheck).TotalSeconds -gt 25) {
        $lastDeviceCheck = $now
        # Fallback: buscar por título si ya existe otra
        $androidProcess = Get-ProcessByTitle "FlutterAndroid"
        if ($null -eq $androidProcess) {
            $detectedId = Get-AndroidDeviceId
            if ($detectedId) {
                $androidId = $detectedId
            }
            if ($androidId) {
                Write-Host "[!] Iniciando terminal 'FlutterAndroid' para dispositivo $androidId en modo Debug..." -ForegroundColor Yellow
                $androidProcess = Start-Process powershell -ArgumentList "-NoExit", "-Command", "[Console]::Title = 'FlutterAndroid'; Set-Location '$appPath'; flutter run -d $androidId" -PassThru
                Start-Sleep -Seconds 2
            }
        }
    }

    # Monitorear cambios en todos los archivos .dart de la carpeta lib recursivamente
    $files = Get-ChildItem -Path $libPath -Filter *.dart -Recurse -ErrorAction SilentlyContinue
    $hasChanges = $false
    if ($manualRestartRequested) {
        $hasChanges = $true
        $manualRestartRequested = $false
    }
    $newestWriteTime = $lastChecked

    foreach ($file in $files) {
        if ($file.LastWriteTime -gt $lastChecked) {
            $hasChanges = $true
            if ($file.LastWriteTime -gt $newestWriteTime) {
                $newestWriteTime = $file.LastWriteTime
            }
        }
    }

    # Si se detecta algún cambio, ejecutar Hot Restart
    if ($hasChanges) {
        $lastChecked = $newestWriteTime
        $timeStr = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timeStr] Cambio de archivo o reinicio manual detectado. Enviando Hot Restart..." -ForegroundColor Yellow

        # Hot restart en Windows
        if ($null -ne $windowsProcess -and (Get-Process -Id $windowsProcess.Id -ErrorAction SilentlyContinue)) {
            # Intentar activar por PID primero, luego por título
            $activated = $wshell.AppActivate($windowsProcess.Id)
            if (-not $activated) {
                $activated = $wshell.AppActivate("FlutterWindows")
            }
            if ($activated) {
                Start-Sleep -Milliseconds 500
                $wshell.SendKeys("+r")
                Write-Host " -> Hot Restart enviado a Windows Desktop" -ForegroundColor Green
            } else {
                Write-Host " -> [Advertencia] No se pudo enfocar la ventana 'FlutterWindows' para enviar Hot Restart." -ForegroundColor Yellow
            }
        }

        # Hot restart en Android
        if ($null -ne $androidProcess -and (Get-Process -Id $androidProcess.Id -ErrorAction SilentlyContinue)) {
            # Intentar activar por PID primero, luego por título
            $activated = $wshell.AppActivate($androidProcess.Id)
            if (-not $activated) {
                $activated = $wshell.AppActivate("FlutterAndroid")
            }
            if ($activated) {
                Start-Sleep -Milliseconds 500
                $wshell.SendKeys("+r")
                Write-Host " -> Hot Restart enviado a Android ($androidId)" -ForegroundColor Green
            } else {
                Write-Host " -> [Advertencia] No se pudo enfocar la ventana 'FlutterAndroid' para enviar Hot Restart." -ForegroundColor Yellow
            }
        }
    }

    # Esperar 1.5 segundos de forma responsiva a teclado (permite presionar R para reinicio manual)
    for ($i = 0; $i -lt 15; $i++) {
        $keyAvailable = $false
        try {
            $keyAvailable = [Console]::KeyAvailable
        } catch {}
        if ($keyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'r' -or $key.KeyChar -eq 'R') {
                Write-Host ""
                Write-Host "-> Reinicio manual solicitado desde teclado." -ForegroundColor Magenta
                $manualRestartRequested = $true
                break
            } elseif ($key.KeyChar -eq 's' -or $key.KeyChar -eq 'S') {
                Write-Host ""
                Write-Host "-> Ejecutando captura de pantalla inalámbrica..." -ForegroundColor Yellow
                try {
                    & Powershell.exe -File (Join-Path $appPath "screenshot.ps1")
                } catch {
                    Write-Host "No se pudo ejecutar la captura de pantalla: $_" -ForegroundColor Red
                }
            } elseif ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') {
                Write-Host ""
                Write-Host "-> Saliendo..." -ForegroundColor Red
                exit
            }
        }
        Start-Sleep -Milliseconds 100
    }
}
