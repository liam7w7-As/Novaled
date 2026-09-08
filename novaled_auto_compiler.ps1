# Script de Auto-Compilación Inalámbrica Novaled (Papá e Hijos)
$DeviceIp = "192.168.18.31:36557"
$AdbPath = "C:\Users\UnseR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$mainDir = "C:\Almir_trabajos\Novaled Sistema"

Set-Location $mainDir
$Host.UI.RawUI.WindowTitle = "MONITOREO NOVALED - PAPA ESCUCHANDO A SUS HIJOS"

Write-Host "Conectando al celular inalambrico en $DeviceIp..." -ForegroundColor Cyan
& $AdbPath connect $DeviceIp

function Build-And-Deploy {
    param([string]$branchName, [string]$reason)
    
    [console]::beep(1000, 500)
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host " 🔥 DETECTA
    DO CAMBIO EN [$branchName] -> $reason" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host "1. Fusionando cambios a main..." -ForegroundColor Yellow
    
    git checkout main
    git merge $branchName -m "Merge automatico desde $branchName: $reason"
    
    Write-Host "2. Compilando APK Debug de Flutter..." -ForegroundColor Yellow
    flutter build apk --debug

    if ($LASTEXITCODE -eq 0) {
        Write-Host "3. Instalando en celular inalambrico ($DeviceIp)..." -ForegroundColor Green
        & $AdbPath connect $DeviceIp
        & $AdbPath -s $DeviceIp install -r "build\app\outputs\flutter-apk\app-debug.apk"
        & $AdbPath -s $DeviceIp shell am start -n com.example.novaled_app/com.example.novaled_app.MainActivity
        Start-Sleep -Seconds 2
        & $AdbPath -s $DeviceIp shell screencap -p /sdcard/screen_temp.png
        & $AdbPath -s $DeviceIp pull /sdcard/screen_temp.png "$mainDir\captura_actual.png"
        [console]::beep(1500, 300)
        [console]::beep(2000, 400)
        Write-Host "🎉 COMPILADO, DESPLEGADO Y CAPTURADO EN TU CELULAR CON EXITO!" -ForegroundColor Green
    } else {
        Write-Host "❌ ERROR EN LA COMPILACIÓN DE FLUTTER. Revisa el codigo." -ForegroundColor Red
    }
}

$worktrees = @(
    @{ Path="C:\Almir_trabajos\Novaled-PDF"; Branch="pestana-pdf"; Name="PDF" },
    @{ Path="C:\Almir_trabajos\Novaled-PestanaCotizaciones"; Branch="pestana-cotizaciones"; Name="Cotizaciones" },
    @{ Path="C:\Almir_trabajos/Novaled-PestanaInicio"; Branch="pestaña-inicio"; Name="Inicio" },
    @{ Path="C:\Almir_trabajos\Novaled-PestanaPuntoDeVenta"; Branch="pestana-punto-de-venta"; Name="PuntoDeVenta" },
    @{ Path="C:\Almir_trabajos\Novaled-Pestana2"; Branch="trabajo-paralelo"; Name="Pestana2" }
)

Write-Host "👀 Papá está activo y escuchando en tiempo real a sus 5 hijos..." -ForegroundColor Green
Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

$i = 0
while ($true) {
    $i++
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] Check #$i: Papá vigilando worktrees..." -NoNewline
    
    $found = $false
    foreach ($wt in $worktrees) {
        $flagFile = Join-Path -Path $wt.Path -ChildPath "LISTO.flag"
        if (Test-Path $flagFile) {
            $found = $true
            Remove-Item $flagFile -Force
            Build-And-Deploy -branchName $wt.Branch -reason "Se detectó bandera LISTO.flag"
            break
        }
        
        # Verificar si hay commits nuevos en la rama del hijo no fusionados en main
        $unmerged = git log main..$($wt.Branch) --oneline 2>$null
        if ($unmerged) {
            $found = $true
            Build-And-Deploy -branchName $wt.Branch -reason "Se detectaron commits nuevos ($unmerged)"
            break
        }
    }
    
    if (-not $found) {
        Write-Host " [OK - Sin cambios]" -ForegroundColor DarkGray
    }
    
    Start-Sleep -Seconds 3
}
