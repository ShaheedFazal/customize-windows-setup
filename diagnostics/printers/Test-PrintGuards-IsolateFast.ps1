<#
.SYNOPSIS
    FAST isolation of which HSS print guard blocks the Zebra driver. No PrintBrm.
    Uses the Zebra queue as a canary: a plain spooler restart does NOT delete the
    queue, it just fails to load the driver and logs Event 808 / 0x679. So we
    enable ONE guard at a time, restart the spooler, and watch for the Zebra 808.

.DESCRIPTION
    Per guard (others off): set guard=1, restart spooler, wait 15s, count NEW 808
    blocks naming a Zebra module (zdn* / ZDesigner). A guard that produces the
    Zebra 808 is the one blocking the driver. No restore needed between guards -
    the queue persists across a plain restart.

    Leaves the box HARDENED (all four guards = 1) at the end. Backs up the
    current guard values first to C:\Install\PrintGuards-Restore-<host>-<stamp>.json.

    SCOPE: this isolates the Zebra DRIVER-LOAD block (the logged 808). The WSD
    Brother *silent queue removal* does NOT log an 808 and likely only happens
    during a full apply, so it is NOT covered here - that's a separate test.

    Runtime: ~2-3 minutes (4 x restart+wait), vs ~20 min for the PrintBrm version.

.NOTES
    Elevated admin PowerShell on the box. PS 5.1-safe. Self-contained.
#>

$ErrorActionPreference = 'Continue'

