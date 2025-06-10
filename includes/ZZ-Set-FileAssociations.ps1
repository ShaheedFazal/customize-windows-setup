# Configure default file associations for Chrome and office documents

param(
    [ValidateSet('Google','LibreOffice')]
    [string]$Suite
)

Write-Host "Configuring file associations..." -ForegroundColor Cyan

$setUserFtaPath = Join-Path $env:TEMP 'SetUserFTA.exe'
if (-not (Test-Path $setUserFtaPath)) {
    $setUserFtaPath = 'C:\\Scripts\\SetUserFTA.exe'
}

# ---- Set Chrome as default browser if installed ----
$chromePaths = @(
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe'
)
$chromeInstalled = $chromePaths | Where-Object { Test-Path $_ } | Measure-Object | Select-Object -ExpandProperty Count

if ($chromeInstalled) {
    Write-Host "Setting Google Chrome defaults..." -ForegroundColor Green
    $chromeAssoc = @{
        'http'   = 'ChromeHTML'
        'https'  = 'ChromeHTML'
        '.htm'   = 'ChromeHTML'
        '.html'  = 'ChromeHTML'
        '.pdf'   = 'ChromePDF'
        'mailto' = 'ChromeHTML'
    }
    foreach ($type in $chromeAssoc.Keys) {
        try {
            Set-FileAssociation -ExtensionOrProtocol $type -ProgId $chromeAssoc[$type] -SetUserFtaPath $setUserFtaPath
        } catch {
            Write-Warning "Failed to associate $type with Chrome"
            Write-Log "Association error for $type : $_"
        }
    }
    Write-Host "Google Chrome set as default browser." -ForegroundColor Green
} else {
    Write-Host "Google Chrome not found. Skipping default browser configuration." -ForegroundColor Yellow
}

# ---- Set office document defaults ----
if (-not $Suite) {
    $Suite = $OFFICESUITE
}

if (-not $Suite) {
    Write-Host "No office suite selection made. Skipping." -ForegroundColor Yellow
    return
}

$libreOfficeMap = @{
    '.doc'  = 'LibreOffice.WriterDocument.1'
    '.docx' = 'LibreOffice.WriterDocument.1'
    '.xls'  = 'LibreOffice.CalcDocument.1'
    '.xlsx' = 'LibreOffice.CalcDocument.1'
    '.ppt'  = 'LibreOffice.ImpressDocument.1'
    '.pptx' = 'LibreOffice.ImpressDocument.1'
}

$chromeMap = @{
    '.doc'  = 'ChromeHTML'
    '.docx' = 'ChromeHTML'
    '.xls'  = 'ChromeHTML'
    '.xlsx' = 'ChromeHTML'
    '.ppt'  = 'ChromeHTML'
    '.pptx' = 'ChromeHTML'
}

switch ($Suite) {
    'Google' {
        Write-Host "Setting Google Workspace defaults..." -ForegroundColor Green
        foreach ($ext in $chromeMap.Keys) {
            try {
                Set-FileAssociation -ExtensionOrProtocol $ext -ProgId $chromeMap[$ext] -SetUserFtaPath $setUserFtaPath
            } catch {
                Write-Warning "Failed to set association for $ext"
                Write-Log "Association error for $ext : $_"
            }
        }

        $apps = @{
            'Google Docs'   = 'https://docs.google.com/document/u/0/'
            'Google Sheets' = 'https://docs.google.com/spreadsheets/u/0/'
            'Google Slides' = 'https://docs.google.com/presentation/u/0/'
            'Google Drive'  = 'https://drive.google.com/'
        }
        $startDir   = [Environment]::GetFolderPath('CommonPrograms')
        $desktopDir = [Environment]::GetFolderPath('CommonDesktopDirectory')
        foreach ($app in $apps.GetEnumerator()) {
            $content = "[InternetShortcut]`nURL=$($app.Value)"
            Set-Content -Path (Join-Path $startDir   ($app.Key + '.url')) -Value $content -Encoding ASCII
            Set-Content -Path (Join-Path $desktopDir ($app.Key + '.url')) -Value $content -Encoding ASCII
        }
        Write-Host "Google Workspace shortcuts added." -ForegroundColor Green
    }
    'LibreOffice' {
        Write-Host "Setting LibreOffice defaults..." -ForegroundColor Green
        foreach ($ext in $libreOfficeMap.Keys) {
            try {
                Set-FileAssociation -ExtensionOrProtocol $ext -ProgId $libreOfficeMap[$ext] -SetUserFtaPath $setUserFtaPath
            } catch {
                Write-Warning "Failed to set association for $ext"
                Write-Log "Association error for $ext : $_"
            }
        }
    }
    default {
        Write-Host "No office suite selection made. Skipping." -ForegroundColor Yellow
    }
}
