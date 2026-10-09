if (Test-MachineWideSentinel -Name 'Enable-PrintServiceLogging') { return }

# Turn on the PrintService Operational log so every job, queue add/remove and
# driver change leaves a record. Windows ships it disabled, which meant printer
# faults on branch PCs (e.g. PC16-FKW75, Oct 2026) left nothing to diagnose from.
# 20 MB keeps several weeks of history on a busy dispensary PC.

Write-Host "Enabling PrintService Operational log..."

$log = 'Microsoft-Windows-PrintService/Operational'
try {
    & wevtutil.exe sl $log /e:true /ms:20971520 /rt:false
    if ($LASTEXITCODE -ne 0) { throw "wevtutil exited $LASTEXITCODE" }
    $enabled = (& wevtutil.exe gl $log | Select-String '^enabled:').ToString().Trim()
    Write-Host "PrintService Operational log: $enabled"
} catch {
    Write-Host "Failed to enable PrintService Operational log: $_"
}
