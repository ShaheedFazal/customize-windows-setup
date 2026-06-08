# Creates a local PrintBrm backup before the HSS scheduled-task apply is
# triggered. This is a safety net only: recovery is intentionally manual so a
# bad restore cannot mask a real issue or resurrect stale printer queues.

if (Test-MachineWideSentinel -Name 'A0-Backup-PrintersBeforeHSS') { return }

$backupRoot = 'C:\Install\PrinterBackups'
$brm = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'

if (-not (Test-Path -LiteralPath $brm)) {
    Write-Host "[WARN] PrintBrm.exe not found; skipping printer backup before HSS." -ForegroundColor Yellow
    Write-Log "WARN: A0-Backup-PrintersBeforeHSS skipped; PrintBrm.exe not found at '$brm'"
    return
}

$printers = @(Get-Printer -ErrorAction SilentlyContinue)
if ($printers.Count -eq 0) {
    Write-Log "A0-Backup-PrintersBeforeHSS: no printers found; skipping backup"
    return
}

$businessPrinters = @($printers | Where-Object {
    $_.DriverName -notmatch '^Microsoft ' -and
    $_.Name -notmatch '^Microsoft ' -and
    $_.Name -ne 'OneNote'
})

if ($businessPrinters.Count -eq 0) {
    Write-Log "A0-Backup-PrintersBeforeHSS: no third-party/business printers found; skipping backup"
    return
}

try {
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    }
} catch {
    Write-Host "[WARN] Could not create printer backup folder '$backupRoot': $_" -ForegroundColor Yellow
    Write-Log "WARN: A0-Backup-PrintersBeforeHSS could not create '$backupRoot' - $_"
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $backupRoot "PrinterBackup-$env:COMPUTERNAME-$stamp.printerExport"
$log = Join-Path $backupRoot "PrinterBackup-$env:COMPUTERNAME-$stamp.log"

Write-Host "[INFO] Backing up printers before HSS apply: $backup" -ForegroundColor Cyan
Write-Log "A0-Backup-PrintersBeforeHSS: starting PrintBrm backup to '$backup'"

try {
    & $brm -B -F $backup *> $log
    $exitCode = $LASTEXITCODE
} catch {
    Write-Host "[WARN] Printer backup failed: $_" -ForegroundColor Yellow
    Write-Log "WARN: A0-Backup-PrintersBeforeHSS PrintBrm threw - $_"
    return
}

if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $backup) -or (Get-Item -LiteralPath $backup).Length -lt 1KB) {
    Write-Host "[WARN] Printer backup did not complete cleanly; see $log" -ForegroundColor Yellow
    Write-Log "WARN: A0-Backup-PrintersBeforeHSS backup failed or empty; exit=$exitCode path='$backup'"
    return
}

Write-Host "[SUCCESS] Printer backup complete." -ForegroundColor Green
Write-Log "A0-Backup-PrintersBeforeHSS: backup complete '$backup'"

# Keep only the latest five printer backups per machine.
try {
    Get-ChildItem -LiteralPath $backupRoot -Filter "PrinterBackup-$env:COMPUTERNAME-*.printerExport" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 5 |
        ForEach-Object {
            $oldLog = [System.IO.Path]::ChangeExtension($_.FullName, '.log')
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $oldLog) {
                Remove-Item -LiteralPath $oldLog -Force -ErrorAction SilentlyContinue
            }
            Write-Log "A0-Backup-PrintersBeforeHSS: pruned old backup '$($_.FullName)'"
        }
} catch {
    Write-Log "WARN: A0-Backup-PrintersBeforeHSS pruning failed - $_"
}
