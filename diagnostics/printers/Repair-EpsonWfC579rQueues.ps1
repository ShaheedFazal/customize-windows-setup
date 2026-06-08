<#
.SYNOPSIS
    Safely repairs the Titan Epson WF-C579R logical queues A4 and Token.

.DESCRIPTION
    This script is intended for one-by-one use on Epson-connected endpoints.
    It does not run as part of the normal customize-windows-setup include chain.

    Safe behaviour:
      - Does not run HSS.
      - Does not enable Windows Protected Print.
      - Does not remove any printer queues unless -RemoveSurplusEpsonQueues is
        explicitly supplied.
      - Requires an installed EPSON WF-C579R Series driver.
      - Prefers an EpsonNet/IP-style port over WSD when one is available.
      - Creates missing A4 and Token queues.
      - Replays saved Epson DEVMODE blobs for tray/paper defaults when present.

    Expected Titan queues:
      - A4    -> Cassette 1, A4 paper.
      - Token -> Cassette 2, token/custom paper size.

.PARAMETER PreferredPortName
    Optional explicit port name, e.g. 192.168.1.29:WF-C579R. Use this when a
    machine has more than one Epson port and automatic selection is ambiguous.

.PARAMETER RemoveSurplusEpsonQueues
    Optional cleanup mode. Only removes surplus Epson WF-C579R queues after both
    A4 and Token exist. Defaults to off.

.NOTES
    Run from elevated PowerShell. PS 5.1 and PowerShell 7 compatible.
#>

param(
    [string]$DriverName = 'EPSON WF-C579R Series',
    [string]$PreferredPortName = '',
    [switch]$RemoveSurplusEpsonQueues,
    [switch]$SkipSavedSettings
)

$ErrorActionPreference = 'Continue'

$LogDir = 'C:\Temp'
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogDir "Repair-EpsonWfC579rQueues-$env:COMPUTERNAME-$Stamp.log"

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    try {
        Add-Content -LiteralPath $LogPath -Value $Message -Encoding UTF8
    } catch {
        Write-Host "WARN: failed to append to log '$LogPath': $($_.Exception.Message)"
    }
}

function Write-Section {
    param([string]$Title)
    Write-Log ''
    Write-Log ('=' * 78)
    Write-Log "== $Title"
    Write-Log ('=' * 78)
}

function Show-Table {
    param($InputObject)
    if ($null -eq $InputObject) {
        Write-Log '  (none)'
        return
    }
    $Text = $InputObject | Format-Table -AutoSize | Out-String -Width 4096
    foreach ($Line in ($Text -split "`r?`n")) {
        if ($Line.TrimEnd()) { Write-Log $Line.TrimEnd() }
    }
}

function Get-WppState {
    $PolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\WPP'
    $LocalPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Print\WPP'
    $Policy = $null
    $Local = $null
    try { $Policy = (Get-ItemProperty -LiteralPath $PolicyPath -Name WindowsProtectedPrintMode -ErrorAction Stop).WindowsProtectedPrintMode } catch {}
    try { $Local = (Get-ItemProperty -LiteralPath $LocalPath -Name WindowsProtectedPrintMode -ErrorAction Stop).WindowsProtectedPrintMode } catch {}
    [pscustomobject]@{
        Policy = $Policy
        Local = $Local
        Effective = if ($null -ne $Local) { $Local } elseif ($null -ne $Policy) { $Policy } else { 0 }
    }
}

