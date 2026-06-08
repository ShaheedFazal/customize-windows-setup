<#
.SYNOPSIS
    STEP 1 of the Zebra end-to-end test. Read-only baseline of a box that has
    NOT broken yet, so we can later watch the HSS full apply break it (or not)
    under controlled conditions.

.DESCRIPTION
    Captures, in one read-only pass:
      - OS / build / UBR  (confirms Windows 11 24H2+ >= 26100, the enforcer)
      - HSS install state (Get-AppxPackage VioletHansen.HardenSystemSecurity)
      - HSS apply state   (HKLM ReportHash / LastAppliedStatus / LastAppliedUtc)
        + the staged report's current hash, so we can tell whether FORCING an
        apply would be a real FULL apply (hash mismatch or status != success)
      - Apps bootstrap state (HKLM ...\Apps) - what "Verify Bootstrap Apps
        failed" is actually reporting
      - The two scheduled tasks (Install-UserApps, Apply-HardenSystemSecurity)
        and their last run result
      - Printers: queues, drivers, ports, offline state, PnP health
        (Zebra/Epson/Brother/Star flagged)
      - Windows Protected Print Mode state
      - Existing Event 808 plug-in blocks (count / last / which DLLs) - to prove
        the box is currently CLEAN before we trigger anything

    Ends with a VERDICT: is this a valid test box, and would forcing an apply be
    a genuine full apply.

    ONLY READS. No changes. Console + transcript at C:\Temp.

.NOTES
    SuperOps (SYSTEM). Self-contained. PS 5.1-safe. No automated tests.
    Part of the Test-ZebraApply-*.ps1 kit (1 baseline, 2 backup,
    3 trigger+watch, 4 restore).
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "ZebraTest-1-Baseline-$env:COMPUTERNAME.log"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block {
    param($InputObject, [string]$Format = 'Table')
    if ($null -eq $InputObject) { Write-Log '  (none)'; return }
    if ($Format -eq 'List') { $text = $InputObject | Format-List * | Out-String -Width 4096 }
    else { $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096 }
    foreach ($line in ($text -split "`r?`n")) { if ($line.TrimEnd()) { Write-Log $line.TrimEnd() } }
}
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$vendorRegex = 'Epson|Zebra|ZDesigner|Brother|BRU|Star|TSP|TM-'
$stateKey    = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\HardenSystemSecurity'
$appsKey     = 'HKLM:\SOFTWARE\CustomizeWindowsSetup\Apps'
$stagedReport = 'C:\ProgramData\CustomizeWindowsSetup\Harden-System-Security.report.json'
$pkgName     = 'VioletHansen.HardenSystemSecurity'

Write-Log "Zebra end-to-end test - STEP 1 baseline (read-only)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. OS / build - is this a 24H2+ box (the enforcer)?
# -----------------------------------------------------------------------------
Write-Section '1. OS / build'
$build = 0; $ubr = 0
try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $build = [int]$cv.CurrentBuildNumber
    $ubr   = [int]$cv.UBR
    Write-Log "Product      : $($cv.ProductName)"
    Write-Log "DisplayVer   : $($cv.DisplayVersion)"
    Write-Log "Build.UBR    : $build.$ubr"
} catch { Write-Log "ERROR reading CurrentVersion: $_" }
$is24H2 = ($build -ge 26100)
if ($is24H2) {
    Write-Log "ENFORCER     : YES - build >= 26100 (24H2+), the hardened spooler that rejects legacy plug-ins"
} else {
    Write-Log "ENFORCER     : NO  - build < 26100; this box's print engine does NOT enforce, so it is a POOR test box for the break"
}

# -----------------------------------------------------------------------------
# 2. HSS install state
# -----------------------------------------------------------------------------
Write-Section '2. HSS app install state'
$pkg = $null
try {
    $pkg = Get-AppxPackage -AllUsers -Name $pkgName -ErrorAction Stop |
        Sort-Object Version -Descending | Select-Object -First 1
} catch { Write-Log "ERROR Get-AppxPackage: $_" }
if ($pkg) {
    Write-Log "HSS installed: YES  v$($pkg.Version)"
    Write-Log "InstallPath  : $($pkg.InstallLocation)"
    $exe = $null
    foreach ($n in 'HardenSystemSecurity.exe','HSS.exe') {
        $p = Join-Path $pkg.InstallLocation $n
        if (Test-Path -LiteralPath $p) { $exe = $p; break }
    }
    Write-Log "Binary       : $(if ($exe) { $exe } else { '(not found in package!)' })"
} else {
    Write-Log "HSS installed: NO - the per-user install task has not landed HSS yet."
    Write-Log "             => no ImportReport has ever run; printers are PRE-HARDENING."
    Write-Log "             => to test the break we must first get HSS installed (Step 3 will note this)."
}

