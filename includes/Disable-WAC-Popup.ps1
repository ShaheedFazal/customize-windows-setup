# Disable WAC pop-up in Server Manager on Windows Server 2019
if ($WINDOWSBUILD -eq $WINDOWSSERVER2019) {
    # Registry path controlling the Server Manager welcome popup
    $regkeyServerManager = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
    Set-RegistryValue -Path $regkeyServerManager -Name 'DoNotPopWACConsoleAtSMLaunch' -Value 1 -Type 'DWord' -Force
}

