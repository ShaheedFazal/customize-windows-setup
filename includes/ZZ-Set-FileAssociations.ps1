#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies standard configurations for a workgroup computer.
.DESCRIPTION
    This script performs two main actions:
    1. Sets default file associations using a 'WorkgroupDefaults.xml' file.
    2. Configures a Microsoft Edge policy to stop it from asking to be the default browser.

    The script looks for the XML file in its own directory.
    This script MUST be run with Administrator privileges.
#>

Write-Host "Starting system configuration..." -ForegroundColor Cyan

# --- Action 1: Apply Default File Associations ---
try {
    Write-Host "`n[1/2] Applying default file associations..." -ForegroundColor White

    # Get the directory where this script is located.
    $scriptDirectory = $PSScriptRoot

    # Define the expected name of the XML configuration file.
    $xmlFileName = "AppAssoc.xml"
    $xmlPath = Join-Path $scriptDirectory $xmlFileName

    # Check if the XML file actually exists.
    if (-not (Test-Path $xmlPath)) {
        throw "Configuration file not found. Make sure '$xmlFileName' is in the same folder as this script."
    }

    Write-Host " - Found configuration file at: $xmlPath" -ForegroundColor Green
    Dism.exe /Online /Import-DefaultAppAssociations:$xmlPath
    Write-Host " - Successfully applied new default file associations." -ForegroundColor Green
    Write-Host "   (Changes will take effect for existing users on their next login)"

    # Apply associations immediately for the current user using Set-FileAssociation
    try {
        if (-not (Get-Command Set-FileAssociation -ErrorAction SilentlyContinue)) {
            $shared = Join-Path $scriptDirectory 'Shared-Functions.ps1'
            if (Test-Path $shared) { . $shared }
        }
        $xmlContent = [xml](Get-Content -Path $xmlPath)
        foreach ($assoc in $xmlContent.DefaultAssociations.Association) {
            Set-FileAssociation -ExtensionOrProtocol $assoc.Identifier -ProgId $assoc.ProgId
        }
        Write-Host " - Current user associations configured." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to set associations for current user: $_"
    }

}
catch {
    Write-Error "An error occurred during file association setup: $_"
}


# --- Action 2: Configure Microsoft Edge Policy ---
try {
    Write-Host "`n[2/2] Configuring Microsoft Edge policies..." -ForegroundColor White

    # Define the path in HKEY_LOCAL_MACHINE to apply the policy to ALL users.
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    # Check if the 'Edge' key exists. If not, create it.
    if (-not (Test-Path $edgePolicyPath)) {
        Write-Host " - Edge policy key not found. Creating it now..." -ForegroundColor Yellow
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    # Set the registry value to disable the default browser check.
    # Name: DefaultBrowserSettingEnabled
    # Type: DWORD (32-bit)
    # Value: 0
    New-ItemProperty -Path $edgePolicyPath -Name "DefaultBrowserSettingEnabled" -Value 0 -PropertyType DWord -Force | Out-Null

    Write-Host " - Successfully set Edge policy to prevent default browser prompts." -ForegroundColor Green
}
catch {
    Write-Error "An error occurred during Edge policy configuration: $_"
}


# --- Finish ---
Write-Host "`nConfiguration complete." -ForegroundColor Cyan