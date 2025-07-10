# Configure local account lockout policy
#
# On a domain-joined machine this affects only the local SAM database. Domain
# controllers or policies managed through Active Directory should use
# `net accounts /domain` or Group Policy instead.
#
# If the lockout threshold is not set first, subsequent commands may return
# "System error 87" indicating an invalid parameter.

$threshold = 5  # failed attempts before lockout
$duration  = 30 # lockout duration in minutes
$window    = 30 # timeframe in which failed attempts are counted

try {
    $output = net.exe accounts /lockoutthreshold:$threshold 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set lockout threshold: $output"
        return
    }
    Write-Host "[OK] Lockout threshold set to $threshold attempts." -ForegroundColor Green
} catch {
    Write-Warning "Error configuring lockout threshold: $_"
    return
}

try {
    $output = net.exe accounts /lockoutduration:$duration 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set lockout duration: $output"
    } else {
        Write-Host "[OK] Lockout duration set to $duration minutes." -ForegroundColor Green
    }
} catch {
    Write-Warning "Error configuring lockout duration: $_"
}

try {
    $output = net.exe accounts /lockoutwindow:$window 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to set lockout window: $output"
    } else {
        Write-Host "[OK] Lockout window set to $window minutes." -ForegroundColor Green
    }
} catch {
    Write-Warning "Error configuring lockout window: $_"
}
