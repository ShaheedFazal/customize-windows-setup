# Note: Use either this script or Disable-Display-Sleep-Mode-Timeouts.ps1, not both, as they could conflict.
# Set Power Management to High Performance if it is not currently the active plan
 Try {
    $highPerf = powercfg -l | ForEach-Object{if($_.contains($POWERMANAGEMENT)) {$_.split()[3]}}
    $currPlan = $(powercfg -getactivescheme).split()[3]
    if ($currPlan -ne $highPerf) {powercfg -setactive $highPerf}
} Catch {
    Write-Warning -Message "Unable to set power plan to $POWERMANAGEMENT" -foregroundcolor $foregroundColor2
}
