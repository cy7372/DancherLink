<#
.SYNOPSIS
    DancherLink Beta Build Script
.DESCRIPTION
    Builds the beta version of DancherLink. Beta shares the same release folder as stable but with -beta suffix in filename.
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

$BuildType = "Beta"
$startTime = Get-Date

# Initialize
$Arch = Initialize-BuildEnvironment -BuildType $BuildType

# Read base version from version.txt (3-digit for Release, e.g., 1.0.11)
$BaseVersion = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }

# Get git commit count for build number
Set-Location $RootDir
$BuildNumber = git rev-list --count HEAD 2>$null
if (-not $BuildNumber) {
    $BuildNumber = 0
}
Set-Location $ScriptDir

# Beta version = base version + build number (e.g., 1.0.11.1070)
$Version = "${BaseVersion}.${BuildNumber}"
$DisplayVersion = "$Version-beta"

Write-Host "[$BuildType Build] Base version: $BaseVersion" -ForegroundColor Green
Write-Host "[$BuildType Build] Git commit count: $BuildNumber" -ForegroundColor Green
Write-Host "[$BuildType Build] Beta version: $DisplayVersion" -ForegroundColor Green

# Get paths
$Paths = Get-BuildPaths -RootDir $RootDir -Arch $Arch -BuildType "beta" -Incremental:$Incremental
$BuildFolder = $Paths.BuildFolder
$DeployFolder = $Paths.DeployFolder
$InstallerFolder = $Paths.InstallerFolder
$SymbolsFolder = $Paths.SymbolsFolder
$LogDir = $Paths.LogDir
$ReleaseFolder = $Paths.ReleaseFolder

# Start build logging
Start-BuildLogging -LogDir $LogDir

try {
    # Sync version to RC file - use full Beta version (e.g., 1.0.11.180)
    Sync-RcVersion -Version $DisplayVersion -RcFile "$RootDir\app\DancherLink_resource.rc"

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
        -BuildType "beta" `
        -VsInstallPath $VsInstallPath `
        -OpenSslPaths $OpenSslPaths `
        -Version $DisplayVersion `
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

    # Copy final binary before building MSI
    $FinalExe = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
    if ($FinalExe) {
        Copy-Item $FinalExe.FullName "$DeployFolder\" -Force
        Write-Host "[$BuildType Build] Copied DancherLink.exe to deploy folder" -ForegroundColor Green
    }

    # Build MSI (unless skipped)
    if (-not $NoMsi) {
        $MsiFile = Build-Msi `
            -InstallerFolder $InstallerFolder `
            -DeployFolder $DeployFolder `
            -BuildFolder $BuildFolder `
            -Version $Version `
            -WxsFile "$RootDir\wix\DancherLink\Product-beta.wxs" `
            -Extensions @("WixToolset.Util.wixext", "WixToolset.Firewall.wixext")

        # Update manifest
        Update-Manifest -RootDir $RootDir -Version $Version -Arch $Arch -BuildType "beta"
    } else {
        Write-Host "[$BuildType Build] Skipping MSI packaging (--NoMsi)" -ForegroundColor Yellow
        $MsiFile = $null
    }

    # Copy to release folder
    Write-Host "[$BuildType Build] Copying to release folder: $ReleaseFolder" -ForegroundColor Green
    Copy-ReleaseFiles -DeployFolder $DeployFolder -ReleaseFolder $ReleaseFolder -MsiFile $MsiFile -Version $Version -RootDir $RootDir -BuildType "beta"

    # Calculate duration
    $endTime = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    $durationStr = "{0}h {1}m {2}s" -f $duration.Hours, $duration.Minutes, $duration.Seconds

    # Success
    Write-BuildSuccess -BuildType $BuildType -Version $Version -MsiPath $MsiFile -BuildDuration $durationStr

    # Note: Build number is now automatically calculated from git commit count
    # No need to manually increment version.txt for Beta builds

} catch {
    Write-Error "[$BuildType Build] $($_.Exception.Message)"
    Stop-BuildLogging
    exit 1
} finally {
    Stop-BuildLogging
}
