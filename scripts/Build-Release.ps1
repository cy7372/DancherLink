<#
.SYNOPSIS
    DancherLink Release Build Script
.DESCRIPTION
    Builds the stable release version of DancherLink using Ninja for faster builds.
.PARAMETER Incremental
    Skip CMake configure and clean build for faster iteration.
.PARAMETER NoMsi
    Skip MSI packaging step.
.PARAMETER NoDeploy
    Skip Qt deployment step (windeployqt).
#>

[CmdletBinding()]
param(
    [switch]$Incremental,
    [switch]$NoMsi,
    [switch]$NoDeploy
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# Import common functions
. "$ScriptDir\Build-Common.ps1"

$BuildType = "Release"
$startTime = Get-Date

# Initialize
$Arch = Initialize-BuildEnvironment -BuildType $BuildType

# Read base version from version.txt (3-digit for Release, e.g., 1.0.11)
$BaseVersion = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }

# Get git commit count for build number (used for RC file, not for Release MSI name)
Set-Location $RootDir
$BuildNumber = git rev-list --count HEAD 2>$null
if (-not $BuildNumber) {
    $BuildNumber = 0
}
Set-Location $ScriptDir

# Release version uses 3-digit format (e.g., 1.0.11)
$Version = $BaseVersion
# RC file needs 4-digit version (Windows requirement): major.minor.build.revision
$RcVersion = "${BaseVersion}.${BuildNumber}"

Write-Host "[$BuildType Build] Base version: $BaseVersion" -ForegroundColor Green
Write-Host "[$BuildType Build] Git commit count: $BuildNumber" -ForegroundColor Green
Write-Host "[$BuildType Build] Release version: $Version" -ForegroundColor Green

# Get paths (this also cleans directories if not incremental)
$Paths = Get-BuildPaths -RootDir $RootDir -Arch $Arch -BuildType $BuildType -Incremental:$Incremental
$BuildFolder = $Paths.BuildFolder
$DeployFolder = $Paths.DeployFolder
$InstallerFolder = $Paths.InstallerFolder
$SymbolsFolder = $Paths.SymbolsFolder
$LogDir = $Paths.LogDir
$ReleaseFolder = $Paths.ReleaseFolder

# Start build logging
Start-BuildLogging -LogDir $LogDir

try {
    # Sync version to RC file (4-digit format for Windows)
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
        -BuildFolder $BuildFolder `
        -RootDir $RootDir `
        -Arch $Arch `
        -BuildType $BuildType `
        -VsInstallPath $VsInstallPath `
        -OpenSslPaths $OpenSslPaths `
        -SkipConfigure:$false

    if ($BuildResult -ne 0) {
        throw "Build failed with exit code $BuildResult"
    }

    # Verify build output
    Write-Host "[$BuildType Build] Verifying build output..." -ForegroundColor Green
    $ExePath = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
    if (-not $ExePath) {
        throw "DancherLink.exe not found in build output!"
    }
    Write-Host "[$BuildType Build] Build output verified: $($ExePath.FullName)" -ForegroundColor Green

    # Save PDBs
    Copy-Symbols -BuildFolder $BuildFolder -SymbolsFolder $SymbolsFolder -Arch $Arch -RootDir $RootDir

    # Copy dependencies
    Copy-Dependencies -DeployFolder $DeployFolder -Arch $Arch -RootDir $RootDir -BuildFolder $BuildFolder

    # Deploy Qt (unless skipped)
    if (-not $NoDeploy) {
        Deploy-Qt -DeployFolder $DeployFolder -RootDir $RootDir -ExePath $ExePath.FullName -GuiDir "app\gui"
        Deploy-QtTranslations -DeployFolder $DeployFolder
        Remove-UnusedQtStyles -DeployFolder $DeployFolder
    } else {
        Write-Host "[$BuildType Build] Skipping Qt deployment (--NoDeploy)" -ForegroundColor Yellow
    }

    # Copy final binary to deploy folder BEFORE building MSI (Deploy-Qt removes it after deployment)
    $FinalExe = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
    if ($FinalExe) {
        Copy-Item $FinalExe.FullName "$DeployFolder\" -Force
        Write-Host "[$BuildType Build] Copied DancherLink.exe to deploy folder" -ForegroundColor Green
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
            -WxsFile "$RootDir\wix\DancherLink\Product.wxs" `
            -Extensions $BuildConfig.WixExtensions

        # Update manifest
        Update-Manifest -RootDir $RootDir -Version $Version -Arch $Arch -BuildType "release"
    } else {
        Write-Host "[$BuildType Build] Skipping MSI packaging (--NoMsi)" -ForegroundColor Yellow
        $MsiFile = $null
    }

    # Copy to release folder
    Write-Host "[$BuildType Build] Copying to release folder: $ReleaseFolder" -ForegroundColor Green
    Copy-ReleaseFiles -DeployFolder $DeployFolder -ReleaseFolder $ReleaseFolder -MsiFile $MsiFile -Version $Version -RootDir $RootDir -BuildType "release"

    # Calculate duration
    $endTime = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    $durationStr = "{0}h {1}m {2}s" -f $duration.Hours, $duration.Minutes, $duration.Seconds

    # Success
    Write-BuildSuccess -BuildType $BuildType -Version $Version -MsiPath $MsiFile -BuildDuration $durationStr

    # Note: Patch version should be manually incremented in version.txt for Release builds
    # Build number is automatically calculated from git commit count

} catch {
    Write-Error "[$BuildType Build] $($_.Exception.Message)"
    Stop-BuildLogging
    exit 1
} finally {
    Stop-BuildLogging
}
