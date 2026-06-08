<#
.SYNOPSIS
    Read-only follow-up diagnostic: identify WHAT enforces Control Flow Guard (CFG)
    / Arbitrary Code Guard (ACG) on the print spooler, blocking legacy vendor
    plug-ins (Zebra ZDesignerui.dll = 0x679 CFG, Brother BRUIM15A.DLL = 0x677 ACG).
    Push site-wide via the SuperOps console.

.DESCRIPTION
    The first diagnostic (Diagnose-PrinterDriverBlock.ps1) established:
      - The blocked plug-in DLLs are present and validly Microsoft-WHQL-signed,
        so the CopyFiles / RedirectionGuard / signature printer policies are NOT
        the cause.
      - Event 808 reasons are CFG (0x679) and "prohibits dynamic code generation"
        / ACG (0x677) - process memory-integrity mitigations.
      - Get-ProcessMitigation showed CFG/signature/imageload = NOTSET on
        spoolsv.exe and PrintIsolationHost.exe (no Exploit-Protection override).

    So enforcement is coming from somewhere else. This script reads the layers that
    can require CFG-compatible images process-wide WITHOUT an IFEO entry, all of
    which the HSS / HotCakeX baseline can configure:
      1. VBS / HVCI (Memory Integrity) + user-mode Code Integrity enforcement state
      2. Smart App Control + WDAC / App Control active policies
      3. CodeIntegrity/Operational block/audit events
      4. System-wide kernel MitigationOptions
      5. FULL process-mitigation dump for the print binaries (incl. DynamicCode/ACG)
      6. PE header CFG flag of the actual blocked DLLs (is the DLL itself CFG-built?)

    ONLY READS. No registry/driver/printer/service/mitigation/policy changes.
    Writes to the console (SuperOps job log) and a transcript file.

.NOTES
    Pushed via SuperOps (runs as SYSTEM). Self-contained. No automated tests.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}
$transcript = Join-Path $logDir "PrinterCFGBlock-Diag-$env:COMPUTERNAME.log"

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    try { Add-Content -LiteralPath $transcript -Value $Message -Encoding UTF8 } catch {
        Write-Host "WARN: failed to append to transcript '$transcript': $($_.Exception.Message)"
    }
}
function Write-Section {
    param([string]$Title)
    Write-Log ''
    Write-Log ('=' * 78)
    Write-Log "== $Title"
    Write-Log ('=' * 78)
}
function Write-Block {
    param($InputObject, [string]$Format = 'List')
    if ($null -eq $InputObject) { return }
    if ($Format -eq 'Table') {
        $text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096
    } else {
        $text = $InputObject | Format-List * | Out-String -Width 4096
    }
    foreach ($line in ($text -split "`r?`n")) {
        if ($line.TrimEnd()) { Write-Log $line.TrimEnd() }
    }
}

try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {
    Write-Host "WARN: failed to reset transcript '$transcript': $($_.Exception.Message)"
}

Write-Log "Printer CFG/ACG enforcement diagnostic"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Transcript  : $transcript"

