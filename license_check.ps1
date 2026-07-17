<# 
.SYNOPSIS
    Scansiona le dipendenze Flutter per licenze incompatibili con MIT e genera report Markdown

.DESCRIPTION
    Usa license_checker per scansionare pubspec.yaml (incluse sotto-dipendenze)
    e genera un report Markdown in license_check.md con exit code 1 se trova licenze GPL/AGPL/LGPL-3.0

.EXAMPLE
    .\license_check.ps1
    .\license_check.ps1 -FailOnCopyleft
    .\license_check.ps1 -OutputPath "reports/license_report.md"
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "license_check.md",
    
    [Parameter(Mandatory=$false)]
    [switch]$FailOnCopyleft,
    
    [Parameter(Mandatory=$false)]
    [string[]]$FailOnLicenses = @("GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-3.0", "AGPL-1.0", "GPL-1.0", "GPL-2.0-only", "SSPL-1.0", "BSL-1.0", "CC-BY-SA-4.0", "CC-BY-NC-4.0", "GFDL-1.3"),
    
    [Parameter(Mandatory=$false)]
    [switch]$OpenReport,
    
    [Parameter(Mandatory=$false)]
    [switch]$InstallTool
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $projectRoot

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       CatechHub - License Compliance Checker              " -ForegroundColor Cyan
Write-Host "       Licenza progetto: MIT | Controllo compatibilita'     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

function Check-ToolAvailable {
    $toolPath = "lic_ck"
    if (Get-Command $toolPath -ErrorAction SilentlyContinue) {
        return $true
    }
    
    $pubCache = "$env:USERPROFILE\AppData\Local\Pub\Cache\bin\lic_ck.bat"
    if (Test-Path $pubCache) {
        return $true
    }
    
    try {
        dart run license_checker --version 2>$null | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Install-Tool {
    Write-Host "Installazione license_checker..." -ForegroundColor Yellow
    dart pub global activate license_checker
    
    $pubCacheBin = "$env:USERPROFILE\AppData\Local\Pub\Cache\bin"
    if ($env:PATH -notlike "*$pubCacheBin*") {
        $env:PATH += ";$pubCacheBin"
        Write-Host "Aggiunto $pubCacheBin al PATH della sessione corrente" -ForegroundColor Green
    }
}

if ($InstallTool -or -not (Check-ToolAvailable)) {
    Install-Tool
}

Write-Host "Esecuzione 'flutter pub get'..." -ForegroundColor Yellow
flutter pub get | Out-Null
Write-Host "Dipendenze aggiornate" -ForegroundColor Green

$configPath = "$env:TEMP\license_checker_config.yaml"
$configContent = @"
permittedLicenses:
  - MIT
  - BSD-2-Clause
  - BSD-3-Clause
  - Apache-2.0
  - ISC
  - Zlib
  - Unicode-DFS-2015
  - Unicode-DFS-2016

rejectedLicenses:
  - GPL-2.0
  - GPL-3.0
  - AGPL-3.0
  - LGPL-3.0
  - AGPL-1.0
  - GPL-1.0
  - GPL-2.0-only
  - SSPL-1.0
  - BSL-1.0
  - CC-BY-SA-4.0
  - CC-BY-NC-4.0
  - GFDL-1.3

reviewLicenses:
  - LGPL-2.1
  - LGPL-2.0
  - MPL-2.0
  - EPL-2.0
  - EPL-1.0
  - CDDL-1.0
  - CDDL-1.1
  - OSL-3.0
  - AFL-3.0
  - EUPL-1.2
"@
Set-Content -Path $configPath -Value $configContent -Encoding UTF8

$cmd = "lic_ck"
$cmd += " --config `"$configPath`""
$cmd += " --output `"$OutputPath`""
$cmd += " --format=markdown"

if ($FailOnCopyleft) {
    $cmd += " --fail-on=rejected"
}

Write-Host "`nEsecuzione scansione licenze..." -ForegroundColor Yellow
Write-Host "   Comando: $cmd" -ForegroundColor Gray
Write-Host ""

try {
    $exitCode = 0
    $output = Invoke-Expression $cmd 2>&1
    $exitCode = $LASTEXITCODE
    
    Write-Host $output
    
    if (Test-Path $OutputPath) {
        Write-Host "`nReport generato: $OutputPath" -ForegroundColor Green
        
        $content = Get-Content $OutputPath -Raw
        $blockingLicenses = @("GPL-2.0", "GPL-3.0", "AGPL-3.0", "LGPL-3.0", "AGPL-1.0", "GPL-1.0", "GPL-2.0-only", "SSPL-1.0", "BSL-1.0", "CC-BY-SA-4.0", "CC-BY-NC-4.0", "GFDL-1.3")
        $foundBlocking = @()
        
        foreach ($lic in $blockingLicenses) {
            if ($content -match [regex]::Escape($lic)) {
                $foundBlocking += $lic
            }
        }
        
        if ($foundBlocking.Count -gt 0) {
            Write-Host "`nLICENZE BLOCCANTI RILEVATE (incompatibili MIT):" -ForegroundColor Red
            $foundBlocking | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
            Write-Host "`nAZIONE RICHIESTA: Rimuovi o sostituisci i pacchetti con queste licenze" -ForegroundColor Red
        } else {
            Write-Host "`nNESSUNA LICENZA BLOCCANTE RILEVATA - Progetto compatibile MIT" -ForegroundColor Green
        }
        
        $weakCopyleft = @("LGPL-2.1", "LGPL-2.0", "MPL-2.0", "EPL-2.0", "EPL-1.0", "CDDL-1.0", "CDDL-1.1", "OSL-3.0", "AFL-3.0", "EUPL-1.2")
        $foundWeak = @()
        foreach ($lic in $weakCopyleft) {
            if ($content -match [regex]::Escape($lic)) {
                $foundWeak += $lic
            }
        }
        
        if ($foundWeak.Count -gt 0) {
            Write-Host "`nLICENZE WEAK COPYLEFT (review required - dynamic linking OK):" -ForegroundColor Yellow
            $foundWeak | ForEach-Object { Write-Host "   $_" -ForegroundColor Yellow }
        }
        
        if ($OpenReport) {
            Invoke-Item $OutputPath
        }
    }
    
    exit $exitCode
}
catch {
    Write-Host "`nErrore durante la scansione: $_" -ForegroundColor Red
    exit 1
}