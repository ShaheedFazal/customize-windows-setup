# Profile customization has been disabled by replacing the original functions.

function Invoke-ProfileTemplate {
    [CmdletBinding()]
    param()

    Write-Host "[TEMPLATE] Profile customization has been disabled. Skipping this step." -ForegroundColor Yellow
    
    # Return $true to allow the main script to continue without error.
    return $true
}

Export-ModuleMember -Function Invoke-ProfileTemplate
