<#
.SYNOPSIS
    Isolates WHICH of the four HSS print guards (if any) causes print queues to
    be removed, by enabling ONE guard at a time (all others off), bouncing the
    spooler, and recording whether any queue vanished or threw an 808 block.
    Restores printers from the PrintBrm backup between each guard so every test
    starts from the same baseline.

.DESCRIPTION
    Guards tested (each set to 1 in turn, others 0):
      1. RedirectionguardPolicy                              - spooler path-redirection guard
      2. CopyFilesPolicy                                     - CVE-2021-36958 CopyFiles allowlist
      3. RestrictDriverInstallationToAdministrators          - CVE-2021-34481 Point and Print
      4. RpcAuthnLevelPrivacyEnabled                         - CVE-2021-1678 RPC privacy

    Per guard:
      a. Reset: all guards 0, restart spooler, PrintBrm-restore the backup,
         snapshot the baseline queue set.
      b. Enable ONLY this guard (=1).
      c. Wait briefly (catch a live policy-change reaction), then restart the
         spooler (catch the restart reaction), wait, snapshot.
      d. Diff vs baseline: which queues vanished? which 808 modules/codes fired?
      e. Record the per-guard verdict.

    At the end it prints a summary table (guard -> effect) and RE-ENABLES all
    four guards (=1) so the box is left HARDENED. The next HSS full apply
    re-asserts them regardless.

    IMPORTANT CAVEAT (printed in the summary): the real break happens during a
    full ImportReport apply; a plain spooler restart may not reproduce it. If
    NO single guard removes a queue here, the trigger is something the apply
    does beyond setting these guards - not the guards themselves.

    REQUIRES a PrintBrm backup (PrinterBackup-<host>-*.printerExport from
    Test-ZebraApply-2-Backup.ps1) in C:\Install or C:\Temp, so queues can be
    restored between iterations.

.NOTES
    Elevated admin PowerShell on the box. PS 5.1-safe. Self-contained.
    Destructive-but-recoverable: queues may be removed during a guard's test and
    are restored from the backup before the next guard.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "PrintGuards-Isolate-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block {
    param($InputObject)
    if ($null -eq $InputObject) { Write-Log '  (none)'; return }
    $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096
    foreach ($line in ($text -split "`r?`n")) { if ($line.TrimEnd()) { Write-Log $line.TrimEnd() } }
}
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$zebraRegex  = 'Zebra|ZDesigner|ZDN'
$vendorRegex = 'Epson|Zebra|ZDesigner|ZDN|Brother|BRU|Star|TSP|TM-'
$log808      = 'Microsoft-Windows-PrintService/Admin'

$guards = @(
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';               Name='RedirectionguardPolicy';                     Label='1. RedirectionGuard' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';               Name='CopyFilesPolicy';                            Label='2. CopyFiles (CVE-2021-36958)' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'; Name='RestrictDriverInstallationToAdministrators';  Label='3. RestrictDriverInstall (CVE-2021-34481)' }
    [pscustomobject]@{ Path='HKLM:\SYSTEM\CurrentControlSet\Control\Print';                        Name='RpcAuthnLevelPrivacyEnabled';                Label='4. RpcAuthnPrivacy (CVE-2021-1678)' }
)

Write-Log "Print-guard ISOLATION sweep (one guard at a time)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# Prereqs: PrintBrm + a backup to restore from
# -----------------------------------------------------------------------------
$brm = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'
if (-not (Test-Path -LiteralPath $brm)) { Write-Log "ABORT: PrintBrm.exe not found at $brm"; return }
$backup = $null
foreach ($dir in 'C:\Install','C:\Temp') {
    $cand = Get-ChildItem -LiteralPath $dir -Filter "PrinterBackup-$env:COMPUTERNAME-*.printerExport" -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $backup = $cand; break }
}
if (-not $backup) {
    Write-Log "ABORT: no PrinterBackup-$env:COMPUTERNAME-*.printerExport found. Run Test-ZebraApply-2-Backup.ps1"
    Write-Log "       first so queues can be restored between guard tests."
    return
}
Write-Log "Restore source: $($backup.FullName)"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Get-PrinterSnapshot {
    try { return @(Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus) }
    catch { Write-Log "  (Get-Printer failed: $_)"; return @() }
}
function Get-New808 {
    param([datetime]$Since)
    try { return @(Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808; StartTime=$Since } -ErrorAction SilentlyContinue | Sort-Object TimeCreated) }
    catch { return @() }
}
function Set-Guard {
    param($Guard, [int]$Value)
    try {
        if (-not (Test-Path -LiteralPath $Guard.Path)) { New-Item -Path $Guard.Path -Force | Out-Null }
        New-ItemProperty -Path $Guard.Path -Name $Guard.Name -Value $Value -PropertyType DWord -Force | Out-Null
    } catch { Write-Log "  ERROR setting $($Guard.Name)=$Value : $_" }
}
function Set-AllGuards { param([int]$Value) foreach ($g in $guards) { Set-Guard -Guard $g -Value $Value } }
function Restart-Spool {
    try { Restart-Service -Name Spooler -Force -ErrorAction Stop } catch { Write-Log "  WARNING restarting spooler: $_" }
}
function Restore-Printers {
    Write-Log "  PrintBrm restore (-R -O FORCE) ..."
    try { & $brm -R -F $backup.FullName -O FORCE *>> $transcript } catch { Write-Log "  ERROR PrintBrm restore: $_" }
    Start-Sleep -Seconds 8
}
function Reset-Baseline {
    # all guards off, spooler restarted, printers restored - returns baseline name set
    Set-AllGuards -Value 0
    Restart-Spool
    Start-Sleep -Seconds 5
    Restore-Printers
    $snap = Get-PrinterSnapshot
    return ,@($snap | ForEach-Object { $_.Name })
}

