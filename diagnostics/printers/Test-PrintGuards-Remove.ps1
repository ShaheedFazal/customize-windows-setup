<#
.SYNOPSIS
    Reversible test: DISABLE the HSS print-hardening policies, restart the
    spooler, and see whether the blocked legacy drivers (Zebra) recover or
    STILL get blocked (808 / 0x679). Answers "will removing the print guards
    fix it?" empirically, on one box, fully reversibly.

.DESCRIPTION
    The HSS report applies these print policies (verified by grepping the report):
      - RedirectionguardPolicy                              (spooler path-redirection guard)
      - CopyFilesPolicy                                     (CVE-2021-36958 CopyFiles allowlist)
      - PointAndPrint\RestrictDriverInstallationToAdministrators (CVE-2021-34481)
      - Control\Print\RpcAuthnLevelPrivacyEnabled           (CVE-2021-1678 RPC privacy)
    None of these is the spooler's per-plug-in CFG enforcement (that has NO policy
    knob - it's OS-default on 24H2). This test turns the *policy* guards OFF and
    restarts the spooler to see what's policy-driven vs OS-level:

      1. Snapshot printers (esp. the Zebra) + spooler + 808 high-water.
      2. Back up the exact current value of each guard to a restore JSON.
      3. Set each guard to 0 (disabled).
      4. Restart the spooler and watch for NEW 808 blocks.
      5. Re-snapshot: did the Zebra driver load (no new 808 / status Normal), or
         did it block again (808 / 0x679 -> OS-level, guards are NOT the cause)?

    DECISIVE SIGNAL:
      - NEW 808 / 0x679 on zdn* after guards-off restart  => OS-level. Removing the
        guards does NOT fix the Zebra. (Brothers may still recover separately.)
      - NO new Zebra 808 + Zebra status Normal            => the guards WERE the
        cause; disabling them (via report edit / post-apply override) is viable.

    REVERSIBLE: writes C:\Install\PrintGuards-Restore-<host>-<stamp>.json.
    Run Test-PrintGuards-Restore.ps1 afterwards (or just let the next HSS full
    apply re-apply the guards). This DOES lower the box's print-security posture
    until restored - it is a test, not a fix.

.NOTES
    Elevated admin PowerShell on the box. PS 5.1-safe. Self-contained.
#>

$ErrorActionPreference = 'Continue'