# -----------------------------------------------------------------------------
# 3. HSS apply state + would a forced apply be a FULL apply?
# -----------------------------------------------------------------------------
Write-Section '3. HSS apply state (HKLM) + staged report'
$storedHash = $null; $storedStatus = $null
try {
    $st = Get-ItemProperty -Path $stateKey -ErrorAction Stop
    $storedHash   = $st.ReportHash
    $storedStatus = $st.LastAppliedStatus
    Write-Log "ReportHash       : $(if ($storedHash) { $storedHash.Substring(0,[Math]::Min(16,$storedHash.Length)) + '...' } else { '(none)' })"
    Write-Log "LastAppliedStatus: $storedStatus"
    Write-Log "LastAppliedUtc   : $($st.LastAppliedUtc)"
    Write-Log "LastAppliedExit  : $($st.LastAppliedExitCode)"
    Write-Log "AppliedHssVersion: $($st.AppliedHssVersion)"
} catch {
    Write-Log "HKLM apply state : (key absent - apply task has never recorded a result)"
}

$stagedHash = $null
if (Test-Path -LiteralPath $stagedReport) {
    try {
        $stagedHash = (Get-FileHash -LiteralPath $stagedReport -Algorithm SHA256).Hash
        Write-Log "Staged report    : present ($stagedReport)"
        Write-Log "Staged hash      : $($stagedHash.Substring(0,16))..."
    } catch { Write-Log "Staged report    : present but hash failed: $_" }
} else {
    Write-Log "Staged report    : ABSENT at $stagedReport"
    Write-Log "             => the apply task has nothing to import; Ensure-Apps must have staged it."
}

$wouldBeFull = $false
if ($stagedHash) {
    if ($stagedHash -ne $storedHash) { $wouldBeFull = $true }
    elseif ($storedStatus -ne 'success') { $wouldBeFull = $true }
}
Write-Log ''
if ($stagedHash) {
    if ($wouldBeFull) {
        Write-Log "FORCED APPLY     : would be a genuine FULL apply (hash mismatch or status != success)"
        Write-Log "             => good - triggering it reproduces the real break."
    } else {
        Write-Log "FORCED APPLY     : would currently be a NO-OP (hash matches AND status = success)"
        Write-Log "             => this box has ALREADY had its full apply; to reproduce the break"
        Write-Log "                Step 3 must clear ReportHash first to force a fresh full apply."
    }
} else {
    Write-Log "FORCED APPLY     : cannot evaluate (no staged report)."
}

# -----------------------------------------------------------------------------
# 4. Apps bootstrap state - what "Verify Bootstrap Apps failed" reports
# -----------------------------------------------------------------------------
Write-Section '4. Apps bootstrap state (HKLM ...\Apps) - the Verify-Apps drift'
try {
    $subs = Get-ChildItem -Path $appsKey -ErrorAction Stop
    foreach ($s in $subs) {
        $props = Get-ItemProperty -Path $s.PSPath -ErrorAction SilentlyContinue
        $kv = @()
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like 'PS*') { continue }
            $kv += "$($p.Name)=$($p.Value)"
        }
        Write-Log ("  {0,-22} {1}" -f $s.PSChildName, ($kv -join '  '))
    }
} catch { Write-Log "  (Apps key absent or unreadable: $_)" }