# -----------------------------------------------------------------------------
# Sweep
# -----------------------------------------------------------------------------
$results = @()
foreach ($g in $guards) {
    Write-Section "Testing $($g.Label)"

    Write-Log "Reset to baseline (all guards OFF, printers restored)..."
    $baseNames = Reset-Baseline
    Write-Log "Baseline queues ($($baseNames.Count)): $($baseNames -join ', ')"

    Write-Log ""
    Write-Log "Enable ONLY $($g.Name)=1 (others 0)..."
    Set-AllGuards -Value 0
    Set-Guard -Guard $g -Value 1
    $mark = Get-Date

    Write-Log "  wait 8s for a live policy-change reaction..."
    Start-Sleep -Seconds 8
    Write-Log "  restart spooler + wait 25s for the restart reaction..."
    Restart-Spool
    Start-Sleep -Seconds 25

    $post = Get-PrinterSnapshot
    $postNames = @($post | ForEach-Object { $_.Name })
    $vanished = @($baseNames | Where-Object { $_ -notin $postNames })
    $new808 = Get-New808 -Since $mark

    Write-Log ""
    Write-Log "Queues after  ($($postNames.Count)): $($postNames -join ', ')"
    Write-Log "VANISHED with $($g.Name)=1 : $($vanished.Count)"
    foreach ($v in $vanished) {
        $flag = if ($v -match $zebraRegex) { '  <<< ZEBRA' } elseif ($v -match $vendorRegex) { '  <<< vendor' } else { '' }
        Write-Log "  - $v$flag"
    }
    Write-Log "NEW 808 blocks: $($new808.Count)"
    $modules = @()
    foreach ($e in $new808) {
        $mm = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
        $cm = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
        $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
        $code= if ($cm.Success) { $cm.Value } else { '?' }
        $modules += "$dll($code)"
        $flag = if ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex) { '  <<< ZEBRA' } elseif ("$($e.Message)" -match $vendorRegex) { '  <<< vendor' } else { '' }
        Write-Log ("  {0}  {1,-22} code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code, $flag)
    }

    $broke = ($vanished.Count -gt 0 -or $new808.Count -gt 0)
    Write-Log ""
    if ($broke) { Write-Log "RESULT: $($g.Label) -> REPRODUCED the break ($($vanished.Count) vanished, $($new808.Count) blocks)." }
    else { Write-Log "RESULT: $($g.Label) -> no effect (queues intact, no blocks)." }

    $results += [pscustomobject]@{
        Guard    = $g.Label
        Broke    = $broke
        Vanished = $vanished.Count
        Blocks   = $new808.Count
        Modules  = ($modules -join ' ')
    }
}

# -----------------------------------------------------------------------------
# Restore to baseline + leave the box HARDENED
# -----------------------------------------------------------------------------
Write-Section 'Cleanup - restore printers + re-enable ALL guards (leave hardened)'
Set-AllGuards -Value 0
Restart-Spool
Start-Sleep -Seconds 5
Restore-Printers
Write-Log "Re-enabling all four guards (=1)..."
Set-AllGuards -Value 1
Restart-Spool
Write-Log "Box left HARDENED (all four guards = 1). Next HSS apply re-asserts them too."

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Section 'SUMMARY - which guard reproduced the break'
Write-Block ($results | Select-Object Guard, Broke, Vanished, Blocks, Modules)

$culprits = @($results | Where-Object { $_.Broke })
Write-Log ""
if ($culprits.Count -eq 0) {
    Write-Log "READ: NO single guard removed a queue via a spooler restart. The break is NOT"
    Write-Log "      driven by any one of these guards on its own - the trigger is something the"
    Write-Log "      full ImportReport apply does beyond setting them (or an interaction of"
    Write-Log "      several). Next step: test combinations, or run a full apply with the guards"
    Write-Log "      removed from the report to isolate at the apply level."
} elseif ($culprits.Count -eq 1) {
    Write-Log "READ: a SINGLE guard reproduced the break: $($culprits[0].Guard). Removing just that"
    Write-Log "      one (keeping the other three) is the minimal-security-cost candidate fix."
    Write-Log "      Validate it survives a real full apply before fleet rollout."
} else {
    Write-Log "READ: $($culprits.Count) guards reproduced the break: $((($culprits | ForEach-Object { $_.Guard }) -join '; '))."
    Write-Log "      Removing the lightest-cost subset that covers the break is the goal - prefer"
    Write-Log "      dropping CopyFiles/RedirectionGuard over the RestrictDriverInstall admin one."
}
Write-Log ""
Write-Log "CAVEAT: a plain spooler restart may not fully reproduce the full-apply break. Treat a"
Write-Log "        positive (a guard broke it) as strong; treat an all-clear as 'not via restart -"
Write-Log "        confirm at the full-apply level' rather than 'guards are innocent'."

Write-Section 'Isolation sweep complete'
Write-Log "Transcript: $transcript"
Write-Log "PHYSICALLY print a Zebra label + Brother page now (box is hardened again) to confirm state."
