<#
.SYNOPSIS
    DancherLink Build System - Main Entry Point
.DESCRIPTION
    Builds DancherLink Release or Beta version.
.PARAMETER Type
    Build type: 'release' or 'beta'
.EXAMPLE
    .\Build.ps1 -Type release
    .\Build.ps1 -Type beta
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('release', 'beta')]
    [string]$Type
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "DancherLink Build System" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Build Type: $Type" -ForegroundColor Yellow
Write-Host "Configuration: Release (optimized)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Execute the appropriate build script
if ($Type -eq 'release') {
    & "$ScriptDir\Build-Release.ps1"
} else {
    & "$ScriptDir\Build-Beta.ps1"
}
