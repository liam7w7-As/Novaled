# ==============================================================================
# Script: screenshot.ps1
# Descripción: Toma una captura de pantalla en alta resolución del celular Android
#              conectado por ADB y la descarga/abre automáticamente en Windows.
# ==============================================================================

# 1. Definir rutas de ADB y carpetas de destino
$adbPath = "C:\Users\UnseR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$appPath = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
$targetDir = Join-Path $appPath "capturas"

# Crear directorio de capturas si no existe
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

Clear-Host
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host "        N O V A L E D   S I S T E M A   -   S C R E E N S H O T" -ForegroundColor Yellow
Write-Host "=====================================================================" -ForegroundColor Yellow
Write-Host "Buscando dispositivo Android activo..." -ForegroundColor Cyan

# Asegurarse de que ADB esté en ejecución e intentar conectar al puerto por defecto si no hay dispositivos
$devices = & $adbPath devices
$hasDevice = $false
foreach ($line in $devices) {
    if ($line -match "device$" -and $line -notmatch "List of") {
        $hasDevice = $true
    }
}

if (-not $hasDevice) {
    Write-Host "Dispositivo no detectado. Intentando reconexión inalámbrica..." -ForegroundColor Yellow
    # Intentar con la IP/Puerto por defecto
    $connectResult = & $adbPath connect 192.168.18.15:33431
    Write-Host $connectResult -ForegroundColor Gray
    
    # Re-verificar
    $devices = & $adbPath devices
    foreach ($line in $devices) {
        if ($line -match "device$" -and $line -notmatch "List of") {
            $hasDevice = $true
        }
    }
}

if (-not $hasDevice) {
    Write-Host "[Error] No se pudo conectar a ningún dispositivo Android." -ForegroundColor Red
    Write-Host "Por favor verifica que la Depuración Inalámbrica esté ACTIVA en el celular." -ForegroundColor Red
    Write-Host "Presiona cualquier tecla para salir..." -ForegroundColor Gray
    [Console]::ReadKey($true) | Out-Null
    exit
}

# 2. Generar nombre de archivo con marca de tiempo
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$filename = "captura_$timestamp.png"
$localPath = Join-Path $targetDir $filename
$latestPath = Join-Path $appPath "captura_actual.png"

Write-Host "Capturando pantalla..." -ForegroundColor Cyan
try {
    # Capturar en el celular
    & $adbPath shell screencap -p /sdcard/screen_temp.png
    
    # Descargar a la computadora
    & $adbPath pull /sdcard/screen_temp.png $localPath | Out-Null
    
    # Copiar como captura_actual.png para acceso rápido
    Copy-Item $localPath $latestPath -Force
    
    # Limpiar archivo temporal en el celular
    & $adbPath shell rm /sdcard/screen_temp.png
    
    # Obtener modelo del dispositivo para el log
    $deviceModel = & $adbPath shell getprop ro.product.model
    $deviceModel = $deviceModel.Trim()

    Write-Host ""
    Write-Host "---------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " -> [ÉXITO] Captura guardada con éxito." -ForegroundColor Green
    Write-Host " Dispositivo: $deviceModel" -ForegroundColor Green
    Write-Host " Archivo Guardado: $localPath" -ForegroundColor Green
    Write-Host " Copia Rápida: $latestPath" -ForegroundColor Green
    Write-Host "---------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
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
} catch {
    Write-Host "[!] Error durante el proceso de captura: $_" -ForegroundColor Red
}
