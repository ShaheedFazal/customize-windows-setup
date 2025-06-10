[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Extension,
    [Parameter(Mandatory)][string]$ProgId
)

try {
    $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$Extension\UserChoice"
    if (-not (Test-Path $key)) {
        New-Item -Path $key -Force | Out-Null
    }
    Set-ItemProperty -Path $key -Name 'ProgId' -Value $ProgId -Force
    Write-Host "Associated $Extension with $ProgId" -ForegroundColor Green
} catch {
    Write-Error "Failed to set association for $Extension : $_"
    exit 1
}