$logDir = 'C:\Temp'; $installDir = 'C:\Install'
foreach ($d in $logDir,$installDir) { if (-not (Test-Path -LiteralPath $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null } }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$transcript = Join-Path $logDir "PrintGuards-IsolateFast-$env:COMPUTERNAME.log"
$restoreFile= Join-Path $installDir "PrintGuards-Restore-$env:COMPUTERNAME-$stamp.json"
function Write-Log { param([string]$m) Write-Host $m; try { Add-Content -LiteralPath $transcript -Value $m -Encoding UTF8 } catch {} }
function Write-Section { param([string]$t) Write-Log ''; Write-Log ('=' * 78); Write-Log "== $t"; Write-Log ('=' * 78) }
function Write-Block { param($o) if ($null -eq $o){Write-Log '  (none)';return}; foreach($l in (($o|Format-Table -AutoSize|Out-String -Width 4096) -split "`r?`n")){ if($l.TrimEnd()){Write-Log $l.TrimEnd()} } }
try { Remove-Item -LiteralPath $transcript -ErrorAction SilentlyContinue } catch {}

$zebraRegex = 'Zebra|ZDesigner|ZDN'
$vendorRegex= 'Epson|Zebra|ZDesigner|ZDN|Brother|BRU|Star|TSP|TM-'
$log808     = 'Microsoft-Windows-PrintService/Admin'

$guards = @(
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';               Name='RedirectionguardPolicy';                    Label='1. RedirectionGuard' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers';               Name='CopyFilesPolicy';                           Label='2. CopyFiles (CVE-2021-36958)' }
    [pscustomobject]@{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'; Name='RestrictDriverInstallationToAdministrators'; Label='3. RestrictDriverInstall (CVE-2021-34481)' }
    [pscustomobject]@{ Path='HKLM:\SYSTEM\CurrentControlSet\Control\Print';                        Name='RpcAuthnLevelPrivacyEnabled';               Label='4. RpcAuthnPrivacy (CVE-2021-1678)' }
)

function Get-PrinterSnapshot { try { return @(Get-Printer -ErrorAction Stop | Select-Object Name,DriverName,PortName,PrinterStatus) } catch { return @() } }
function Get-New808 { param([datetime]$Since) try { return @(Get-WinEvent -FilterHashtable @{LogName=$log808;Id=808;StartTime=$Since} -ErrorAction SilentlyContinue | Sort-Object TimeCreated) } catch { return @() } }
function Set-Guard { param($G,[int]$V) try { if(-not(Test-Path -LiteralPath $G.Path)){New-Item -Path $G.Path -Force|Out-Null}; New-ItemProperty -Path $G.Path -Name $G.Name -Value $V -PropertyType DWord -Force|Out-Null } catch { Write-Log "  ERROR $($G.Name)=$V : $_" } }
function Set-AllGuards { param([int]$V) foreach($g in $guards){ Set-Guard -G $g -V $V } }
function Restart-Spool { try { Restart-Service -Name Spooler -Force -ErrorAction Stop } catch { Write-Log "  WARNING spooler restart: $_" } }

Write-Log "Print-guard FAST isolation (Zebra 808 canary, no PrintBrm)"
Write-Log "Host        : $env:COMPUTERNAME"
Write-Log "Run (local) : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Back up current guard values
$restore=@()
foreach($g in $guards){
    $existed=$false;$prior=$null
    try { $item=Get-ItemProperty -Path $g.Path -Name $g.Name -ErrorAction Stop; $existed=$true; $prior=$item.$($g.Name) } catch {}
    $restore += [pscustomobject]@{Path=$g.Path;Name=$g.Name;Existed=$existed;PriorValue=$prior}
}
try { $restore | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $restoreFile -Encoding UTF8; Write-Log "Backed up guard state -> $restoreFile" } catch {}

# Confirm the Zebra canary is present
$pre = Get-PrinterSnapshot
$zebra = @($pre | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
Write-Log ""
Write-Log "Zebra canary queue(s): $($zebra.Count)"
foreach($z in $zebra){ Write-Log "  - $($z.Name) [$($z.DriverName)] port=$($z.PortName) status=$($z.PrinterStatus)" }
if ($zebra.Count -eq 0) {
    Write-Log "ABORT: no Zebra queue present to use as the canary. Restore the Zebra first (Step 4)."
    return
}

# Sweep
$results=@()
foreach($g in $guards){
    Write-Section "Testing $($g.Label)"
    Set-AllGuards -V 0
    Set-Guard -G $g -V 1
    $mark = Get-Date
    Write-Log "Enabled ONLY $($g.Name)=1, restarting spooler + waiting 15s..."
    Restart-Spool
    Start-Sleep -Seconds 15

    $new = Get-New808 -Since $mark
    $zebraBlocks = @()
    foreach($e in $new){
        $mm=[regex]::Match("$($e.Message)",'([A-Za-z0-9_\-]+\.dll)','IgnoreCase')
        $cm=[regex]::Match("$($e.Message)",'0x[0-9A-Fa-f]+')
        $dll=if($mm.Success){$mm.Groups[1].Value}else{'?'}
        $code=if($cm.Success){$cm.Value}else{'?'}
        $isZ = ($dll -match $zebraRegex -or "$($e.Message)" -match $zebraRegex)
        if($isZ){ $zebraBlocks += "$dll($code)" }
        $flag= if($isZ){'  <<< ZEBRA'} elseif("$($e.Message)" -match $vendorRegex){'  <<< vendor'} else {''}
        Write-Log ("  {0}  {1,-22} code={2}{3}" -f $e.TimeCreated.ToString('HH:mm:ss'),$dll,$code,$flag)
    }
    $now = Get-PrinterSnapshot
    $zebraNow = @($now | Where-Object { $_.Name -match $zebraRegex -or $_.DriverName -match $zebraRegex })
    $zebraGone = ($zebraNow.Count -lt $zebra.Count)
    $broke = ($zebraBlocks.Count -gt 0 -or $zebraGone)
    Write-Log ""
    if($broke){ Write-Log "RESULT: $($g.Label) -> BLOCKS the Zebra ($($zebraBlocks.Count) zebra 808; queueGone=$zebraGone)" }
    else { Write-Log "RESULT: $($g.Label) -> no Zebra block (driver loaded clean, no 808)" }
    $results += [pscustomobject]@{ Guard=$g.Label; BlocksZebra=$broke; Zebra808=($zebraBlocks -join ' '); QueueGone=$zebraGone }
}

# Leave hardened
Write-Section 'Cleanup - re-enable all four guards (leave hardened)'
Set-AllGuards -V 1
Restart-Spool
Write-Log "All four guards = 1. Box hardened."

Write-Section 'SUMMARY - which guard blocks the Zebra'
Write-Block ($results | Select-Object Guard,BlocksZebra,Zebra808,QueueGone)
$culprits=@($results | Where-Object { $_.BlocksZebra })
Write-Log ""
if($culprits.Count -eq 0){
    Write-Log "READ: NO single guard blocked the Zebra via a spooler restart. The Zebra 808 we saw"
    Write-Log "      during the full apply is therefore NOT caused by any one of these guards alone"
    Write-Log "      on restart - it's the full-apply mechanism / OS-level. Removing these guards"
    Write-Log "      will not stop the Zebra block."
} elseif($culprits.Count -eq 1){
    Write-Log "READ: ONE guard blocks the Zebra: $($culprits[0].Guard). That single guard is the"
    Write-Log "      lever - removing just it (keeping the other three) is the minimal-cost fix to"
    Write-Log "      validate against a full apply."
} else {
    Write-Log "READ: $($culprits.Count) guards block the Zebra: $((($culprits|ForEach-Object{$_.Guard}) -join '; '))."
}

Write-Section 'Fast isolation complete'
Write-Log "Transcript: $transcript"
