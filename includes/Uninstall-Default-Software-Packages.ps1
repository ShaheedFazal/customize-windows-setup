# Disable Consumer Features to prevent automatic installation of third-party apps and games
Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type "DWord" -Force
Write-Host "[OK] Disabled Windows Consumer Features (prevents automatic app installs)"

# Helper to quietly uninstall an AppX package if it exists. Also removes
# any provisioned copy so the app does not return for new users.
function Uninstall-PackageIfPresent {
    param(
        [string]$Identifier
    )

    $package = Get-AppxPackage $Identifier -ErrorAction SilentlyContinue
    if ($null -ne $package) {
        try {
            $package | Remove-AppxPackage -ErrorAction Stop
        } catch {
            Write-Log "Failed to remove AppX $Identifier : $_"
        }
    }

    $prov = Get-AppxProvisionedPackage -Online | Where-Object DisplayName -like $Identifier
    if ($null -ne $prov) {
        # Some entries may reference missing install locations which causes
        # Remove-AppxProvisionedPackage to throw a path related error. Only
        # attempt removal when a valid install path exists.
        foreach ($p in $prov) {
            if ($p.InstallLocation -and (Test-Path $p.InstallLocation)) {
                try {
                    $p | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
                }
                catch [System.Runtime.InteropServices.COMException] {
                    if ($_.Exception.HResult -ne -2147024893) {
                        Write-Log "Failed to remove provisioned package $Identifier : $_"
                    }
                }
            } else {
                Write-Log "Skipping removal of provisioned package $Identifier due to missing install location"
            }
        }
    }
}

# Uninstall default Microsoft applications
Uninstall-PackageIfPresent "Microsoft.3DBuilder"
Uninstall-PackageIfPresent "Microsoft.AppConnector"
Uninstall-PackageIfPresent "Microsoft.BingFinance"
Uninstall-PackageIfPresent "Microsoft.BingNews"
Uninstall-PackageIfPresent "Microsoft.BingSports"
Uninstall-PackageIfPresent "Microsoft.BingTranslator"
Uninstall-PackageIfPresent "Microsoft.BingWeather"
Uninstall-PackageIfPresent "Microsoft.CommsPhone"
Uninstall-PackageIfPresent "Microsoft.ConnectivityStore"
Uninstall-PackageIfPresent "Microsoft.GetHelp"
Uninstall-PackageIfPresent "Microsoft.Getstarted"
Uninstall-PackageIfPresent "Microsoft.Messaging"
Uninstall-PackageIfPresent "Microsoft.Microsoft3DViewer"
Uninstall-PackageIfPresent "Microsoft.MicrosoftPowerBIForWindows"
Uninstall-PackageIfPresent "Microsoft.MicrosoftSolitaireCollection"
Uninstall-PackageIfPresent "Microsoft.MicrosoftStickyNotes"
Uninstall-PackageIfPresent "Microsoft.NetworkSpeedTest"
Uninstall-PackageIfPresent "Microsoft.Office.OneNote"
Uninstall-PackageIfPresent "Microsoft.Office.Sway"
Uninstall-PackageIfPresent "Microsoft.OneConnect"
Uninstall-PackageIfPresent "Microsoft.People"
Uninstall-PackageIfPresent "Microsoft.Print3D"
Uninstall-PackageIfPresent "Microsoft.RemoteDesktop"
Uninstall-PackageIfPresent "Microsoft.Wallet"
Uninstall-PackageIfPresent "Microsoft.WindowsAlarms"
Uninstall-PackageIfPresent "Microsoft.WindowsCamera"
Uninstall-PackageIfPresent "microsoft.windowscommunicationsapps"
Uninstall-PackageIfPresent "Microsoft.WindowsFeedbackHub"
Uninstall-PackageIfPresent "Microsoft.WindowsMaps"
Uninstall-PackageIfPresent "Microsoft.WindowsPhone"
Uninstall-PackageIfPresent "Microsoft.Windows.Photos"
Uninstall-PackageIfPresent "Microsoft.WindowsSoundRecorder"
Uninstall-PackageIfPresent "Microsoft.ZuneMusic"
Uninstall-PackageIfPresent "Microsoft.ZuneVideo"