$logDir     = 'C:\Temp'
$installDir = 'C:\Install'
foreach ($d in $logDir, $installDir) { if (-not (Test-Path -LiteralPath $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null } }
$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "PrintGuards-Remove-$env:COMPUTERNAME.log"
$restoreFile= Join-Path $installDir "PrintGuards-Restore-$env:COMPUTERNAME-$stamp.json"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block {
    param($InputObject)
    if ($null -eq $InputObject) { Write-Log '  (none)'; return }
    $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096
    foreach ($line in ($text -split "`r?`n")) { if ($line.TrimEnd()) { Write-Log $line.TrimEnd() } }
}
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$zebraRegex = 'Zebra|ZDesigner|ZDN'
$vendorRegex= 'Epson|Zebra|ZDesigner|ZDN|Brother|BRU|Star|TSP|TM-'
$log808     = 'Microsoft-Windows-PrintService/Admin'

# The print guards to disable (all DWord).
$guards = @(
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';                 Name='RedirectionguardPolicy' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';                 Name='CopyFilesPolicy' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint';   Name='RestrictDriverInstallationToAdministrators' }
    [pscustomobject]@{ Path='HKLM:\SYSTEM\CurrentControlSet\Control\Print';                          Name='RpcAuthnLevelPrivacyEnabled' }
)

Write-Log "Print-guard removal TEST (reversible)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"
Write-Log "Restore file: $restoreFile"

# -----------------------------------------------------------------------------
# 1. PRE snapshot
# -----------------------------------------------------------------------------
Write-Section '1. PRE snapshot (printers + Zebra + spooler + 808 high-water)'
function Get-PrinterSnapshot {
    try { return Get-Printer -ErrorAction Stop | Select-Object Name, DriverName, PortName, PrinterStatus }
    catch { Write-Log "  (Get-Printer failed: $_)"; return @() }
}
$prePrinters = @(Get-PrinterSnapshot)
Write-Block $prePrinters
$preZebra = @($prePrinters | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
Write-Log ''
Write-Log "Zebra queues before : $($preZebra.Count)"
foreach ($z in $preZebra) { Write-Log "  - $($z.Name)  [$($z.DriverName)]  port=$($z.PortName)  status=$($z.PrinterStatus)" }

$spool = Get-Service -Name Spooler -ErrorAction SilentlyContinue
Write-Log ''
Write-Log "Spooler service     : $($spool.Status)"

$triggerStart = Get-Date
Write-Log "808 high-water      : any block after $($triggerStart.ToString('HH:mm:ss')) is NEW"

# -----------------------------------------------------------------------------
# 2. Current guard values (read reality before changing anything)
# -----------------------------------------------------------------------------
Write-Section '2. Current print-guard policy values + back them up'
$restore = @()
foreach ($g in $guards) {
    $existed = $false; $prior = $null
    try {
        $item = Get-ItemProperty -Path $g.Path -Name $g.Name -ErrorAction Stop
        $existed = $true; $prior = $item.$($g.Name)
    } catch { $existed = $false }
    $restore += [pscustomobject]@{ Path=$g.Path; Name=$g.Name; Existed=$existed; PriorValue=$prior }
    if ($existed) { Write-Log ("  {0,-45} = {1}" -f $g.Name, $prior) }
    else { Write-Log ("  {0,-45} = (not set)" -f $g.Name) }
}
try {
    $restore | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $restoreFile -Encoding UTF8
    Write-Log ''
    Write-Log "Backed up current guard state -> $restoreFile"
    Write-Log "Run Test-PrintGuards-Restore.ps1 to put these back exactly."
} catch { Write-Log "  WARNING: could not write restore file: $_" }

# -----------------------------------------------------------------------------
# 3. Disable the guards
# -----------------------------------------------------------------------------
Write-Section '3. Disable the print guards (set each to 0)'
foreach ($g in $guards) {
    try {
        if (-not (Test-Path -LiteralPath $g.Path)) { New-Item -Path $g.Path -Force | Out-Null }
        New-ItemProperty -Path $g.Path -Name $g.Name -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Log "  set $($g.Name) = 0"
    } catch { Write-Log "  ERROR setting $($g.Name): $_" }
}

# -----------------------------------------------------------------------------
# 4. Restart spooler + watch for new 808s
# -----------------------------------------------------------------------------
Write-Section '4. Restart spooler (re-attempts loading the blocked drivers)'
try {
    Restart-Service -Name Spooler -Force -ErrorAction Stop
    Write-Log "  spooler restarted at $((Get-Date).ToString('HH:mm:ss'))"
} catch { Write-Log "  ERROR restarting spooler: $_" }
Write-Log "  waiting 25s for the spooler to re-init queues + emit any 808s..."
Start-Sleep -Seconds 25

function Get-New808 {
    param([datetime]$Since)
    $out = @()
    try { $out = @(Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808; StartTime=$Since } -ErrorAction SilentlyContinue) } catch {}
    return $out
}
$new = @(Get-New808 -Since $triggerStart | Sort-Object TimeCreated)
Write-Log ''
Write-Log "NEW 808 blocks after guards-off spooler restart: $($new.Count)"
$zebra808 = $false
foreach ($e in $new) {
    $mm  = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
    $cm  = [regex]::Match("$($e.Message)", '0x[0-9A-Fa-f]+')
    $dll = if ($mm.Success) { $mm.Groups[1].Value } else { '?' }
    $code= if ($cm.Success) { $cm.Value } else { '?' }
    $isZ = ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex)
    if ($isZ) { $zebra808 = $true }
    $flag= if ($isZ) { '  <<< ZEBRA' } elseif ("$($e.Message)" -match $vendorRegex) { '  <<< vendor' } else { '' }
    Write-Log ("  {0}  {1,-22} code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'), $dll, $code, $flag)
}

# -----------------------------------------------------------------------------
# 5. POST snapshot + verdict
# -----------------------------------------------------------------------------
Write-Section '5. POST snapshot + verdict'
$postPrinters = @(Get-PrinterSnapshot)
Write-Block $postPrinters
$postZebra = @($postPrinters | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
Write-Log ''
Write-Log "Zebra queues after  : $($postZebra.Count)"
foreach ($z in $postZebra) { Write-Log "  - $($z.Name)  status=$($z.PrinterStatus)" }

Write-Log ''
$zebraStillBad = [bool]($postZebra | Where-Object { $_.PrinterStatus -ne 'Normal' })
if ($zebra808) {
    Write-Log "VERDICT: the Zebra plug-ins were BLOCKED AGAIN (808/0x679) even with the print"
    Write-Log "         guards OFF. => This block is OS-LEVEL (24H2 hardened spooler), NOT the"
    Write-Log "         HSS policies. Removing the guards does NOT fix the Zebra. Reapply the"
    Write-Log "         guards (restore) - turning them off buys nothing for the Zebra and only"
    Write-Log "         lowers security."
} elseif ($zebraStillBad) {
    Write-Log "VERDICT: no new Zebra 808, but the Zebra queue is still not Normal. Inconclusive -"
    Write-Log "         the queue may need re-adding to re-trigger driver load. Try removing and"
    Write-Log "         re-adding the Zebra queue, then re-check, before concluding."
} else {
    Write-Log "VERDICT: NO new Zebra 808 and the Zebra is Normal with the guards OFF. => the HSS"
    Write-Log "         print policies WERE implicated. Disabling them (via report edit or a"
    Write-Log "         post-apply override) is a candidate fix - weigh the security cost"
    Write-Log "         (reintroduces the CVE-2021-34481/36958/1678 print exposures)."
}
Write-Log ''
Write-Log ">>> Now PHYSICALLY print a Zebra label and a Brother test page and report which work. <<<"
Write-Log ""
Write-Log "REMEMBER: guards are currently OFF on this box. Run Test-PrintGuards-Restore.ps1 to"
Write-Log "restore them, or the next HSS full apply will re-apply them anyway."

Write-Section 'Print-guard removal test complete'
Write-Log "Transcript : $transcript"
Write-Log "Restore via: Test-PrintGuards-Restore.ps1  (reads $restoreFile)"
