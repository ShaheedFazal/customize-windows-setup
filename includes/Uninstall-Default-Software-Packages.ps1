# Disable Consumer Features to prevent automatic installation of third-party apps and games
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type "DWord" -Force
Write-Host "[OK] Disabled Windows Consumer Features (prevents automatic app installs)"

# Get provisioned packages once to avoid repeated slow calls
Write-Host "[INFO] Loading provisioned package list..."
$ProvisionedPackages = $null
try {
    $job = Start-Job -ScriptBlock { Get-AppxProvisionedPackage -Online -ErrorAction Stop }
    if (Wait-Job $job -Timeout 120) {
        $ProvisionedPackages = Receive-Job $job
        Write-Host "[OK] Loaded $($ProvisionedPackages.Count) provisioned packages"
    } else {
        Write-Host "[WARN] Timeout after 2 minutes loading provisioned packages - will skip provisioned package removal"
        Remove-Job $job -Force
    }
} catch {
    Write-Host "[WARN] Failed to load provisioned packages: $_"
}

# Helper to quietly uninstall an AppX package if it exists. Also removes
# any provisioned copy so the app does not return for new users.
function Uninstall-PackageIfPresent {
    param(
        [string]$Identifier
    )
    
    Write-Host "[REMOVING] $Identifier..." -NoNewline
    $removedCount = 0
    $startTime = Get-Date

    try {
        # Remove installed packages for current user with timeout
        $packages = Get-AppxPackage $Identifier -ErrorAction SilentlyContinue
        foreach ($package in $packages) {
            try {
                $job = Start-Job -ScriptBlock {
                    param($pkg)
                    $pkg | Remove-AppxPackage -ErrorAction Stop
                } -ArgumentList $package
                
                if (Wait-Job $job -Timeout 30) {
                    Receive-Job $job | Out-Null
                    $removedCount++
                } else {
                    Remove-Job $job -Force
                    Write-Log "Timeout removing AppX package: $Identifier"
                }
            } catch {
                Write-Log "Failed to remove AppX $Identifier : $_"
            }
        }

        # Remove provisioned packages (for new users) using pre-loaded list
        if ($null -ne $ProvisionedPackages) {
            $provPackages = $ProvisionedPackages | Where-Object DisplayName -like $Identifier
            foreach ($p in $provPackages) {
                # Skip if we've been working on this package too long
                $elapsed = (Get-Date) - $startTime
                if ($elapsed.TotalSeconds -gt 60) {
                    Write-Log "Skipping provisioned package removal for $Identifier due to timeout"
                    break
                }
                
                if ($p.InstallLocation -and (Test-Path $p.InstallLocation)) {
                    try {
                        $job = Start-Job -ScriptBlock {
                            param($pkg)
                            $pkg | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                        } -ArgumentList $p
                        
                        if (Wait-Job $job -Timeout 30) {
                            Receive-Job $job | Out-Null
                            $removedCount++
                        } else {
                            Remove-Job $job -Force
                            Write-Log "Timeout removing provisioned package: $Identifier"
                        }
                    }
                    catch [System.Runtime.InteropServices.COMException] {
                        if ($_.Exception.HResult -ne -2147024893) {
                            Write-Log "Failed to remove provisioned package $Identifier : $_"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Log "General error processing package $Identifier : $_"
    }
    
    $totalElapsed = ((Get-Date) - $startTime).TotalSeconds
    if ($removedCount -gt 0) {
        Write-Host " REMOVED ($removedCount packages, $([math]::Round($totalElapsed,1))s)" -ForegroundColor Green
    } elseif ($totalElapsed -gt 30) {
        Write-Host " TIMEOUT ($([math]::Round($totalElapsed,1))s)" -ForegroundColor Yellow
    } else {
        Write-Host " NOT FOUND ($([math]::Round($totalElapsed,1))s)" -ForegroundColor Gray
    }
}

# Comprehensive list of packages to remove (deduplicated and organized)
Write-Host "[INFO] Starting app removal process..."

$SoftwarePackages = @(
    # Microsoft Apps
    "Microsoft.3DBuilder"
    "Microsoft.AppConnector"
    "Microsoft.BingFinance"
    "Microsoft.BingNews"
    "Microsoft.BingSports"
    "Microsoft.BingTranslator"
    "Microsoft.BingWeather"
    "Microsoft.CommsPhone"
    "Microsoft.ConnectivityStore"
    "Microsoft.GetHelp"
    "Microsoft.Getstarted"
    "Microsoft.Messaging"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.MicrosoftPowerBIForWindows"
    "Microsoft.MicrosoftSolitaireCollection"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.NetworkSpeedTest"
    "Microsoft.News"
    "Microsoft.Office.Lens"
    "Microsoft.Office.OneNote"
    "Microsoft.Office.Sway"
    "Microsoft.OneConnect"
    "Microsoft.People"
    "Microsoft.Print3D"
    "Microsoft.RemoteDesktop"
    "Microsoft.SkypeApp"
    "Microsoft.StorePurchaseApp"
    "Microsoft.Wallet"
    "Microsoft.Whiteboard"
    "Microsoft.WindowsAlarms"
    "Microsoft.WindowsCamera"
    "Microsoft.WindowsFeedbackHub"
    "Microsoft.WindowsMaps"
    "Microsoft.WindowsPhone"
    "Microsoft.Windows.Photos"
    "Microsoft.WindowsSoundRecorder"
    "Microsoft.XboxApp"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "microsoft.windowscommunicationsapps"
    
    # Third-party Apps (exact names)
    "2414FC7A.Viber"
    "41038Axilesoft.ACGMediaPlayer"
    "46928bounde.EclipseManager"
    "4DF9E0F8.Netflix"
    "64885BlueEdge.OneCalendar"
    "7EE7776C.LinkedInforWindows"
    "828B5831.HiddenCityMysteryofShadows"
    "89006A2E.AutodeskSketchBook"
    "9E2F88E3.Twitter"
    "A278AB0D.DisneyMagicKingdoms"
    "A278AB0D.MarchofEmpires"
    "ActiproSoftwareLLC.562882FEEB491"
    "AdobeSystemsIncorporated.AdobePhotoshopExpress"
    "CAF9E577.Plex"
    "D52A8D61.FarmVille2CountryEscape"
    "D5EA27B7.Duolingo-LearnLanguagesforFree"
    "DB6EA5DB.CyberLinkMediaSuiteEssentials"
    "DolbyLaboratories.DolbyAccess"
    "Drawboard.DrawboardPDF"
    "Facebook.Facebook"
    "flaregamesGmbH.RoyalRevolt2"
    "GAMELOFTSA.Asphalt8Airborne"
    "KeeperSecurityInc.Keeper"
    "king.com.BubbleWitch3Saga"
    "king.com.CandyCrushSaga"
    "king.com.CandyCrushSodaSaga"
    "PandoraMediaInc.29680B314EFC2"
    "SpotifyAB.SpotifyMusic"
    "WinZipComputing.WinZipUniversal"
    "XINGAG.XING"
    
    # Wildcard patterns for variable names
    "*EclipseManager*"
    "*ActiproSoftwareLLC*"
    "*AdobeSystemsIncorporated.AdobePhotoshopExpress*"
    "*Duolingo-LearnLanguagesforFree*"
    "*PandoraMediaInc*"
    "*CandyCrush*"
    "*BubbleWitch3Saga*"
    "*Wunderlist*"
    "*Flipboard*"
    "*Twitter*"
    "*Facebook*"
    "*Spotify*"
    "*Royal Revolt*"
    "*Sway*"
    "*Speed Test*"
    "*Dolby*"
    "*officehub*"
    
    # Legacy/alternative names
    "3dbuilder"
    "getstarted"
    
    # Optional removals (advertising components)
    "*Microsoft.Advertising.Xaml*"
)

# Remove packages with progress tracking
$totalPackages = $SoftwarePackages.Count
$currentPackage = 0

foreach ($pkg in $SoftwarePackages) {
    $currentPackage++
    Write-Host "[$currentPackage/$totalPackages]" -NoNewline -ForegroundColor Cyan
    Uninstall-PackageIfPresent $pkg
}

Write-Host "[COMPLETED] App removal process finished" -ForegroundColor Green