function Resolve-EpsonPort {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        $Explicit = Get-PrinterPort -Name $Preferred -ErrorAction SilentlyContinue
        if ($Explicit) { return $Explicit.Name }
        Write-Log "ERROR: preferred port '$Preferred' was not found."
        return $null
    }

    $ExistingEpsonQueues = @(Get-Printer -ErrorAction SilentlyContinue |
        Where-Object { $_.DriverName -eq $DriverName -or $_.Name -match 'EPSON|WF-C579R|^A4$|^Token$' })

    $ExistingGoodPortNames = @($ExistingEpsonQueues |
        Where-Object { $_.PortName -match 'WF-C579R|EPSON|^\d{1,3}(\.\d{1,3}){3}' } |
        Select-Object -ExpandProperty PortName -Unique)

    if ($ExistingGoodPortNames.Count -eq 1) {
        return $ExistingGoodPortNames[0]
    }

    $Ports = @(Get-PrinterPort -ErrorAction SilentlyContinue)

    $EpsonNetPorts = @($Ports | Where-Object {
        $_.Description -match 'EpsonNet|EPSON|WF-C579R' -or
        $_.Name -match 'WF-C579R|EPSON|^\d{1,3}(\.\d{1,3}){3}'
    })

    $PreferredEpsonNet = @($EpsonNetPorts | Where-Object {
        $_.Description -match 'EpsonNet' -or $_.Name -match '^\d{1,3}(\.\d{1,3}){3}'
    })

    if ($PreferredEpsonNet.Count -eq 1) {
        return $PreferredEpsonNet[0].Name
    }

    if ($EpsonNetPorts.Count -eq 1) {
        return $EpsonNetPorts[0].Name
    }

    $WsdPorts = @($Ports | Where-Object { $_.Name -match '^WSD-' -and $_.Description -match 'WSD' })
    if ($WsdPorts.Count -eq 1) {
        Write-Log "WARN: only a WSD port was found; using '$($WsdPorts[0].Name)'. EpsonNet/IP is preferred where available."
        return $WsdPorts[0].Name
    }

    Write-Log 'ERROR: could not choose a unique Epson port. Re-run with -PreferredPortName.'
    Write-Log 'Candidate ports:'
    Show-Table ($Ports | Where-Object {
        $_.Name -match 'WSD|WF-C579R|EPSON|^\d{1,3}(\.\d{1,3}){3}' -or
        $_.Description -match 'WSD|Epson|WF-C579R'
    } | Select-Object Name, PrinterHostAddress, Description)
    return $null
}

function Ensure-Queue {
    param(
        [string]$Name,
        [string]$Driver,
        [string]$Port
    )

    $Queue = Get-Printer -Name $Name -ErrorAction SilentlyContinue
    if (-not $Queue) {
        try {
            Add-Printer -Name $Name -DriverName $Driver -PortName $Port -ErrorAction Stop
            Write-Log "SUCCESS: created queue '$Name' with driver '$Driver' on port '$Port'."
            return
        } catch {
            Write-Log "ERROR: failed to create queue '$Name': $($_.Exception.Message)"
            return
        }
    }

    Write-Log "INFO: queue '$Name' already exists: driver='$($Queue.DriverName)' port='$($Queue.PortName)' status='$($Queue.PrinterStatus)'."

    if ($Queue.DriverName -ne $Driver) {
        Write-Log "WARN: queue '$Name' uses unexpected driver '$($Queue.DriverName)'; leaving unchanged."
    }

    if ($Queue.PortName -ne $Port) {
        try {
            Set-Printer -Name $Name -PortName $Port -ErrorAction Stop
            Write-Log "SUCCESS: moved queue '$Name' from port '$($Queue.PortName)' to '$Port'."
        } catch {
            Write-Log "WARN: failed to move queue '$Name' to port '$Port': $($_.Exception.Message)"
        }
    }
}

function Restore-QueueSettings {
    param(
        [string]$QueueName,
        [string]$BlobName
    )

    if ($SkipSavedSettings) {
        Write-Log "INFO: skipped saved settings for '$QueueName' because -SkipSavedSettings was supplied."
        return
    }

    $ConfigPath = Join-Path $PSScriptRoot (Join-Path 'epson-configs' $BlobName)
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Log "WARN: saved settings blob not found for '$QueueName': $ConfigPath"
        return
    }

    try {
        $Process = Start-Process -FilePath 'rundll32.exe' `
            -ArgumentList @('printui.dll,PrintUIEntry', '/Sr', '/n', $QueueName, '/a', $ConfigPath, 'd', 'g') `
            -Wait -PassThru -WindowStyle Hidden

        if ($Process.ExitCode -eq 0) {
            Write-Log "SUCCESS: restored saved Epson tray settings for '$QueueName' from '$BlobName'."
        } else {
            Write-Log "WARN: printui returned exit code $($Process.ExitCode) restoring '$QueueName'. Check preferences manually."
        }
    } catch {
        Write-Log "WARN: failed to restore saved settings for '$QueueName': $($_.Exception.Message)"
    }
}

Write-Log "Repair Epson WF-C579R queues"
Write-Log "Host       : $env:COMPUTERNAME"
Write-Log "Run local  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Log        : $LogPath"

