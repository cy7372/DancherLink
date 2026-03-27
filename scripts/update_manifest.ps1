#
# DancherLink Manifest Update Script
# Usage: ./update_manifest.ps1 <version> <arch> <build_type> <source_root>
#

param (
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [string]$Arch,
    [Parameter(Mandatory=$true)]
    [ValidateSet("release", "beta")]
    [string]$BuildType,
    [Parameter(Mandatory=$true)]
    [string]$SourceRoot
)

# Convert build arch to QSysInfo format
$ArchMap = @{ "x64" = "x86_64"; "x86" = "i386"; "arm64" = "arm64" }
$QArch = $ArchMap[$Arch]

# Paths
$ServerDir = Join-Path $SourceRoot "server"
$BuildRoot = Join-Path $SourceRoot "build"
$BuildFolder = Join-Path $BuildRoot "build-$Arch-beta-$BuildType"
$ManifestFile = Join-Path $ServerDir "updates-beta.json"

Write-Host "Version: $Version"
Write-Host "Arch: $QArch (from build arch: $Arch)"
Write-Host "Build Type: $BuildType"
Write-Host "Server dir: $ServerDir"

# Ensure server directory exists
if (!(Test-Path $ServerDir)) {
    New-Item -ItemType Directory -Path $ServerDir -Force | Out-Null
}

# Find the MSI file
$MsiFile = Join-Path $BuildFolder "DancherLink-$Version.msi"

if (!(Test-Path $MsiFile)) {
    # Try alternative location
    $AltMsi = Join-Path $BuildRoot "installer-$Arch-beta-$BuildType\DancherLink-$Version.msi"
    if (Test-Path $AltMsi) {
        $MsiFile = $AltMsi
    } else {
        Write-Error "MSI not found: $MsiFile"
        exit 1
    }
}

Write-Host "Found MSI: $MsiFile"

# Copy MSI to server directory
$DestMsi = Join-Path $ServerDir "DancherLink-$QArch-$Version.msi"
Copy-Item $MsiFile $DestMsi -Force
Write-Host "Copied: $DestMsi"

# browser_url - relative path
$BrowserUrl = "DancherLink-$QArch-$Version.msi"

# Update manifest
$Manifest = @(
    @{
        platform = "windows"
        arch = $QArch
        version = $Version
        browser_url = $BrowserUrl
        isBeta = $true
    }
)

# Read existing manifest and merge if needed
if (Test-Path $ManifestFile) {
    try {
        $Existing = Get-Content $ManifestFile -Raw | ConvertFrom-Json
        # Keep other platform entries, update matching one
        foreach ($Entry in $Existing) {
            if ($Entry.platform -ne "windows" -or $Entry.arch -ne $QArch) {
                $Manifest += $Entry
            }
        }
    } catch {
        Write-Warning "Could not parse existing $ManifestFile, overwriting"
    }
}

# Write updated manifest
$Manifest | ConvertTo-Json -Depth 10 | Set-Content $ManifestFile -Encoding UTF8

Write-Host "Updated: $ManifestFile"
Write-Host "Done!"
