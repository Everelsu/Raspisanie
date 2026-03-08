# Сборка релизного Android с минимальным размером:
# - обфускация Dart (--obfuscate --split-debug-info)
# - AAB для Play Store (меньше размер за счёт split по ABI) или APK по ABI

param(
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "appbundle"
)

$ErrorActionPreference = "Stop"
$root = (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
Set-Location $root

$symbolsDir = "build\symbols"
if (-not (Test-Path $symbolsDir)) { New-Item -ItemType Directory -Path $symbolsDir -Force | Out-Null }

if ($Target -eq "appbundle") {
    Write-Host "Building release AAB (для Play Store, меньше размер установки)..." -ForegroundColor Cyan
    flutter build appbundle --obfuscate --split-debug-info=$symbolsDir
    Write-Host "Готово: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
} else {
    Write-Host "Building release APK (по ABI — отдельный APK под arm64/armeabi/x86)..." -ForegroundColor Cyan
    flutter build apk --obfuscate --split-debug-info=$symbolsDir --split-per-abi
    Write-Host "Готово: build\app\outputs\flutter-apk\" -ForegroundColor Green
}
