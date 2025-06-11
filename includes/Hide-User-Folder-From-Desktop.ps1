# Hide User Folder shortcut from desktop

$userFolderGuid = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'
$registryPaths = @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
)

foreach ($path in $registryPaths) {
    if (Test-Path $path -PathType Container -and `
        (Get-ItemProperty -Path $path -Name $userFolderGuid -ErrorAction SilentlyContinue)) {
        Remove-RegistryValue -Path $path -Name $userFolderGuid
    } else {
        Write-Host "[REGISTRY] Value not found (already removed): $path\$userFolderGuid" -ForegroundColor Gray
    }
}
