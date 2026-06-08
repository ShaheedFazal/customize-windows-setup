# Reference-machine helper: confirms the printui /Ss DEVMODE captures exist and
# look valid before you commit them. Run this after capturing A4.dat/Token.dat.
# Not part of the customize chain - it lives in printer-configs\ (a subfolder),
# which the orchestrator never executes.
#
# Usage (point it at wherever you saved the captures):
#   .\Verify-Captures.ps1                 # checks C:\Temp
#   .\Verify-Captures.ps1 -Path .         # checks current folder

param([string]$Path = 'C:\Temp')

$expected = 'a4_epson_config.dat', 'token_epson_config.dat'
$allGood  = $true

Write-Host "Checking for DEVMODE captures in: $Path`n" -ForegroundColor Cyan

foreach ($file in $expected) {
    $full = Join-Path $Path $file
    $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue

    if (-not $item) {
        Write-Host ("  [MISSING] {0,-12} not found" -f $file) -ForegroundColor Red
        $allGood = $false
    } elseif ($item.Length -eq 0) {
        Write-Host ("  [EMPTY]   {0,-12} 0 bytes - capture failed, re-run /Ss" -f $file) -ForegroundColor Red
        $allGood = $false
    } else {
        Write-Host ("  [OK]      {0,-12} {1,6:N0} bytes  (saved {2})" -f `
            $file, $item.Length, $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor Green
    }
}

Write-Host ''
if ($allGood) {
    Write-Host "Both captures present and non-empty - ready to commit into includes\printer-configs\." -ForegroundColor Green
    exit 0
} else {
    Write-Host "One or more captures are missing or empty. Re-run the printui /Ss commands." -ForegroundColor Yellow
    exit 1
}
