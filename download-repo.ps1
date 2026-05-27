# Download and extract the customize-windows-setup repository.
#
# Fetches the repository as a zip archive from GitHub, extracts it next to
# the script, and removes the zip. Customize $RepoOwner / $RepoName / $Branch
# if you need a different fork or branch.
#
# Exit codes (so SuperOps / any RMM sees real failures):
#   0  success — entrypoint script exists on disk
#   2  DNS / network preflight failed
#   3  download failed after retries
#   4  extraction failed
#   5  expected entrypoint script not found after extract

[CmdletBinding()]
param(
    [string] $RepoOwner = 'ShaheedFazal',
    [string] $RepoName  = 'customize-windows-setup',
    [string] $Branch    = 'main',
    [string] $EntryPoint = 'customize-windows-client.ps1'
)

$ErrorActionPreference = 'Stop'

$ZipUrl    = "https://github.com/$RepoOwner/$RepoName/archive/refs/heads/$Branch.zip"
$GitUrl    = "https://github.com/$RepoOwner/$RepoName.git"

function Test-Administrator {
    $u = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $u.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Fail {
    param([int]$Code, [string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit $Code
}

if (-not (Test-Administrator)) {
    Write-Warning 'It is recommended to run this script as Administrator.'
}

# Sensible base path: alongside the script, or C:\Temp for iex one-liners.
$basePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ($basePath -like "$env:windir*") { $basePath = 'C:\Temp' }
if (-not (Test-Path $basePath)) { New-Item -ItemType Directory -Force -Path $basePath | Out-Null }

$zipPath     = Join-Path $basePath "$RepoName.zip"
$extractPath = Join-Path $basePath $RepoName
$expectedDir = Join-Path $extractPath "$RepoName-$Branch"
$expectedExe = Join-Path $expectedDir $EntryPoint

# --- 1. Preflight: can we resolve github.com / codeload.github.com? -------
Write-Host '[INFO] DNS preflight...' -ForegroundColor Cyan
$dnsOk = $true
foreach ($host in @('github.com', 'codeload.github.com')) {
    try {
        $null = Resolve-DnsName -Name $host -Type A -ErrorAction Stop -QuickTimeout
        Write-Host "  $host  OK"
    } catch {
        Write-Host "  $host  FAIL ($_)" -ForegroundColor Yellow
        $dnsOk = $false
    }
}

# --- 2. Download with retries (3 attempts: 0s, 30s, 120s backoff) ---------
$downloadOk = $false
if ($dnsOk) {
    $delays = @(0, 30, 120)
    for ($i = 0; $i -lt $delays.Count; $i++) {
        if ($delays[$i] -gt 0) {
            Write-Host "[INFO] Backing off $($delays[$i])s before retry $($i+1)..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delays[$i]
        }
        try {
            Write-Host "[INFO] Downloading $ZipUrl (attempt $($i+1)/$($delays.Count))..." -ForegroundColor Cyan
            Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing
            $downloadOk = $true
            break
        } catch {
            Write-Host "[WARN] Download attempt failed: $_" -ForegroundColor Yellow
        }
    }
}

# --- 3. Fallback: git clone (sidesteps codeload.github.com entirely) ------
if (-not $downloadOk) {
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git) {
        Write-Host '[INFO] Falling back to git clone...' -ForegroundColor Cyan
        try {
            if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
            # Clone into the same structure ExpandArchive would produce: <extractPath>\<RepoName>-<Branch>
            & git.exe clone --depth 1 --branch $Branch $GitUrl $expectedDir 2>&1 | Write-Host
            if ($LASTEXITCODE -eq 0 -and (Test-Path $expectedExe)) {
                Write-Host "[SUCCESS] Repository cloned to $expectedDir" -ForegroundColor Green
                exit 0
            }
        } catch {
            Write-Host "[WARN] git clone failed: $_" -ForegroundColor Yellow
        }
    }
    if (-not $dnsOk) {
        Fail 2 "DNS preflight failed and git fallback unavailable. Check endpoint network / EDR / proxy for github.com + codeload.github.com."
    }
    Fail 3 "Download failed after $($delays.Count) attempts and git fallback unavailable. Last URL: $ZipUrl"
}

# --- 4. Extract -----------------------------------------------------------
Write-Host '[INFO] Extracting archive...' -ForegroundColor Cyan
try {
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
} catch {
    Fail 4 "Extraction failed: $_"
} finally {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
}

# --- 5. Verify entrypoint exists ------------------------------------------
if (-not (Test-Path $expectedExe)) {
    Fail 5 "Entrypoint not found at $expectedExe after extract. Repository layout may have changed."
}

Write-Host "[SUCCESS] Repository extracted to $extractPath" -ForegroundColor Green
Write-Host "[INFO] Entrypoint: $expectedExe" -ForegroundColor DarkGray
exit 0
