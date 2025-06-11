# Deploy BGInfo wallpaper with custom configuration
param(
    [string]$WallpaperImage = '',
    [string]$BgInfoConfig = ''
)

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoWallpaperDir = Join-Path $ScriptRoot '..\wallpaper'
$DestDir = 'C:\\wallpaper'
$PersistDir = 'C:\\Scripts'
$PersistScript = Join-Path $PersistDir 'Deploy-BGInfo.ps1'
$BgInfoExe = Join-Path $DestDir 'Bginfo.exe'
$BgInfoUrl = 'https://download.sysinternals.com/files/BGInfo.zip'
$BgInfoZip = Join-Path $env:TEMP 'BGInfo.zip'
$TaskName = 'ApplyBGInfo'

if (-not (Test-Path $DestDir)) {
    New-Item -Path $DestDir -ItemType Directory -Force | Out-Null
}

$isPersisted = ($PSCommandPath -ieq $PersistScript)
if (-not $isPersisted -and (Test-Path $RepoWallpaperDir)) {
    Copy-Item -Path (Join-Path $RepoWallpaperDir '*') -Destination $DestDir -Recurse -Force
}

if (-not $WallpaperImage) { $WallpaperImage = Join-Path $DestDir 'wallpaper.png' }
if (-not $BgInfoConfig) { $BgInfoConfig = Join-Path $DestDir 'WallpaperSettings.bgi' }

function Download-File {
    param([string]$Url, [string]$Path)
    $maxRetries = 3
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing -ErrorAction Stop
            return $true
        } catch {
            if ($i -eq $maxRetries) { return $false }
            Start-Sleep -Seconds (2 * $i)
        }
    }
    return $false
}

if (-not (Test-Path $BgInfoExe)) {
    if (Download-File -Url $BgInfoUrl -Path $BgInfoZip) {
        try {
            Expand-Archive -Path $BgInfoZip -DestinationPath $DestDir -Force
            Remove-Item $BgInfoZip -ErrorAction SilentlyContinue
            $downloaded = Get-ChildItem -Path $DestDir -Filter 'Bginfo*.exe' -Recurse | Select-Object -First 1
            if ($downloaded) { Move-Item $downloaded.FullName $BgInfoExe -Force }
        } catch {
            Write-Warning "Failed to extract BGInfo: $_"
        }
    } else {
        Write-Warning 'Failed to download BGInfo.'
    }
}

if (-not (Test-Path $BgInfoExe)) {
    Write-Warning 'BGInfo executable not available.'
    return
}

$arguments = "`"$BgInfoConfig`" /silent /nolicprompt /timer:0 /accepteula"

# Run once immediately
Start-Process -FilePath $BgInfoExe -ArgumentList $arguments -Wait

# Create scheduled task to run at logon
if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute $BgInfoExe -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogon
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -RunLevel Highest -Force | Out-Null
}

# Persist script for future runs if executed from repository
if (-not $isPersisted) {
    if (-not (Test-Path $PersistDir)) { New-Item -Path $PersistDir -ItemType Directory -Force | Out-Null }
    Copy-Item -Path $PSCommandPath -Destination $PersistScript -Force
}