# Uninstall default third party applications
Uninstall-PackageIfPresent "2414FC7A.Viber"
Uninstall-PackageIfPresent "41038Axilesoft.ACGMediaPlayer"
Uninstall-PackageIfPresent "46928bounde.EclipseManager"
Uninstall-PackageIfPresent "4DF9E0F8.Netflix"
Uninstall-PackageIfPresent "64885BlueEdge.OneCalendar"
Uninstall-PackageIfPresent "7EE7776C.LinkedInforWindows"
Uninstall-PackageIfPresent "828B5831.HiddenCityMysteryofShadows"
Uninstall-PackageIfPresent "89006A2E.AutodeskSketchBook"
Uninstall-PackageIfPresent "9E2F88E3.Twitter"
Uninstall-PackageIfPresent "A278AB0D.DisneyMagicKingdoms"
Uninstall-PackageIfPresent "A278AB0D.MarchofEmpires"
Uninstall-PackageIfPresent "ActiproSoftwareLLC.562882FEEB491"
Uninstall-PackageIfPresent "AdobeSystemsIncorporated.AdobePhotoshopExpress"
Uninstall-PackageIfPresent "CAF9E577.Plex"
Uninstall-PackageIfPresent "D52A8D61.FarmVille2CountryEscape"
Uninstall-PackageIfPresent "D5EA27B7.Duolingo-LearnLanguagesforFree"
Uninstall-PackageIfPresent "DB6EA5DB.CyberLinkMediaSuiteEssentials"
Uninstall-PackageIfPresent "DolbyLaboratories.DolbyAccess"
Uninstall-PackageIfPresent "Drawboard.DrawboardPDF"
Uninstall-PackageIfPresent "Facebook.Facebook"
Uninstall-PackageIfPresent "flaregamesGmbH.RoyalRevolt2"
Uninstall-PackageIfPresent "GAMELOFTSA.Asphalt8Airborne"
Uninstall-PackageIfPresent "KeeperSecurityInc.Keeper"
Uninstall-PackageIfPresent "king.com.BubbleWitch3Saga"
Uninstall-PackageIfPresent "king.com.CandyCrushSodaSaga"
Uninstall-PackageIfPresent "PandoraMediaInc.29680B314EFC2"
Uninstall-PackageIfPresent "SpotifyAB.SpotifyMusic"
Uninstall-PackageIfPresent "WinZipComputing.WinZipUniversal"
Uninstall-PackageIfPresent "XINGAG.XING"

# Remove Windows 10 Metro App
Uninstall-PackageIfPresent "king.com.CandyCrushSaga"
Uninstall-PackageIfPresent "Microsoft.BingWeather"
Uninstall-PackageIfPresent "Microsoft.BingNews"
Uninstall-PackageIfPresent "Microsoft.BingSports"
Uninstall-PackageIfPresent "Microsoft.BingFinance"
Uninstall-PackageIfPresent "Microsoft.XboxApp"
Uninstall-PackageIfPresent "Microsoft.WindowsPhone"
Uninstall-PackageIfPresent "Microsoft.MicrosoftSolitaireCollection"
Uninstall-PackageIfPresent "Microsoft.People"
Uninstall-PackageIfPresent "Microsoft.ZuneMusic"
Uninstall-PackageIfPresent "Microsoft.ZuneVideo"
Uninstall-PackageIfPresent "Microsoft.SkypeApp"
Uninstall-PackageIfPresent "3dbuilder"
Uninstall-PackageIfPresent "getstarted"
Uninstall-PackageIfPresent "*officehub*"

$SoftwarePackages = @(
	#Unnecessary Windows 10 AppX Apps
	"Microsoft.BingNews"
	"Microsoft.GetHelp"
	"Microsoft.Getstarted"
	"Microsoft.Messaging"
	"Microsoft.Microsoft3DViewer"
	"Microsoft.MicrosoftSolitaireCollection"
	"Microsoft.NetworkSpeedTest"
	"Microsoft.News"
	"Microsoft.Office.Lens"
	"Microsoft.Office.Sway"
	"Microsoft.OneConnect"
	"Microsoft.People"
	"Microsoft.Print3D"
	"Microsoft.SkypeApp"
	"Microsoft.StorePurchaseApp"
	"Microsoft.Whiteboard"
	"Microsoft.WindowsAlarms"
	"microsoft.windowscommunicationsapps"
	"Microsoft.WindowsFeedbackHub"
	"Microsoft.WindowsMaps"
	"Microsoft.WindowsSoundRecorder"
	"Microsoft.ZuneMusic"
	"Microsoft.ZuneVideo"

	#Sponsored Windows 10 AppX Apps
	#Add sponsored/featured apps to remove in the "*AppName*" format
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
	
	#Optional: Typically not removed but you can if you need to for some reason
	"*Microsoft.Advertising.Xaml_10.1712.5.0_x64__8wekyb3d8bbwe*"
	"*Microsoft.Advertising.Xaml_10.1712.5.0_x86__8wekyb3d8bbwe*"
	"*Microsoft.BingWeather*"
	#"*Microsoft.MSPaint*"
	"*Microsoft.MicrosoftStickyNotes*"
	"*Microsoft.Windows.Photos*"
	#"*Microsoft.WindowsCalculator*"
	#"*Microsoft.WindowsStore*"
)

# Removing packages can trigger errors like:
#  - "Deployment failed with HRESULT: 0x80073CFA"
#  - "Remove-AppxProvisionedPackage : The system cannot find the path specified"
# These simply indicate the app is already gone. They are harmless and can be
# safely ignored.
foreach ($pkg in $SoftwarePackages) {
        Uninstall-PackageIfPresent $pkg
}

