<#
.SYNOPSIS
    Inspect the saved print settings (DEVMODE) of Zebra label queues: the
    queue-wide Printing Defaults AND every signed-in user's own Printing
    Preferences. Optionally saves a technician-confirmed known-good baseline.

.DESCRIPTION
    Background: PrintService/Admin Event 318 ("Failed to upgrade printer
    settings ... set to those configured by the manufacturer") resets a
    queue's DEVMODE to the driver default. For ZDesigner that is 4x6in, which
    sends LABEL LENGTH ~1219 dots to a printer loaded with 104 x 76.2 mm stock
    and puts it into media-out. See ZEBRA-DEVMODE-GUARD-DESIGN.md.

    For each queue whose name or driver matches -QueueMatch this reports:
      - driver name + version, port, job count and job states
      - Printing Defaults: the global DEVMODE from
        HKLM\SYSTEM\CurrentControlSet\Control\Print\Printers\<queue>\Default DevMode,
        decoded (paper width x length in mm, form name, driver version field)
      - Get-PrintConfiguration PaperSize + PrintTicket PageMediaSize (microns)
      - per-user Printing Preferences for every LOADED user hive:
        HKU\<SID>\Printers\DevModePerUser\<queue> and ...\DevModes2\<queue>.
        These override the queue defaults for that user (Titan prints as
        MyLocalChemist). Profiles that are not signed in cannot be read
        without loading their hive, which this script does not do; they are
        listed so you know what was NOT checked.
      - Event 318 for the queue in the last 30 days

    A decoded size of 101.6 x 152.4 mm (4x6in) is flagged DRIVER-DEFAULT.

    Default mode is READ-ONLY.

    -SaveBaseline writes files only (no printer, driver, queue or registry
    change) to C:\ProgramData\CustomizeWindowsSetup\PrinterSettings\<queue>\:
      global-gd.dat        printui /Ss capture, flags g (global DEVMODE) and
                           d (printer data / driver-private settings)
      user-<SID>-DevModePerUser.bin / -DevModes2.bin   raw per-user blobs
      baseline.json        driver version, port, decoded sizes, hashes
    The folder is ACL'd to SYSTEM + Administrators only, because a SYSTEM
    restore would feed these blobs to the driver inside spoolsv.
    Run it ONLY after a correct label has printed from Titan. It refuses to
    save a queue whose Printing Defaults are still the driver default unless
    -AllowDriverDefaultSize is given.

.PARAMETER QueueMatch
    Regex matched against queue name and driver name. Default 'ZDesigner|Zebra'.

.PARAMETER SaveBaseline
    Save the known-good baseline described above.

.PARAMETER AllowDriverDefaultSize
    Save a baseline even when the Printing Defaults decode as 4x6in.

.NOTES
    Run elevated (SYSTEM via SuperOps, or an elevated admin shell).
    Self-contained. PS 5.1-safe. No automated tests (AGENTS.md).
    Unverified on a live box at time of writing: the first run on a
    known-good Zebra must confirm the decoded size reads 104.0 x 76.2 mm.
#>

param(
    [string]$QueueMatch = 'ZDesigner|Zebra',
    [switch]$SaveBaseline,
    [switch]$AllowDriverDefaultSize
)

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$transcript = Join-Path $logDir "ZebraPrinterSettings-$env:COMPUTERNAME.log"
function Write-Log {
    param([string]$m)
    Write-Host $m
    try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {
        Write-Host "WARN: failed to append to transcript '$transcript': $($_.Exception.Message)"
    }
}
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$baselineRoot = Join-Path $env:ProgramData 'CustomizeWindowsSetup\PrinterSettings'

# --- DEVMODEW decoding ---------------------------------------------------------
# Public DEVMODEW layout (offsets in bytes):
#   0 dmDeviceName WCHAR[32] | 64 dmSpecVersion | 66 dmDriverVersion | 68 dmSize
#   70 dmDriverExtra | 72 dmFields | 76 dmOrientation | 78 dmPaperSize
#   80 dmPaperLength (0.1 mm) | 82 dmPaperWidth (0.1 mm) | 102 dmFormName WCHAR[32]
function ConvertFrom-DevMode {
    param([byte[]]$Bytes)
    if (-not $Bytes -or $Bytes.Length -lt 84) { return $null }
    $size = [BitConverter]::ToUInt16($Bytes, 68)
    $form = ''
    if ($Bytes.Length -ge 166 -and $size -ge 166) {
        $form = ([Text.Encoding]::Unicode.GetString($Bytes, 102, 64)).Split([char]0)[0]
    }
    $len = [BitConverter]::ToInt16($Bytes, 80)
    $wid = [BitConverter]::ToInt16($Bytes, 82)
    $isDefault = (($wid -eq 1016 -and $len -eq 1524) -or ($wid -eq 1524 -and $len -eq 1016))
    [pscustomobject]@{
        DeviceName    = ([Text.Encoding]::Unicode.GetString($Bytes, 0, 64)).Split([char]0)[0]
        SpecVersion   = '0x{0:X4}' -f [BitConverter]::ToUInt16($Bytes, 64)
        DriverVersion = '0x{0:X4}' -f [BitConverter]::ToUInt16($Bytes, 66)
        Size          = $size
        DriverExtra   = [BitConverter]::ToUInt16($Bytes, 70)
        Fields        = '0x{0:X8}' -f [BitConverter]::ToUInt32($Bytes, 72)
        Orientation   = [BitConverter]::ToInt16($Bytes, 76)
        PaperSize     = [BitConverter]::ToInt16($Bytes, 78)
        WidthMm       = [math]::Round($wid / 10.0, 1)
        LengthMm      = [math]::Round($len / 10.0, 1)
        FormName      = $form
        DriverDefault = $isDefault
        TotalBytes    = $Bytes.Length
    }
}
function Format-DevMode {
    param($D)
    if (-not $D) { return '(absent or too short to decode)' }
    $flag = if ($D.DriverDefault) { '  <-- DRIVER-DEFAULT 4x6in' } else { '' }
    return ("{0} x {1} mm  form='{2}'  paperSize={3}  orient={4}  dmDriverVersion={5}  bytes={6}{7}" -f `
        $D.WidthMm, $D.LengthMm, $D.FormName, $D.PaperSize, $D.Orientation, $D.DriverVersion, $D.TotalBytes, $flag)
}
function Get-RegBinary {
    param([string]$Path, [string]$Name)
    try {
        $v = (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name
        if ($v -is [byte[]]) { return $v }
    } catch {}
    return $null
}
function Get-DriverVersionText {
    param($Raw)
    try {
        $v = [uint64]$Raw
        return '{0}.{1}.{2}.{3}' -f (($v -shr 48) -band 0xFFFF), (($v -shr 32) -band 0xFFFF), (($v -shr 16) -band 0xFFFF), ($v -band 0xFFFF)
    } catch { return "$Raw" }
}
function Get-SafeName { param([string]$Name) return ($Name -replace '[\\/:*?"<>|,]', '_') }
function Get-Sha256 { param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '') } finally { $sha.Dispose() }
}

Write-Log "Zebra printer settings inspection"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   as $env:USERDOMAIN\$env:USERNAME"
Write-Log "Mode        : $(if ($SaveBaseline) { 'SAVE BASELINE (writes files only)' } else { 'read-only' })"

# --- Loaded user hives (per-user preferences live here) ----------------------
$userHives = @()
try {
    $userHives = @(Get-ChildItem -LiteralPath 'Registry::HKEY_USERS' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' } |
        ForEach-Object {
            $sid = $_.PSChildName
            $acct = $sid
            try { $acct = (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value } catch {}
            [pscustomobject]@{ Sid = $sid; Account = $acct }
        })
} catch {
    Write-Log "WARN: cannot enumerate HKEY_USERS: $($_.Exception.Message)"
}
$loadedSids = @($userHives | Select-Object -ExpandProperty Sid)
$notLoaded = @()
try {
    $notLoaded = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop |
        Where-Object { $_.PSChildName -match '^S-1-5-21-[\d-]+$' -and $_.PSChildName -notin $loadedSids } |
        ForEach-Object {
            $p = (Get-ItemProperty -LiteralPath $_.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
            "$($_.PSChildName) ($p)"
        })
} catch {}

Write-Section 'User hives'
Write-Log "Loaded (checked)    : $(if ($userHives) { ($userHives | ForEach-Object { "$($_.Account) [$($_.Sid)]" }) -join '; ' } else { '(none)' })"
Write-Log "Not loaded (NOT checked - user not signed in): $(if ($notLoaded) { $notLoaded -join '; ' } else { '(none)' })"

# --- Queues ------------------------------------------------------------------
$queues = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $QueueMatch -or $_.DriverName -match $QueueMatch })
if ($queues.Count -eq 0) {
    Write-Log ''
    Write-Log "No queue matches '$QueueMatch'. Nothing to inspect."
    return
}

$resets = @()
try {
    $resets = @(Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-PrintService/Admin'; Id=318; StartTime=(Get-Date).AddDays(-30) } -ErrorAction Stop)
} catch {
    if ($_.Exception.Message -notmatch 'No events were found') { Write-Log "WARN: Event 318 query failed: $($_.Exception.Message)" }
}

foreach ($q in $queues) {
    Write-Section "Queue: $($q.Name)"
    $drv = Get-PrinterDriver -Name $q.DriverName -ErrorAction SilentlyContinue | Select-Object -First 1
    $drvVer = if ($drv) { Get-DriverVersionText $drv.DriverVersion } else { '?' }
    Write-Log "Driver        : $($q.DriverName)  v$drvVer"
    Write-Log "Port          : $($q.PortName)   Status: $($q.PrinterStatus)   Shared: $($q.Shared)"

    $jobs = @(Get-PrintJob -PrinterName $q.Name -ErrorAction SilentlyContinue)
    Write-Log "Jobs in queue : $($jobs.Count)"
    foreach ($j in ($jobs | Select-Object -First 5)) {
        Write-Log ("    #{0}  {1}  owner={2}  submitted={3}  status={4}" -f $j.Id, $j.DocumentName, $j.UserName, $j.SubmittedTime, $j.JobStatus)
    }

    # Printing Defaults (global DEVMODE)
    $regKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\' + ($q.Name -replace '\\', ',')
    $globalBytes = Get-RegBinary $regKey 'Default DevMode'
    $global = ConvertFrom-DevMode $globalBytes
    Write-Log "Printing Defaults (Default DevMode) : $(Format-DevMode $global)"

    try {
        $pc = Get-PrintConfiguration -PrinterName $q.Name -ErrorAction Stop
        $w = [regex]::Match("$($pc.PrintTicketXML)", 'MediaSizeWidth".*?<psf:Value[^>]*>(\d+)<', 'Singleline')
        $h = [regex]::Match("$($pc.PrintTicketXML)", 'MediaSizeHeight".*?<psf:Value[^>]*>(\d+)<', 'Singleline')
        $tk = if ($w.Success -and $h.Success) { '{0} x {1} mm' -f ([int]$w.Groups[1].Value / 1000), ([int]$h.Groups[1].Value / 1000) } else { '(no PageMediaSize in ticket)' }
        Write-Log "Get-PrintConfiguration              : PaperSize=$($pc.PaperSize)  ticket=$tk"
    } catch {
        Write-Log "Get-PrintConfiguration              : failed - $($_.Exception.Message)"
    }

    # Per-user Printing Preferences
    $userResults = @()
    foreach ($u in $userHives) {
        foreach ($valueKey in @('DevModePerUser', 'DevModes2')) {
            $bytes = Get-RegBinary "Registry::HKEY_USERS\$($u.Sid)\Printers\$valueKey" $q.Name
            $decoded = ConvertFrom-DevMode $bytes
            $shown = if ($bytes) { Format-DevMode $decoded } else { '(none - user inherits Printing Defaults)' }
            Write-Log ("{0,-36}: {1}" -f "$($u.Account) $valueKey", $shown)
            if ($bytes) { $userResults += [pscustomobject]@{ Sid = $u.Sid; Account = $u.Account; Value = $valueKey; Bytes = $bytes; Decoded = $decoded } }
        }
    }

    $qResets = @($resets | Where-Object { "$($_.Message)" -like "*$($q.Name)*" })
    Write-Log "Event 318 (30d): $($qResets.Count)"
    foreach ($e in ($qResets | Select-Object -First 5)) {
        Write-Log ("    {0}  {1}" -f $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), (("$($e.Message)" -replace '\s+', ' ').Trim()))
    }

    $baselineFile = Join-Path (Join-Path $baselineRoot (Get-SafeName $q.Name)) 'baseline.json'
    if (Test-Path -LiteralPath $baselineFile) {
        try {
            $b = Get-Content -LiteralPath $baselineFile -Raw | ConvertFrom-Json
            $match = ($global -and $b.Global -and $global.WidthMm -eq $b.Global.WidthMm -and $global.LengthMm -eq $b.Global.LengthMm)
            Write-Log "Saved baseline: $($b.CapturedUtc) by $($b.CapturedBy), driver v$($b.DriverVersion), $($b.Global.WidthMm) x $($b.Global.LengthMm) mm -> Printing Defaults match baseline size: $match"
            if ($b.DriverVersion -ne $drvVer) { Write-Log "    WARN: driver version changed since baseline ($($b.DriverVersion) -> $drvVer). A restore from this baseline is NOT safe." }
        } catch { Write-Log "Saved baseline: unreadable - $($_.Exception.Message)" }
    } else {
        Write-Log "Saved baseline: none"
    }

    if (-not $SaveBaseline) { continue }

    # --- Save baseline (files only) ------------------------------------------
    if (-not $global) {
        Write-Log "SKIP baseline: Printing Defaults DEVMODE could not be read."
        continue
    }
    if ($global.DriverDefault -and -not $AllowDriverDefaultSize) {
        Write-Log "SKIP baseline: Printing Defaults are the 4x6in driver default. Fix and test-print first, or pass -AllowDriverDefaultSize if 4x6 is really this branch's stock."
        continue
    }

    $dir = Join-Path $baselineRoot (Get-SafeName $q.Name)
    try {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        # SYSTEM (S-1-5-18) and Administrators (S-1-5-32-544) only; SIDs keep it locale-independent.
        $null = & icacls.exe $baselineRoot /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
        if ($LASTEXITCODE -ne 0) { Write-Log "WARN: icacls on $baselineRoot returned $LASTEXITCODE" }
    } catch {
        Write-Log "ERROR: cannot create $dir - $($_.Exception.Message)"
        continue
    }

    $datPath = Join-Path $dir 'global-gd.dat'
    Remove-Item -LiteralPath $datPath -ErrorAction SilentlyContinue
    # Start-Process joins -ArgumentList with spaces WITHOUT quoting, so queue
    # names with spaces must be quoted by hand. /q suppresses error dialogs
    # (a modal dialog in a hidden session would hang). Flags go last.
    $printUiArgs = "printui.dll,PrintUIEntry /Ss /n `"$($q.Name)`" /a `"$datPath`" /q g d"
    try {
        $p = Start-Process -FilePath 'rundll32.exe' -ArgumentList $printUiArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        Write-Log "printui /Ss exit=$($p.ExitCode) (rundll32 exit codes are not meaningful; checking the file)"
    } catch {
        Write-Log "ERROR: printui /Ss failed to start - $($_.Exception.Message)"
    }
    $datInfo = $null
    if (Test-Path -LiteralPath $datPath) {
        $datInfo = Get-Item -LiteralPath $datPath
        Write-Log "Saved $datPath ($($datInfo.Length) bytes)"
    } else {
        Write-Log "ERROR: printui did not write $datPath (blocked by App Control? wrong queue name?)"
    }

    $userMeta = @()
    foreach ($r in $userResults) {
        $binPath = Join-Path $dir ("user-{0}-{1}.bin" -f $r.Sid, $r.Value)
        try {
            [IO.File]::WriteAllBytes($binPath, $r.Bytes)
            $userMeta += [ordered]@{
                Sid = $r.Sid; Account = $r.Account; Value = $r.Value; File = (Split-Path $binPath -Leaf)
                Sha256 = (Get-Sha256 $r.Bytes); WidthMm = $r.Decoded.WidthMm; LengthMm = $r.Decoded.LengthMm
                FormName = $r.Decoded.FormName; DriverDefault = $r.Decoded.DriverDefault
            }
            Write-Log "Saved $binPath"
        } catch {
            Write-Log "ERROR: cannot write $binPath - $($_.Exception.Message)"
        }
    }

    $meta = [ordered]@{
        Queue         = $q.Name
        Driver        = $q.DriverName
        DriverVersion = $drvVer
        Port          = $q.PortName
        Host          = $env:COMPUTERNAME
        CapturedUtc   = (Get-Date).ToUniversalTime().ToString('o')
        CapturedBy    = "$env:USERDOMAIN\$env:USERNAME"
        PrintUiFile   = if ($datInfo) { $datInfo.Name } else { $null }
        PrintUiFlags  = 'g d'
        Global        = [ordered]@{
            WidthMm = $global.WidthMm; LengthMm = $global.LengthMm; FormName = $global.FormName
            PaperSize = $global.PaperSize; DriverVersionField = $global.DriverVersion
            Sha256 = (Get-Sha256 $globalBytes)
        }
        Users         = $userMeta
    }
    try {
        $meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'baseline.json') -Encoding UTF8
        Write-Log "Saved $(Join-Path $dir 'baseline.json')"
    } catch {
        Write-Log "ERROR: cannot write baseline.json - $($_.Exception.Message)"
    }
}

Write-Section 'Done'
if (-not $SaveBaseline) { Write-Log 'Read-only run - no changes made.' }
Write-Log "Transcript: $transcript"
