# Prompt for default office suite and configure file associations

$setUserFtaPath = Join-Path $env:TEMP 'SetUserFTA.exe'
# Fall back to the location used by Install-EssentialApps.ps1
if (-not (Test-Path $setUserFtaPath)) {
    $setUserFtaPath = 'C:\Scripts\SetUserFTA.exe'
}
if (-not (Test-Path $setUserFtaPath)) {
    Write-Host "SetUserFTA not found. Skipping office suite defaults." -ForegroundColor Yellow
    return
}

Write-Host "Choose default office suite:" -ForegroundColor Cyan
Write-Host "[1] Google Workspace" -ForegroundColor Cyan
Write-Host "[2] LibreOffice" -ForegroundColor Cyan
$choice = Read-Host "Enter 1 or 2"

# Map document types to ProgIDs for LibreOffice
$libreOfficeMap = @{ 
    '.doc'  = 'LibreOffice.WriterDocument.1'
    '.docx' = 'LibreOffice.WriterDocument.1'
    '.xls'  = 'LibreOffice.CalcDocument.1'
    '.xlsx' = 'LibreOffice.CalcDocument.1'
    '.ppt'  = 'LibreOffice.ImpressDocument.1'
    '.pptx' = 'LibreOffice.ImpressDocument.1'
}

# Map document types to Chrome when Google Workspace is chosen
$chromeMap = @{ 
    '.doc'  = 'ChromeHTML'
    '.docx' = 'ChromeHTML'
    '.xls'  = 'ChromeHTML'
    '.xlsx' = 'ChromeHTML'
    '.ppt'  = 'ChromeHTML'
    '.pptx' = 'ChromeHTML'
}

switch ($choice) {
    '1' {
        Write-Host "Setting Google Workspace defaults..." -ForegroundColor Green
        foreach ($ext in $chromeMap.Keys) {
            & $setUserFtaPath $ext $chromeMap[$ext] | Out-Null
        }

        # Shortcuts for Google Workspace apps
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
            $startPath   = Join-Path $startDir   ($app.Key + '.url')
            $desktopPath = Join-Path $desktopDir ($app.Key + '.url')
            Set-Content -Path $startPath   -Value $content -Encoding ASCII
            Set-Content -Path $desktopPath -Value $content -Encoding ASCII
        }

        Write-Host "Google Workspace shortcuts added." -ForegroundColor Green
    }
    '2' {
        Write-Host "Setting LibreOffice defaults..." -ForegroundColor Green
        foreach ($ext in $libreOfficeMap.Keys) {
            & $setUserFtaPath $ext $libreOfficeMap[$ext] | Out-Null
        }
    }
    default {
        Write-Host "No office suite selection made. Skipping." -ForegroundColor Yellow
    }
}