Write-Section '1. Safety checks'
$Wpp = Get-WppState
Write-Log "WPP policy=$($Wpp.Policy) local=$($Wpp.Local) effective=$($Wpp.Effective)"
if ($Wpp.Effective -eq 1) {
    Write-Log 'ERROR: Windows Protected Print appears enabled. Stop here; do not repair legacy Epson queues until WPP is off.'
    exit 30
}

$Driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
if (-not $Driver) {
    Write-Log "ERROR: required driver '$DriverName' is not installed. Install the Epson driver/printer first."
    exit 20
}
Write-Log "Found driver '$($Driver.Name)' version '$($Driver.DriverVersion)'."

$PortName = Resolve-EpsonPort -Preferred $PreferredPortName
if (-not $PortName) { exit 21 }
Write-Log "Selected Epson port: $PortName"

Write-Section '2. Before'
Show-Table (Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'EPSON|WF-C579R|^A4$|^Token$' -or $_.DriverName -eq $DriverName } |
    Select-Object Name, DriverName, PortName, PrinterStatus)

Write-Section '3. Ensure A4 and Token queues'
Ensure-Queue -Name 'A4' -Driver $DriverName -Port $PortName
Ensure-Queue -Name 'Token' -Driver $DriverName -Port $PortName

Write-Section '4. Apply saved tray settings'
Restore-QueueSettings -QueueName 'A4' -BlobName 'a4_epson_config.dat'
Restore-QueueSettings -QueueName 'Token' -BlobName 'token_epson_config.dat'

Write-Section '5. Optional surplus queue cleanup'
$Wanted = @('A4', 'Token')
$HaveWanted = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $Wanted })
$Surplus = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object {
    (
        $_.DriverName -eq $DriverName -or
        $_.Name -match 'EPSON|WF-C579R|Token Printer'
    ) -and
    $_.Name -notin $Wanted
})

if ($Surplus.Count -eq 0) {
    Write-Log 'No surplus Epson queues found in Get-Printer.'
} elseif (-not $RemoveSurplusEpsonQueues) {
    Write-Log 'Surplus Epson queues found, but not removed because cleanup is opt-in.'
    Show-Table ($Surplus | Select-Object Name, DriverName, PortName, PrinterStatus)
} elseif ($HaveWanted.Count -ne 2) {
    Write-Log "WARN: cleanup requested but skipped because A4/Token are not both present ($($HaveWanted.Count)/2)."
} else {
    Show-Table ($Surplus | Select-Object Name, DriverName, PortName, PrinterStatus)
    foreach ($Queue in $Surplus) {
        try {
            Remove-Printer -Name $Queue.Name -ErrorAction Stop
            Write-Log "SUCCESS: removed surplus queue '$($Queue.Name)'."
        } catch {
            Write-Log "WARN: failed to remove surplus queue '$($Queue.Name)': $($_.Exception.Message)"
        }
    }
}

Write-Section '6. After'
Show-Table (Get-Printer -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'EPSON|WF-C579R|^A4$|^Token$' -or $_.DriverName -eq $DriverName } |
    Select-Object Name, DriverName, PortName, PrinterStatus)

Write-Section '7. Public print configuration'
foreach ($QueueName in 'A4', 'Token') {
    Write-Log "-- $QueueName --"
    try {
        $Config = Get-PrintConfiguration -PrinterName $QueueName -ErrorAction Stop
        Write-Log ("  PaperSize={0} Color={1} Duplex={2}" -f $Config.PaperSize, $Config.Color, $Config.DuplexingMode)
        $Ticket = "$($Config.PrintTicketXML)"
        $InputBin = [regex]::Match($Ticket, '<psf:Feature name="psk:PageInputBin"><psf:Option name="([^"]+)"')
        $MediaSize = [regex]::Match($Ticket, '<psf:Feature name="psk:PageMediaSize"><psf:Option name="([^"]+)"')
        if ($InputBin.Success) { Write-Log "  PrintTicket PageInputBin=$($InputBin.Groups[1].Value)" }
        if ($MediaSize.Success) { Write-Log "  PrintTicket PageMediaSize=$($MediaSize.Groups[1].Value)" }
    } catch {
        Write-Log "  WARN: failed to read public print configuration: $($_.Exception.Message)"
    }
}

Write-Section '8. Manual verification still required'
Write-Log 'Print one real A4 document and one real Token job from Titan.'
Write-Log 'Windows may still show stale "driver unavailable" device entries; trust Get-Printer for real queues.'
Write-Log 'Done.'
