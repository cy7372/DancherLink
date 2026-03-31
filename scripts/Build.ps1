<#
.SYNOPSIS
    DancherLink Unified Build Script
.DESCRIPTION
    Builds the release or beta version of DancherLink using a single unified script.
.PARAMETER Type
    Build type: "release" (default) or "beta".
.PARAMETER Incremental
    Skip CMake configure and clean build for faster iteration.
.PARAMETER NoMsi
    Skip MSI packaging step.
.PARAMETER NoDeploy
    Skip Qt deployment step (windeployqt).
.EXAMPLE
    .\Build.ps1 -Type release
    Build stable release version.
.EXAMPLE
    .\Build.ps1 -Type beta
    Build beta version.
.EXAMPLE
    .\Build.ps1 -Type release -Incremental
    Incremental build (faster iteration).
.EXAMPLE
    .\Build.ps1 -Type beta -NoDeploy
    Build beta without Qt deployment.
#>

[CmdletBinding()]
param(
    [ValidateSet("release", "beta")]
    [string]$Type = "release",
    [switch]$Incremental,
    [switch]$NoMsi,
    [switch]$NoDeploy,
    [switch]$Help
)

if ($Help) {
    Write-Host "DancherLink Build System - Unified Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\Build.ps1 [-Type <release|beta>] [-Incremental] [-NoMsi] [-NoDeploy]" -ForegroundColor White
    Write-Host ""
    Write-Host "Parameters:" -ForegroundColor Cyan
    Write-Host "  -Type        Build type: 'release' (default) or 'beta'" -ForegroundColor White
    Write-Host "  -Incremental Skip CMake configure for faster iteration" -ForegroundColor White
    Write-Host "  -NoMsi       Skip MSI packaging step" -ForegroundColor White
    Write-Host "  -NoDeploy    Skip Qt deployment step" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\Build.ps1 -Type release    # Build stable release" -ForegroundColor White
    Write-Host "  .\Build.ps1 -Type beta       # Build beta version" -ForegroundColor White
    Write-Host "  .\Build.ps1 -Incremental     # Faster incremental build" -ForegroundColor White
    exit 0
}

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# Import common functions
. "$ScriptDir\Build-Common.ps1"

# Normalize build type for internal use
$BuildType = if ($Type -eq "beta") { "beta" } else { "Release" }
$BuildTypeParam = if ($Type -eq "beta") { "beta" } else { "release" }
$startTime = Get-Date

# Initialize
$Arch = Initialize-BuildEnvironment -BuildType $BuildType

# Read base version from version.txt (3-digit base, e.g., 1.0.11)
$BaseVersion = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }

# Get git commit count for build number
Set-Location $RootDir
$BuildNumber = git rev-list --count HEAD 2>$null
if (-not $BuildNumber) {
    $BuildNumber = 0
}
Set-Location $ScriptDir

# Version handling based on build type
if ($Type -eq "beta") {
    # Beta: 4-digit version (e.g., 1.0.11.1070)
    $Version = "${BaseVersion}.${BuildNumber}"
    $DisplayVersion = "$Version-beta"
    $RcVersion = $DisplayVersion
    $WixFile = "$RootDir\wix\DancherLink\Product-beta.wxs"
    Write-Host "[$BuildType Build] Base version: $BaseVersion" -ForegroundColor Green
    Write-Host "[$BuildType Build] Git commit count: $BuildNumber" -ForegroundColor Green
    Write-Host "[$BuildType Build] Beta version: $DisplayVersion" -ForegroundColor Green
} else {
    # Release: 3-digit version (e.g., 1.0.11)
    $Version = $BaseVersion
    $DisplayVersion = $Version
    # RC file needs 4-digit version (Windows requirement)
    $RcVersion = "${BaseVersion}.${BuildNumber}"
    $WixFile = "$RootDir\wix\DancherLink\Product.wxs"
    Write-Host "[$BuildType Build] Base version: $BaseVersion" -ForegroundColor Green
    Write-Host "[$BuildType Build] Git commit count: $BuildNumber" -ForegroundColor Green
    Write-Host "[$BuildType Build] Release version: $Version" -ForegroundColor Green
}

# Get paths (this also cleans directories if not incremental)
$Paths = Get-BuildPaths -RootDir $RootDir -Arch $Arch -BuildType $BuildTypeParam -Incremental:$Incremental
$CacheFolder = $Paths.CacheFolder      # CMake intermediate files (.obj, etc.)
$OutFolder = $Paths.OutFolder          # Final output directory
$DeployFolder = $Paths.DeployFolder    # Deployed app (exe + DLLs)
$InstallerFolder = $Paths.InstallerFolder  # MSI output (same as OutFolder)
$SymbolsFolder = $Paths.SymbolsFolder  # PDB files
$LogDir = $Paths.LogDir
$ReleaseFolder = $Paths.ReleaseFolder

# Start build logging
Start-BuildLogging -LogDir $LogDir

