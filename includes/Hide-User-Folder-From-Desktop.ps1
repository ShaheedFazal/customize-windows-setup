# Hide User Folder shortcut from desktop system-wide

$userFolderGuid = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'
$policyBasePath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer\HideDesktopIcons'
$policySubKeys  = @('ClassicStartMenu', 'NewStartPanel')

foreach ($sub in $policySubKeys) {
    $path = Join-Path $policyBasePath $sub
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
        Write-Host "[REGISTRY] Created key: $path" -ForegroundColor Green
    }
    Set-RegistryValue -Path $path -Name $userFolderGuid -Value 1 -Type 'DWord' -Force
}

# Remove per-user values that might conflict with the policy
$userRegistryPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
)

foreach ($path in $userRegistryPaths) {
    Remove-RegistryValue -Path $path -Name $userFolderGuid
}
