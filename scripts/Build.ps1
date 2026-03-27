<#
.SYNOPSIS
    DancherLink Build System - Main Entry Point
.DESCRIPTION
    Builds DancherLink Release or Beta version.
.PARAMETER Type
    Build type: 'release' or 'beta'
.EXAMPLE
    .\Build.ps1 -Type release    # Build stable release
    .\Build.ps1 -Type beta       # Build beta version
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('release', 'beta')]
    [string]$Type,

    [switch]$Help
)

if ($Help -or -not $Type) {
    Write-Host "DancherLink Build System" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Builds DancherLink Release or Beta version." -ForegroundColor White
    Write-Host ""
    Write-Host "Build Types:" -ForegroundColor Cyan
    Write-Host "  release    Build stable release version (MSI)" -ForegroundColor White
    Write-Host "  beta       Build beta/test version (MSI)" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\Build.ps1 -Type release" -ForegroundColor White
    Write-Host "  .\Build.ps1 -Type beta" -ForegroundColor White
    exit 0
}

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
