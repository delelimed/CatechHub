$commands = @(
    @{ Name = "flutter clean"; Cmd = "flutter clean" },
    @{ Name = "flutter pub get"; Cmd = "flutter pub get" },
    @{ Name = "Disabilita Flutter telemetry"; Cmd = "flutter config --no-analytics" },
    @{ Name = "gradlew clean"; Cmd = "Set-Location android; if (`$?) { ./gradlew clean }; Set-Location .." },
    @{ Name = "flutter build apk (release, arm64)"; Cmd = "flutter build apk --release --dart-define-from-file=.env --dart-define=flutter.analytics=false --target-platform=android-arm64" }
)

function Show-Menu {
    Clear-Host
    Write-Host "===== FLUTTER BUILD AUTOMATION =====" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $commands.Count; $i++) {
        Write-Host "  $($i + 1). $($commands[$i].Name)" -ForegroundColor Yellow
    }
    Write-Host "  A. Esegui TUTTI i comandi in sequenza" -ForegroundColor Green
    Write-Host "  Q. Esci" -ForegroundColor Red
    Write-Host ""
}

function Run-Selected {
    param([int[]]$indices)
    foreach ($i in $indices) {
        Write-Host "`n>>> Esecuzione: $($commands[$i].Name) ..." -ForegroundColor Magenta
        $start = Get-Date
        Invoke-Expression $commands[$i].Cmd
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null) {
            Write-Host "<<< Completato ($((Get-Date - $start).TotalSeconds.ToString('F1'))s)" -ForegroundColor Green
        } else {
            Write-Host "<<< ERRORE (exit code: $LASTEXITCODE)" -ForegroundColor Red
            $choice = Read-Host "Continuare con il prossimo comando? (s/N)"
            if ($choice -ne 's') { break }
        }
    }
}

do {
    Show-Menu
    $choice = Read-Host "Scegli opzione/i (es: 1,3,4 o A per tutti)"
    switch ($choice.ToUpper()) {
        'Q' { Write-Host "Uscita."; break }
        'A' {
            Run-Selected -indices @(0, 1, 2, 3, 4)
            Write-Host "`nPremi un tasto per continuare..." -NoNewline; $null = $Host.UI.RawUI.ReadKey()
        }
        default {
            # Supporta formati: "1,3,4" o "1 3 4" o "1"
            $indices = $choice -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object {
                $n = 0
                if ([int]::TryParse($_, [ref]$n) -and $n -ge 1 -and $n -le $commands.Count) {
                    $n - 1
                }
            }
            if ($indices.Count -gt 0) {
                Run-Selected -indices $indices
                Write-Host "`nPremi un tasto per continuare..." -NoNewline; $null = $Host.UI.RawUI.ReadKey()
            } elseif ($choice -ne '') {
                Write-Host "Scelta non valida!" -ForegroundColor Red
                Start-Sleep 1
            }
        }
    }
} while ($choice.ToUpper() -ne 'Q')