# -----------------------------------------------------------------------------
# 1. VBS / HVCI (Memory Integrity) + Code Integrity enforcement state.
#    UsermodeCodeIntegrityPolicyEnforcementStatus = 2 (enforced) is the smoking
#    gun for a WDAC UMCI policy blocking user-mode images.
# -----------------------------------------------------------------------------
Write-Section '1. Device Guard / VBS / HVCI / Code Integrity state'
try {
    $dg = Get-CimInstance -ClassName Win32_DeviceGuard `
        -Namespace 'root\Microsoft\Windows\DeviceGuard' -ErrorAction Stop
    $map = @{
        VirtualizationBasedSecurityStatus               = @{0='Off';1='Enabled-not-running';2='Running'}
        CodeIntegrityPolicyEnforcementStatus            = @{0='Off';1='Audit';2='Enforced'}
        UsermodeCodeIntegrityPolicyEnforcementStatus    = @{0='Off';1='Audit';2='Enforced'}
    }
    foreach ($p in 'VirtualizationBasedSecurityStatus','CodeIntegrityPolicyEnforcementStatus','UsermodeCodeIntegrityPolicyEnforcementStatus') {
        $v = $dg.$p
        $label = if ($map[$p].ContainsKey([int]$v)) { $map[$p][[int]$v] } else { '?' }
        Write-Log ("  {0,-46} = {1} ({2})" -f $p, $v, $label)
    }
    Write-Log ("  {0,-46} = {1}" -f 'SecurityServicesConfigured', ($dg.SecurityServicesConfigured -join ','))
    Write-Log ("  {0,-46} = {1}" -f 'SecurityServicesRunning',    ($dg.SecurityServicesRunning -join ','))
    Write-Log ("  {0,-46} = {1}" -f 'AvailableSecurityProperties',($dg.AvailableSecurityProperties -join ','))
    Write-Log "  (SecurityServices code 2 = HVCI / Memory Integrity)"
} catch {
    Write-Log "  ERROR reading Win32_DeviceGuard: $_"
}

# HVCI registry view + Memory Integrity (HypervisorEnforcedCodeIntegrity).
foreach ($pair in @(
    @('HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity','Enabled'),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard','EnableVirtualizationBasedSecurity'),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy','VerifiedAndReputablePolicyState')
)) {
    try {
        $val = (Get-ItemProperty -LiteralPath $pair[0] -Name $pair[1] -ErrorAction Stop).$($pair[1])
        Write-Log ("  {0}\{1} = {2}" -f $pair[0], $pair[1], $val)
    } catch {
        Write-Log ("  {0}\{1} = <not set>" -f $pair[0], $pair[1])
    }
}
Write-Log "  (VerifiedAndReputablePolicyState: 0=off, 1=Smart App Control ON, 2=evaluation)"

# -----------------------------------------------------------------------------
# 2. WDAC / App Control active policies on disk.
# -----------------------------------------------------------------------------
Write-Section '2. WDAC / App Control active policies'
$ciPaths = @(
    'C:\Windows\System32\CodeIntegrity\CiPolicies\Active',
    'C:\Windows\System32\CodeIntegrity'
)
foreach ($path in $ciPaths) {
    Write-Log "[$path]"
    try {
        $files = Get-ChildItem -LiteralPath $path -Include *.cip,*.p7b -Recurse -ErrorAction SilentlyContinue
        if ($files) {
            foreach ($f in $files) {
                Write-Log ("  {0,-46} {1}  {2} bytes" -f $f.Name, $f.LastWriteTime, $f.Length)
            }
        } else {
            Write-Log "  <no .cip / .p7b policies>"
        }
    } catch {
        Write-Log "  ERROR: $_"
    }
}

# -----------------------------------------------------------------------------
# 3. CodeIntegrity/Operational block + audit events (3033/3077 block, 3076 audit).
# -----------------------------------------------------------------------------
Write-Section '3. CodeIntegrity/Operational events (last 40)'
try {
    $ciEvents = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-CodeIntegrity/Operational'
    } -MaxEvents 40 -ErrorAction Stop
    if ($ciEvents) {
        foreach ($e in $ciEvents) {
            $msg = ($e.Message -split "`r?`n")[0]
            $mark = if ($e.Message -match 'ZDesigner|BRU|spool|print') { ' <<<' } else { '' }
            Write-Log ("{0}  Id={1,-5} [{2}]  {3}{4}" -f `
                $e.TimeCreated.ToString('MM-dd HH:mm:ss'), $e.Id, $e.LevelDisplayName, $msg, $mark)
        }
    } else {
        Write-Log "No CodeIntegrity/Operational events."
    }
} catch {
    Write-Log "No CodeIntegrity/Operational log or events: $_"
}

# -----------------------------------------------------------------------------
# 4. System-wide kernel process-mitigation options (bytes -> hex).
# -----------------------------------------------------------------------------
Write-Section '4. System-wide kernel MitigationOptions'
$kernelKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
foreach ($name in 'MitigationOptions','MitigationAuditOptions') {
    try {
        $raw = (Get-ItemProperty -LiteralPath $kernelKey -Name $name -ErrorAction Stop).$name
        if ($raw -is [byte[]]) {
            $hex = ($raw | ForEach-Object { $_.ToString('X2') }) -join ' '
            Write-Log ("  {0} = {1}" -f $name, $hex)
        } else {
            Write-Log ("  {0} = {1}" -f $name, $raw)
        }
    } catch {
        Write-Log ("  {0} = <not set>" -f $name)
    }
}

