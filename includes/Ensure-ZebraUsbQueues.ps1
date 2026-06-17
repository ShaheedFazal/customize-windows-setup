# Repairs missing Windows print queues for already-installed Zebra USB label
# printers. This intentionally does NOT install drivers and does NOT fall back
# to Generic / Text Only. Titan PMR profiles depend on stable Windows printer
# names, so the queue name is the matched ZDesigner driver name.

$sharedFunctions = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Shared-Functions.ps1' } else { $null }
if (-not (Get-Command -Name Write-Log -CommandType Function -ErrorAction SilentlyContinue) -and
    $sharedFunctions -and
    (Test-Path -LiteralPath $sharedFunctions)) {
    . $sharedFunctions
}

if (-not (Get-Command -Name Write-Log -CommandType Function -ErrorAction SilentlyContinue)) {
    function Write-Log {
        param([string]$Message)
        try {
            if (-not (Test-Path -LiteralPath 'C:\Temp')) {
                New-Item -Path 'C:\Temp' -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path 'C:\Temp\Customization.log' -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`t$Message"
        } catch {}
    }
}

if (-not (Get-Command -Name Test-MachineWideSentinel -CommandType Function -ErrorAction SilentlyContinue)) {
    function Test-MachineWideSentinel {
        param([Parameter(Mandatory)][string]$Name)
        return $false
    }
}

if (Test-MachineWideSentinel -Name 'Ensure-ZebraUsbQueues') { return }

function Get-ZebraModelToken {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $patterns = @(
        'GK\d{3}\w*'
        'GX\d{3}\w*'
        'GC\d{3}\w*'
        'ZD\d{3}[\w-]*'
        'ZT\d{3}[\w-]*'
        'ZQ\d{3}[\w-]*'
        'LP\s*\d+'
        'TLP\s*\d+'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return ($match.Value -replace '\s+', '').ToUpperInvariant()
        }
    }

    return $null
}

function Get-BestZebraDriver {
    param(
        [Parameter(Mandatory)]$Port,
        [Parameter(Mandatory)][array]$Drivers
    )

    $portText = @($Port.Name, $Port.Description, $Port.PrinterHostAddress) -join ' '
    $token = Get-ZebraModelToken -Text $portText

    if ($token) {
        $matches = @($Drivers | Where-Object {
            (($_.Name -replace '\s+', '').ToUpperInvariant()).Contains($token)
        })
        if ($matches.Count -eq 1) { return $matches[0] }
        if ($matches.Count -gt 1) {
            return $matches | Sort-Object Name | Select-Object -First 1
        }
    }

    if ($Drivers.Count -eq 1) { return $Drivers[0] }

    return $null
}

$printers = @(Get-Printer -ErrorAction SilentlyContinue)
$drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'ZDesigner|Zebra' })
$ports = @(Get-PrinterPort -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^USB\d+' -and
        ($_.Description -match 'Zebra|ZDesigner|ZTC' -or $_.Name -match 'Zebra|ZDesigner')
    })

if ($ports.Count -eq 0) {
    return
} elseif ($drivers.Count -eq 0) {
    $portList = ($ports | Select-Object -ExpandProperty Name) -join ', '
    Write-Host "[WARN] Zebra USB port(s) found ($portList) but no ZDesigner/Zebra driver is installed; install the Zebra driver first." -ForegroundColor Yellow
    Write-Log "WARN: Ensure-ZebraUsbQueues found Zebra USB port(s) ($portList) but no installed Zebra driver"
} else {
    foreach ($port in $ports) {
        $existingOnPort = @($printers | Where-Object { $_.PortName -eq $port.Name })
        if ($existingOnPort.Count -gt 0) {
            Write-Host "[INFO] Zebra USB port '$($port.Name)' already has queue '$($existingOnPort[0].Name)'; leaving unchanged." -ForegroundColor DarkGray
            Write-Log "Ensure-ZebraUsbQueues: port '$($port.Name)' already has queue '$($existingOnPort[0].Name)'"
            continue
        }

        $driver = Get-BestZebraDriver -Port $port -Drivers $drivers
        if (-not $driver) {
            Write-Host "[WARN] Zebra USB port '$($port.Name)' found but no unambiguous matching driver; skipping." -ForegroundColor Yellow
            Write-Log "WARN: Ensure-ZebraUsbQueues no unambiguous driver for port '$($port.Name)' description '$($port.Description)'"
            continue
        }

        $queueName = $driver.Name
        $existingByName = Get-Printer -Name $queueName -ErrorAction SilentlyContinue
        if ($existingByName) {
            Write-Host "[WARN] Queue '$queueName' already exists on port '$($existingByName.PortName)', not reusing name for '$($port.Name)'." -ForegroundColor Yellow
            Write-Log "WARN: Ensure-ZebraUsbQueues queue '$queueName' already exists on '$($existingByName.PortName)', skipped port '$($port.Name)'"
            continue
        }

        try {
            Add-Printer -Name $queueName -DriverName $driver.Name -PortName $port.Name -ErrorAction Stop
            Write-Host "[SUCCESS] Created Zebra queue '$queueName' on '$($port.Name)'." -ForegroundColor Green
            Write-Log "Ensure-ZebraUsbQueues: created queue '$queueName' driver '$($driver.Name)' port '$($port.Name)'"
            $printers = @(Get-Printer -ErrorAction SilentlyContinue)
        } catch {
            Write-Host "[ERROR] Failed to create Zebra queue '$queueName' on '$($port.Name)': $_" -ForegroundColor Red
            Write-Log "ERROR: Ensure-ZebraUsbQueues failed queue '$queueName' port '$($port.Name)' - $_"
        }
    }
}
