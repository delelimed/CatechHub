<#
.SYNOPSIS
    Patcha flutter_bluetooth_serial per compatibilità con Gradle 9.x / AGP 9.x.
.DESCRIPTION
    Modifica SOLO il file build.gradle nella cache pub (build system).
    NON tocca alcun file .java / .kt / MethodChannel / EventChannel.
    
    Modifiche applicate:
    1. jcenter()  -> mavenCentral()  (repository buildscript + allprojects)
    2. Aggiunge namespace (obbligatorio da AGP 8+)
    
    Da eseguire dopo ogni 'flutter pub get' o 'flutter pub cache repair'.
.PARAMETER FlutterSdkPath
    Percorso Flutter SDK (default: auto-detect via flutter --version)
#>
param(
    [string]$CachePath = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev"
)

$ErrorActionPreference = "Stop"

# Trova la directory del plugin nella cache pub
$pluginDir = Get-ChildItem -Path $CachePath -Directory | 
    Where-Object { $_.Name -match "^flutter_bluetooth_serial-\d+\.\d+\.\d+$" } |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $pluginDir) {
    Write-Host "[OK] flutter_bluetooth_serial non trovato nella cache. Niente da patchare." -ForegroundColor Green
    exit 0
}

$buildGradle = Join-Path $pluginDir.FullName "android\build.gradle"

if (-not (Test-Path $buildGradle)) {
    Write-Host "[ERRORE] File non trovato: $buildGradle" -ForegroundColor Red
    exit 1
}

$content = Get-Content $buildGradle -Raw

# Verifica se già patchato
if ($content -match "mavenCentral\(\)" -and $content -notmatch "jcenter\(\)") {
    Write-Host "[OK] $($pluginDir.Name) già patchato." -ForegroundColor Green
    exit 0
}

Write-Host "[PATCH] Patching $($pluginDir.Name)..." -ForegroundColor Yellow

# 1. Sostituisci jcenter() con mavenCentral() nei repository
$content = $content -replace 'jcenter\(\)', 'mavenCentral()'

# 2. Aggiungi namespace se mancante
if ($content -notmatch "namespace\s+'") {
    $content = $content -replace "(apply plugin: 'com.android.library'\s*\n)(android \{)", "`$1android {`n    namespace 'io.github.edufolly.flutterbluetoothserial'"
}

# Scrivi il file patchato
Set-Content -Path $buildGradle -Value $content -NoNewline

Write-Host "[OK] Patch applicata con successo a $buildGradle" -ForegroundColor Green
Write-Host "     - jcenter() sostituito con mavenCentral()" -ForegroundColor Gray
Write-Host "     - namespace aggiunto" -ForegroundColor Gray
Write-Host "     - Nessuna modifica al codice nativo Kotlin/Java" -ForegroundColor Gray
