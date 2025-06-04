# Download and extract the customize-windows-setup repository
#
# This script fetches the repository as a zip archive from GitHub,
# extracts it to a folder next to the script and then removes the zip file.
# Customize the $repoUrl if you need a different fork or branch.

# URL of the zipped repository
$repoUrl = "https://github.com/ShaheedFazal/customize-windows-setup/archive/refs/heads/main.zip"

# Check for administrative privileges
function Test-Administrator {
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent()
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    }
}

if (-not (Test-Administrator)) {
    Write-Warning "It is recommended to run this script as Administrator."
}

# Check execution policy
try {
    $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
} catch {
    $executionPolicy = $null
    Write-Warning "Unable to determine execution policy: $_"
}
if ($executionPolicy -eq 'Restricted') {
    Write-Warning "Script execution is disabled by the current policy ($executionPolicy)."
    Write-Warning "Run 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser' or invoke the script with -ExecutionPolicy Bypass."
}

# Choose a sensible base path when the script is invoked via a one-liner.
# A direct `iex` call often starts in the Windows system directory, so
# default to the user's Downloads folder in that case.
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ($basePath -like "$env:windir*") {
    $basePath = Join-Path $env:USERPROFILE 'Downloads'
}

# Path to store the downloaded zip
$zipPath = Join-Path $basePath 'customize-windows-setup.zip'

# Folder where the contents will be extracted
$extractPath = Join-Path $basePath 'customize-windows-setup'

try {
    Write-Host "Downloading repository..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $repoUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting archive..." -ForegroundColor Cyan
    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    Write-Host "Cleaning up zip file..." -ForegroundColor Cyan
    Remove-Item $zipPath
    Write-Host "Done. Repository extracted to $extractPath" -ForegroundColor Green
} catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
}
