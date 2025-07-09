# Disable IE Enhanced Security Configuration (ESC)
function Disable-IEESC {
    $isServer = ((Get-CimInstance Win32_OperatingSystem).ProductType -ne 1)
    if (-not $isServer) {
        return
    }

    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" # Admin ESC
    $UserKey  = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" # User ESC

    if (Test-Path $AdminKey) {
        Set-RegistryValue -Path $AdminKey -Name "IsInstalled" -Value 0 -Type "DWord"
    }

    if (Test-Path $UserKey) {
        Set-RegistryValue -Path $UserKey -Name "IsInstalled" -Value 0 -Type "DWord"
    }

    # WARNING: This closes all open File Explorer windows
    Stop-Process -Name explorer -Force

    # Restart Explorer
    Start-Process "explorer.exe"
}

Disable-IEESC