try {
    # Sync version to RC file
    Sync-RcVersion -Version $RcVersion -RcFile "$RootDir\app\DancherLink_resource.rc"

    # Generate translations
    Generate-Translations -LanguagesDir "$RootDir\app\languages"

    # Find Visual Studio
    Write-Host "[$BuildType Build] Setting up Visual Studio environment..." -ForegroundColor Green
    $VsWhere = "$ScriptDir\vswhere.exe"
    $VsInstallPath = & $VsWhere -latest -property installationPath

    # Build with Ninja
    $OpenSslPaths = @{
        Inc = "$RootDir\libs\windows\include\x64"
        Crypto = "$RootDir\libs\windows\lib\$Arch\libcrypto.lib"
        Ssl = "$RootDir\libs\windows\lib\$Arch\libssl.lib"
    }

    $BuildResult = Invoke-NativeBuild `
        -CacheFolder $CacheFolder `
        -RootDir $RootDir `
        -Arch $Arch `
        -BuildType $BuildTypeParam `
        -VsInstallPath $VsInstallPath `
        -OpenSslPaths $OpenSslPaths `
        -Version:$Version `
        -SkipConfigure:$false

    if ($BuildResult -ne 0) {
        throw "Build failed with exit code $BuildResult"
    }

    # Verify build output
    Write-Host "[$BuildType Build] Verifying build output..." -ForegroundColor Green
    $ExePath = Find-Executable -SearchPaths @("$CacheFolder\bin", "$CacheFolder\app") -Filter "DancherLink.exe"
    if (-not $ExePath) {
        throw "DancherLink.exe not found in build output!"
    }
    Write-Host "[$BuildType Build] Build output verified: $($ExePath.FullName)" -ForegroundColor Green

    # Save PDBs
    Copy-Symbols -CacheFolder $CacheFolder -SymbolsFolder $SymbolsFolder -Arch $Arch -RootDir $RootDir

    # Ensure deploy folder exists
    if (-not (Test-Path $DeployFolder)) {
        New-Item -ItemType Directory -Path $DeployFolder -Force | Out-Null
    }

    # Copy dependencies
    Copy-Dependencies -DeployFolder $DeployFolder -Arch $Arch -RootDir $RootDir -CacheFolder $CacheFolder

    # Deploy Qt (unless skipped)
    if (-not $NoDeploy) {
        Deploy-Qt -DeployFolder $DeployFolder -RootDir $RootDir -ExePath $ExePath.FullName -GuiDir "app\gui"
        Deploy-QtTranslations -DeployFolder $DeployFolder
        Remove-UnusedQtStyles -DeployFolder $DeployFolder
    } else {
        Write-Host "[$BuildType Build] Skipping Qt deployment (--NoDeploy)" -ForegroundColor Yellow
    }

    # Copy final binary to deploy folder BEFORE building MSI
    $FinalExe = Find-Executable -SearchPaths @("$CacheFolder\bin", "$CacheFolder\app") -Filter "DancherLink.exe"
    if ($FinalExe) {
        Copy-Item $FinalExe.FullName "$DeployFolder\" -Force
        Write-Host "[$BuildType Build] Copied DancherLink.exe to deploy folder" -ForegroundColor Green

        # Copy updater script (Windows only)
        $UpdaterBat = Join-Path $CacheFolder "bin\updater.bat"
        if (Test-Path $UpdaterBat) {
            Copy-Item $UpdaterBat "$DeployFolder\" -Force
            Write-Host "[$BuildType Build] Copied updater.bat to deploy folder" -ForegroundColor Green
        }
    } else {
        throw "DancherLink.exe not found in build output!"
    }

    # Build MSI (unless skipped)
    if (-not $NoMsi) {
        $MsiFile = Build-Msi `
            -InstallerFolder $InstallerFolder `
            -DeployFolder $DeployFolder `
            -BuildFolder $BuildFolder `
            -Version $Version `
            -WxsFile $WixFile `
            -Extensions $BuildConfig.WixExtensions

        # Generate differential patch (for incremental updates)
        Write-Host "[$BuildType Build] Generating differential patch..." -ForegroundColor Green
        Generate-Patch -RootDir $RootDir -DeployFolder $DeployFolder -Version $Version -BuildType $BuildTypeParam -Arch $Arch

        # Update manifest
        Update-Manifest -RootDir $RootDir -Version $Version -Arch $Arch -BuildType $BuildTypeParam
    } else {
        Write-Host "[$BuildType Build] Skipping MSI packaging (--NoMsi)" -ForegroundColor Yellow
        $MsiFile = $null
    }

    # Copy to release folder
    Write-Host "[$BuildType Build] Copying to release folder: $ReleaseFolder" -ForegroundColor Green
    Copy-ReleaseFiles -DeployFolder $DeployFolder -ReleaseFolder $ReleaseFolder -MsiFile $MsiFile -Version $Version -RootDir $RootDir -BuildType $BuildTypeParam

    # Calculate duration
    $endTime = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    $durationStr = "{0}h {1}m {2}s" -f $duration.Hours, $duration.Minutes, $duration.Seconds

    # Success
    Write-BuildSuccess -BuildType $BuildType -Version $Version -MsiPath $MsiFile -BuildDuration $durationStr

    # Build notes
    if ($Type -eq "beta") {
        Write-Host "[$BuildType Build] Beta build number is auto-calculated from git commit count" -ForegroundColor Cyan
    } else {
        Write-Host "[$BuildType Build] Remember to increment patch version in version.txt for next release" -ForegroundColor Cyan
    }

} catch {
    Write-Error "[$BuildType Build] $($_.Exception.Message)"
    Stop-BuildLogging
    exit 1
} finally {
    Stop-BuildLogging
}
