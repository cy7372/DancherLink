<#
.SYNOPSIS
    DancherLink Beta Build Script
.DESCRIPTION
    Builds the Beta/test version of DancherLink with separate installation directory using Ninja for faster builds.
#>

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
Set-Location $RootDir

# Import common functions
. "$ScriptDir\Build-Common.ps1"

$BuildType = "Beta"

# Initialize
$Arch = Initialize-BuildEnvironment -BuildType $BuildType

# Read Beta version
if (Test-Path "$RootDir\app\version_beta.txt") {
    $Version = (Get-Content "$RootDir\app\version_beta.txt" | ForEach-Object { $_.Trim() })
} else {
    # Auto-generate beta version from main version
    $BaseVersion = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }
    $Version = "${BaseVersion}-beta"
    Write-Host "[$BuildType Build] Warning: version_beta.txt not found, using $Version" -ForegroundColor Yellow
}

# Ensure version has -beta suffix
if ($Version -notlike "*-beta*") {
    $Version = "${Version}-beta"
}

Write-Host "[$BuildType Build] Version: $Version" -ForegroundColor Green

# Get paths
$Paths = Get-BuildPaths -RootDir $RootDir -Arch $Arch -BuildType "beta"
$BuildFolder = $Paths.BuildFolder
$DeployFolder = $Paths.DeployFolder
$InstallerFolder = $Paths.InstallerFolder
$SymbolsFolder = $Paths.SymbolsFolder

# Clean directories
Clean-BuildDirectories -Paths @($DeployFolder, $BuildFolder, $InstallerFolder, $SymbolsFolder)

# Sync version to RC file (beta uses same RC version as release)
Sync-RcVersion -VersionFile "$RootDir\app\version.txt" -RcFile "$RootDir\app\DancherLink_resource.rc"

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
    -OpenSslPaths $OpenSslPaths

if ($BuildResult -ne 0) {
    Write-Error "[$BuildType Build] Build failed with exit code $BuildResult"
    exit $BuildResult
}

# Verify build output
Write-Host "[$BuildType Build] Verifying build output..." -ForegroundColor Green
$ExePath = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
if (-not $ExePath) {
    Write-Error "[$BuildType Build] DancherLink.exe not found in build output!"
    exit 1
}
Write-Host "[$BuildType Build] Build output verified: $($ExePath.FullName)" -ForegroundColor Green

# Save PDBs
Copy-Symbols -BuildFolder $BuildFolder -SymbolsFolder $SymbolsFolder -Arch $Arch -RootDir $RootDir

# Copy dependencies
Copy-Dependencies -DeployFolder $DeployFolder -Arch $Arch -RootDir $RootDir -BuildFolder $BuildFolder

# Deploy Qt
Deploy-Qt -DeployFolder $DeployFolder -RootDir $RootDir -ExePath $ExePath.FullName

# Deploy translations
Deploy-QtTranslations -DeployFolder $DeployFolder

# Remove unused styles
Remove-UnusedQtStyles -DeployFolder $DeployFolder

# Build MSI (beta uses Product-beta.wxs, no extensions needed)
$MsiFile = Build-Msi `
    -InstallerFolder $InstallerFolder `
    -DeployFolder $DeployFolder `
    -BuildFolder $BuildFolder `
    -Version $Version `
    -WxsFile "$RootDir\wix\DancherLink\Product-beta.wxs" `
    -Extensions @()

# Copy final binary
$FinalExe = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
if ($FinalExe) { Copy-Item $FinalExe.FullName "$DeployFolder\" -Force }

# Update manifest
Update-Manifest -RootDir $RootDir -Version $Version -Arch $Arch -BuildType "beta"

# Success
Write-BuildSuccess -BuildType $BuildType -Version $Version -MsiPath $MsiFile
