# Disable WAC pop-up in Server Manager on Windows Server 2019
if ($WINDOWSBUILD -eq $WINDOWSSERVER2019) {
    # Registry path controlling the Server Manager welcome popup
    $regkeyServerManager = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
    New-ItemProperty -Path $regkeyServerManager -Name 'DoNotPopWACConsoleAtSMLaunch' -PropertyType 'DWord' -Value 1 -Force | Out-Null
}