# -----------------------------------------------------------------------------
# 5. Scheduled tasks - are the install + apply tasks present, last result?
# -----------------------------------------------------------------------------
Write-Section '5. CustomizeWindowsSetup scheduled tasks'
foreach ($tn in 'Install-UserApps','Apply-HardenSystemSecurityReport') {
    try {
        $task = Get-ScheduledTask -TaskPath '\CustomizeWindowsSetup\' -TaskName $tn -ErrorAction Stop
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        Write-Log ("  {0,-34} State={1}  LastRun={2}  LastResult={3}" -f `
            $tn, $task.State, $info.LastRunTime, $info.LastTaskResult)
    } catch {
        Write-Log "  $tn : NOT REGISTERED ($_)"
    }
}

# -----------------------------------------------------------------------------
# 6. Printers - queues / drivers / ports / offline / PnP (vendors flagged)
# -----------------------------------------------------------------------------
Write-Section '6a. Printer queues (Get-Printer)'
try {
    Write-Block (Get-Printer -ErrorAction Stop |
        Select-Object Name, DriverName, PortName, Shared, PrinterStatus) 'Table'
} catch { Write-Log "ERROR Get-Printer: $_" }

Write-Section '6b. Win32_Printer (WorkOffline / status)'
try {
    Write-Block (Get-CimInstance Win32_Printer -ErrorAction Stop |
        Select-Object Name, WorkOffline, PrinterStatus, PortName, Default) 'Table'
} catch { Write-Log "ERROR Win32_Printer: $_" }

Write-Section '6c. Printer drivers (vendors flagged)'
try {
    $drivers = Get-PrinterDriver -ErrorAction Stop | ForEach-Object {
        $flag = ''
        if ($_.Name -match $vendorRegex -or $_.Manufacturer -match $vendorRegex) { $flag = '<<<' }
        [pscustomobject]@{ Flag=$flag; Name=$_.Name; Manufacturer=$_.Manufacturer }
    }
    Write-Block $drivers 'Table'
} catch { Write-Log "ERROR Get-PrinterDriver: $_" }

Write-Section '6d. Printer ports'
try {
    Write-Block (Get-PrinterPort -ErrorAction Stop |
        Select-Object Name, Description, PrinterHostAddress, PortNumber) 'Table'
} catch { Write-Log "ERROR Get-PrinterPort: $_" }

Write-Section '6e. PnP devices (printers + vendor devices, with health)'
try {
    $pnp = Get-PnpDevice -ErrorAction Stop | Where-Object {
        $_.Class -in 'Printer','PrintQueue' -or $_.FriendlyName -match $vendorRegex
    } | Select-Object Status, Class, FriendlyName
    if ($pnp) { Write-Block $pnp 'Table' } else { Write-Log '  (no matching PnP devices)' }
} catch { Write-Log "ERROR Get-PnpDevice: $_" }

# -----------------------------------------------------------------------------
# 7. Windows Protected Print Mode state
# -----------------------------------------------------------------------------
Write-Section '7. Windows Protected Print Mode (WPP)'
$wppPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP'
try {
    $wpp = (Get-ItemProperty -Path $wppPath -Name 'WindowsProtectedPrintMode' -ErrorAction Stop).WindowsProtectedPrintMode
    Write-Log "WindowsProtectedPrintMode = $wpp  ($(if ($wpp -eq 1) { 'ON - only IPP class-driver printers allowed' } else { 'OFF' }))"
} catch { Write-Log "WindowsProtectedPrintMode = (not set / OFF)" }

# -----------------------------------------------------------------------------
# 8. Existing Event 808 plug-in blocks - prove the box is currently CLEAN
# -----------------------------------------------------------------------------
Write-Section '8. Existing Event 808 plug-in blocks (baseline - expect ZERO/clean)'
$log808 = 'Microsoft-Windows-PrintService/Admin'
$has808Log = $false
try {
    $li = Get-WinEvent -ListLog $log808 -ErrorAction Stop
    if ($li -and $li.IsEnabled) { $has808Log = $true }
} catch { }
if (-not $has808Log) {
    Write-Log "  PrintService/Admin log not enabled or unreadable - cannot read 808 history."
} else {
    $blocks = @()
    try {
        $blocks = Get-WinEvent -FilterHashtable @{ LogName=$log808; Id=808 } -MaxEvents 200 -ErrorAction SilentlyContinue
    } catch { }
    if (-not $blocks -or $blocks.Count -eq 0) {
        Write-Log "  808 count: 0  -> CLEAN baseline (no plug-in blocks recorded). Ideal."
    } else {
        $dlls = @{}
        foreach ($e in $blocks) {
            $mm = [regex]::Match("$($e.Message)", '([A-Za-z0-9_\-]+\.dll)', 'IgnoreCase')
            if ($mm.Success) { $dlls[$mm.Groups[1].Value] = $true }
        }
        $sorted = $blocks | Sort-Object TimeCreated
        Write-Log "  808 count: $($blocks.Count)"
        Write-Log "  earliest : $($sorted[0].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Log "  latest   : $($sorted[-1].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Log "  modules  : $(($dlls.Keys | Sort-Object) -join ', ')"
        Write-Log "  NOTE: box already has 808 history - it may have partly hardened already."
    }
}

# -----------------------------------------------------------------------------
# 9. VERDICT
# -----------------------------------------------------------------------------
Write-Section '9. VERDICT - is this a valid end-to-end test box?'
$zebraPresent = $false
try {
    $zebraPresent = [bool](Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Zebra|ZDesigner' -or $_.DriverName -match 'Zebra|ZDesigner' })
} catch { }
Write-Log "24H2+ enforcer present : $is24H2"
Write-Log "Zebra queue present    : $zebraPresent"
Write-Log "HSS installed          : $([bool]$pkg)"
Write-Log "Forced apply = FULL    : $wouldBeFull"
Write-Log ''
if ($is24H2 -and $zebraPresent -and $wouldBeFull) {
    Write-Log "READ: GOOD test box. It's 24H2, has a Zebra queue, and a forced apply would be a"
    Write-Log "      real full apply. Proceed: run Step 2 (backup), then Step 3 (trigger + watch)."
} elseif ($is24H2 -and $zebraPresent -and -not $wouldBeFull -and $pkg) {
    Write-Log "READ: USABLE, but the box has already had its full apply (hash matches). Step 3 will"
    Write-Log "      need to clear ReportHash to force a fresh full apply. Back up first (Step 2)."
} elseif ($is24H2 -and $zebraPresent -and -not $pkg) {
    Write-Log "READ: USABLE but HSS isn't installed yet, so no apply can run. We'd need to install"
    Write-Log "      HSS first (or let the user-logon task land it) before Step 3 can break it."
} else {
    Write-Log "READ: WEAK test box for this hypothesis (missing 24H2, or no Zebra queue). Tell me the"
    Write-Log "      details above and we'll decide whether to use it or pick another."
}

Write-Section 'Baseline complete (read-only - no changes made)'
Write-Log "Transcript: $transcript"
Write-Log "Next: Step 2 backup (Test-ZebraApply-2-Backup.ps1) before anything destructive."
