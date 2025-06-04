# Set Google Chrome as the default browser and handler for common file types
# The alphabetical order of this file (after Install-EssentialApps.ps1)
# ensures it runs once Chrome is installed.

Write-Host "🔧 Setting Google Chrome defaults..."

$setUserFtaPath = 'C:\\Scripts\\SetUserFTA.exe'

if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "⚠️ SetUserFTA not found at $setUserFtaPath. Skipping default browser configuration." -ForegroundColor Yellow
    return
}

# Verify that Chrome is installed before proceeding
$chromePaths = @(
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe'
)
$chromeInstalled = $false
foreach ($path in $chromePaths) {
    if (Test-Path $path) { $chromeInstalled = $true; break }
}

if (-not $chromeInstalled) {
    Write-Host "⚠️ Google Chrome not found. Skipping default browser configuration." -ForegroundColor Yellow
    return
}


# Map file types and protocols to their corresponding ProgIDs
$associations = @{
    'http'   = 'ChromeHTML'
    'https'  = 'ChromeHTML'
    '.htm'   = 'ChromeHTML'
    '.html'  = 'ChromeHTML'
    '.pdf'   = 'ChromePDF'
    'mailto' = 'ChromeHTML'
}

foreach ($type in $associations.Keys) {
    & $setUserFtaPath $type $associations[$type] | Out-Null
}

Write-Host "✅ Google Chrome set as default browser." -ForegroundColor Green
