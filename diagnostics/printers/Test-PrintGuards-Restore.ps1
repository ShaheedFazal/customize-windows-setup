<#
.SYNOPSIS
    Restores the HSS print-hardening policies that Test-PrintGuards-Remove.ps1
    disabled, from the newest PrintGuards-Restore-<host>-*.json backup. Puts the
    box's print-security posture back exactly as it was before the test.

.DESCRIPTION
    For each backed-up guard: if it existed before, re-set it to its prior value;
    if it did NOT exist before (we created it as 0), delete it. Then restart the
    spooler so the restored policies take effect.

    NOTE: the next HSS full apply re-asserts these guards regardless - this script
    just returns the box to a hardened state immediately after the test.

.NOTES
    Elevated admin PowerShell on the box. PS 5.1-safe. Self-contained.
#>

$ErrorActionPreference = 'Continue'

$logDir     = 'C:\Temp'
$installDir = 'C:\Install'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "PrintGuards-Restore-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

Write-Log "Print-guard RESTORE"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Find newest restore file.
$bk = Get-ChildItem -LiteralPath $installDir -Filter "PrintGuards-Restore-$env:COMPUTERNAME-*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bk) {
    Write-Log "ABORT: no PrintGuards-Restore-$env:COMPUTERNAME-*.json found in $installDir. Nothing to restore."
    return
}
Write-Log "Restoring from: $($bk.FullName)"

try { $items = Get-Content -LiteralPath $bk.FullName -Raw | ConvertFrom-Json }
catch { Write-Log "ABORT: could not parse restore file: $_"; return }

# ConvertFrom-Json yields a single object if there was one element; normalise to array.
$items = @($items)

foreach ($it in $items) {
    try {
        if ($it.Existed) {
            if (-not (Test-Path -LiteralPath $it.Path)) { New-Item -Path $it.Path -Force | Out-Null }
            New-ItemProperty -Path $it.Path -Name $it.Name -Value ([int]$it.PriorValue) -PropertyType DWord -Force | Out-Null
            Write-Log "  restored $($it.Name) = $($it.PriorValue)"
        } else {
            Remove-ItemProperty -Path $it.Path -Name $it.Name -ErrorAction SilentlyContinue
            Write-Log "  removed  $($it.Name)  (was not set before the test)"
        }
    } catch { Write-Log "  ERROR restoring $($it.Name): $_" }
}

try {
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    Write-Log "  spooler restarted - restored guards now in effect"
} catch { Write-Log "  WARNING restarting spooler: $_" }

Write-Log "Restore complete. Box is hardened again."
Write-Log "Transcript: $transcript"
