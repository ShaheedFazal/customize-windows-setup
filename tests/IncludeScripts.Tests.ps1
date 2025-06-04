$ErrorActionPreference = 'Stop'

Describe "Include scripts" {
    $includePath = Join-Path $PSScriptRoot '..' 'includes'
    Get-ChildItem -Path $includePath -Filter '*.ps1' | ForEach-Object {
        It "Invokes $($_.Name) with -WhatIf" {
            $result = powershell -NoProfile -ExecutionPolicy Bypass -File $_.FullName -WhatIf 2>&1
            $result | Should -Not -Match 'Error'
        }
    }
}