# -----------------------------------------------------------------------------
# 5. FULL process-mitigation dump for the print binaries (incl. DynamicCode/ACG).
# -----------------------------------------------------------------------------
Write-Section '5. Full Get-ProcessMitigation for print binaries'
if (-not (Get-Command Get-ProcessMitigation -ErrorAction SilentlyContinue)) {
    Write-Log "Get-ProcessMitigation not available."
} else {
    foreach ($name in 'spoolsv.exe','PrintIsolationHost.exe') {
        Write-Log ''
        Write-Log "-- $name (full) --"
        try {
            $m = Get-ProcessMitigation -Name $name -ErrorAction Stop
            foreach ($prop in $m.PSObject.Properties) {
                if ($null -ne $prop.Value -and $prop.Value.PSObject.Properties.Count -gt 0) {
                    Write-Log "  [$($prop.Name)]"
                    Write-Block $prop.Value 'List'
                }
            }
        } catch {
            Write-Log "  ERROR: $_"
        }
    }
}

# -----------------------------------------------------------------------------
# 6. Is the blocked DLL itself CFG-built? Read PE DllCharacteristics.
#    GUARD_CF (0x4000) set => CFG-enabled. If clear, strict-CFG enforcement
#    would reject it. (For comparison we also test a known CFG-enabled MS DLL.)
# -----------------------------------------------------------------------------
Write-Section '6. PE DllCharacteristics / CFG flag of blocked DLLs'
function Get-PeFlags {
    param([string]$Path)
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Seek(0x3C, 'Begin') | Out-Null
        $peOff = $br.ReadInt32()
        $fs.Seek($peOff, 'Begin') | Out-Null
        if ($br.ReadUInt32() -ne 0x00004550) { return $null }   # 'PE\0\0'
        $fs.Seek($peOff + 4 + 20, 'Begin') | Out-Null            # skip PE signature + full COFF header
        $magic = $br.ReadUInt16()                                # 0x10B PE32, 0x20B PE32+
        # DllCharacteristics is at optional-header offset 70 (0x46) for both.
        $fs.Seek($peOff + 24 + 70, 'Begin') | Out-Null
        $dllChar = $br.ReadUInt16()
        return [pscustomobject]@{
            Magic            = ('0x{0:X}' -f $magic)
            DllCharacteristics = ('0x{0:X4}' -f $dllChar)
            CFG              = (($dllChar -band 0x4000) -ne 0)
            HighEntropyVA    = (($dllChar -band 0x0020) -ne 0)
            DynamicBase_ASLR = (($dllChar -band 0x0040) -ne 0)
            NXCompat_DEP     = (($dllChar -band 0x0100) -ne 0)
        }
    } catch {
        return $null
    } finally {
        if ($fs) { $fs.Close() }
    }
}

$driverRoot = "$env:WINDIR\System32\spool\DRIVERS\x64\3"
$targets = @(
    (Join-Path $driverRoot 'ZDesignerui.dll'),
    (Join-Path $driverRoot 'BRUIM15A.DLL'),
    (Join-Path $driverRoot 'ZDesignerLM.dll'),
    "$env:WINDIR\System32\kernel32.dll"   # reference: should be CFG=True
)
foreach ($t in $targets) {
    Write-Log ''
    Write-Log "-- $t --"
    if (-not (Test-Path -LiteralPath $t)) { Write-Log "  not found"; continue }
    $flags = Get-PeFlags -Path $t
    if ($flags) {
        Write-Log ("  Magic={0}  DllCharacteristics={1}  CFG={2}  ASLR={3}  DEP={4}  HighEntropyVA={5}" -f `
            $flags.Magic, $flags.DllCharacteristics, $flags.CFG, $flags.DynamicBase_ASLR, $flags.NXCompat_DEP, $flags.HighEntropyVA)
    } else {
        Write-Log "  (could not parse PE header)"
    }
}

Write-Section 'Diagnostic complete (read-only - no changes made)'
Write-Log "Transcript saved to: $transcript"
