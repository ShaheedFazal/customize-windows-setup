# Prompt for default office suite and configure file associations

param(
    [ValidateSet('Google', 'LibreOffice')]
    [string]$Suite
)

$setUserFtaPath = Join-Path $env:TEMP 'SetUserFTA.exe'
# Fall back to the location used by Install-EssentialApps.ps1
if (-not (Test-Path $setUserFtaPath)) {
    $setUserFtaPath = 'C:\Scripts\SetUserFTA.exe'
}

$setFileAssocPath = Join-Path $PSScriptRoot 'Set-FileAssoc.ps1'

if (-not (Test-Path $setUserFtaPath) -and -not (Test-Path $setFileAssocPath)) {
    Write-Warning "SetUserFTA.exe and Set-FileAssoc.ps1 not found. File associations will be skipped."
    Write-Log "No association tools available for office defaults"
    return
}

if (-not $Suite) {
    $Suite = $OFFICESUITE
}

if (-not $Suite) {
    Write-Host "No office suite selection made. Skipping." -ForegroundColor Yellow
    return
}

$choice = if ($Suite -eq 'Google') { '1' } else { '2' }

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
            try {
                Set-FileAssociation -ExtensionOrProtocol $ext -ProgId $chromeMap[$ext] -SetUserFtaPath $setUserFtaPath -SetFileAssocPath $setFileAssocPath
            } catch {
                Write-Warning "Failed to set association for $ext"
                Write-Log "Association error for $ext : $_"
            }
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
            try {
                Set-FileAssociation -ExtensionOrProtocol $ext -ProgId $libreOfficeMap[$ext] -SetUserFtaPath $setUserFtaPath -SetFileAssocPath $setFileAssocPath
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
