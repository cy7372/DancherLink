<#
.SYNOPSIS
    DancherLink Beta Build Script
.DESCRIPTION
    Builds the Beta/test version of DancherLink with separate installation directory.
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

Set-Location $RootDir

# Configuration
$Config = "Release"
$CMakeBuildType = "Release"

# Setup Qt path
if ($env:QTDIR) {
    $env:PATH = "$env:QTDIR\bin;$env:PATH"
} elseif (Test-Path "C:\Qt\6.10.1\msvc2022_64\bin") {
    $env:PATH = "C:\Qt\6.10.1\msvc2022_64\bin;$env:PATH"
}

# Verify qmake is available
if (-not (Get-Command qmake -ErrorAction SilentlyContinue)) {
    Write-Error "qmake not found in PATH. Please install Qt or set QTDIR."
    exit 1
}

Write-Host "[Beta Build] Starting build process..." -ForegroundColor Green

# Detect architecture
$QtPath = Split-Path (Get-Command qmake).Source -Parent
if ($QtPath -like "*_arm64*") {
    $Arch = "arm64"
} elseif ($QtPath -like "*_64*") {
    $Arch = "x64"
} else {
    $Arch = "x86"
}

Write-Host "[Beta Build] Architecture: $Arch" -ForegroundColor Green

# Read Beta version
if (Test-Path "$RootDir\app\version_beta.txt") {
    $Version = (Get-Content "$RootDir\app\version_beta.txt" | ForEach-Object { $_.Trim() })
} else {
    # Auto-generate beta version from main version
    $BaseVersion = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }
    $Version = "${BaseVersion}-beta"
    Write-Host "[Beta Build] Warning: version_beta.txt not found, using $Version" -ForegroundColor Yellow
}

# Ensure version has -beta suffix
if ($Version -notlike "*-beta*") {
    $Version = "${Version}-beta"
}

Write-Host "[Beta Build] Version: $Version" -ForegroundColor Green

# Build directories - use beta-specific paths
$BuildRoot = "$RootDir\build"
$BuildFolder = "$BuildRoot\build-$Arch-beta-release"
$DeployFolder = "$BuildRoot\deploy-$Arch-beta-release"
$InstallerFolder = "$BuildRoot\installer-$Arch-beta-release"
$SymbolsFolder = "$RootDir\symbols-$Arch-beta-release"

# Clean output directories
Write-Host "[Beta Build] Cleaning output directories..." -ForegroundColor Green
if (Test-Path $DeployFolder) { Remove-Item -Recurse -Force $DeployFolder }
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
if (Test-Path $InstallerFolder) { Remove-Item -Recurse -Force $InstallerFolder }
if (Test-Path $SymbolsFolder) { Remove-Item -Recurse -Force $SymbolsFolder }
New-Item -ItemType Directory -Path $BuildRoot, $DeployFolder, $BuildFolder, $InstallerFolder, $SymbolsFolder | Out-Null

# Sync version to RC file (beta uses same RC version as release)
Write-Host "[Beta Build] Syncing version to RC file..." -ForegroundColor Green
& powershell -ExecutionPolicy Bypass -File "$ScriptDir\update_rc_version.ps1" `
    -VersionFile "$RootDir\app\version.txt" `
    -RcFile "$RootDir\app\DancherLink_resource.rc"

# Generate translations
Write-Host "[Beta Build] Generating translations..." -ForegroundColor Green
Push-Location "$RootDir\app\languages"
Get-ChildItem *.ts | ForEach-Object {
    Write-Host "  Processing $($_.Name)..."
    lrelease $_.Name
}
Pop-Location

# Find Visual Studio and setup environment
Write-Host "[Beta Build] Setting up Visual Studio environment..." -ForegroundColor Green
$VsWhere = "$ScriptDir\vswhere.exe"
$VsInstallPath = & $VsWhere -latest -property installationPath
$VcArch = "AMD64"

# Run vcvarsall.bat and capture environment
$VcVarsCmd = "& `"$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat`" $VcArch"
$EnvVars = cmd /c "$VcVarsCmd && set" | ForEach-Object {
    if ($_ -match '^(\w+)=(.*)$') {
        Set-Item -Force -Path "ENV:\$($matches[1])" -Value $matches[2]
    }
}

# Find VC redistributable
$VcRedistPath = & $VsWhere -latest -find "VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT"

# Configure CMake with Beta identifier
Write-Host "[Beta Build] Configuring CMake..." -ForegroundColor Green
$OpenSslInc = "$RootDir\libs\windows\include\x64"

cmake -S "$RootDir" -B "$BuildFolder" -G "Ninja" `
    -DCMAKE_BUILD_TYPE="$CMakeBuildType" `
    -DCMAKE_VERBOSE_MAKEFILE=ON `
    -DARCH_DIR="$Arch" `
    -DBUILD_TYPE="beta" `
    -DOPENSSL_INCLUDE_DIR="$OpenSslInc" `
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/$Arch/libcrypto.lib" `
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/$Arch/libssl.lib"

# Build
Write-Host "[Beta Build] Compiling..." -ForegroundColor Green
cmake --build "$BuildFolder" --config "$CMakeBuildType" --parallel

# Save PDBs
Write-Host "[Beta Build] Saving PDBs..." -ForegroundColor Green
Get-ChildItem -Recurse -Filter "*.pdb" -Path "$BuildFolder" | ForEach-Object {
    Copy-Item $_.FullName "$SymbolsFolder\" -Force
}
Get-ChildItem "$RootDir\libs\windows\lib\$Arch\*.pdb" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName "$SymbolsFolder\" -Force
}

# Copy dependencies
Write-Host "[Beta Build] Copying dependencies..." -ForegroundColor Green
Copy-Item "$RootDir\libs\windows\lib\$Arch\*.dll" "$DeployFolder\" -Force -ErrorAction SilentlyContinue

# Copy moonlight-common-c.dll
$MoonlightDll = Get-ChildItem -Recurse -Filter "moonlight-common-c.dll" -Path "$BuildFolder" | Select-Object -First 1
if ($MoonlightDll) {
    Copy-Item $MoonlightDll.FullName "$DeployFolder\" -Force
}

# Copy GC mapping
Copy-Item "$RootDir\app\SDL_GameControllerDB\gamecontrollerdb.txt" "$DeployFolder\" -Force

# Deploy Qt
Write-Host "[Beta Build] Deploying Qt dependencies..." -ForegroundColor Green
$WindeployqtArgs = @(
    "--dir", $DeployFolder
    "--release"
    "--qmldir", "$RootDir\app\gui"
    "--no-opengl-sw"
    "--no-compiler-runtime"
    "--no-sql"
    "--no-system-d3d-compiler"
    "--no-system-dxc-compiler"
    "--skip-plugin-types", "qmltooling,generic"
    "--no-ffmpeg"
    "--no-quickcontrols2fusion"
    "--no-quickcontrols2imagine"
    "--no-quickcontrols2universal"
    "--no-quickcontrols2fusionstyleimpl"
    "--no-quickcontrols2imaginestyleimpl"
    "--no-quickcontrols2universalstyleimpl"
    "--no-quickcontrols2windowsstyleimpl"
    "--no-translations"
)

$ExePath = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin\Release","$BuildFolder\app\Release" | Select-Object -First 1
if (-not $ExePath) {
    Write-Error "DancherLink.exe not found in build output!"
    exit 1
}

windeployqt @WindeployqtArgs $ExePath.FullName

# Deploy translations
$TranslationsDir = "$DeployFolder\translations"
New-Item -ItemType Directory -Path $TranslationsDir -Force | Out-Null
"$QtPath\..\translations\qt_zh_CN.qm",
"$QtPath\..\translations\qtbase_zh_CN.qm",
"$QtPath\..\translations\qtquick_zh_CN.qm",
"$QtPath\..\translations\qtmultimedia_zh_CN.qm" | Where-Object { Test-Path $_ } | ForEach-Object {
    Copy-Item $_ "$TranslationsDir\" -Force
}

# Delete unused styles
Write-Host "[Beta Build] Removing unused Qt styles..." -ForegroundColor Green
"@{Fusion;Imagine;Universal;Windows;NativeStyle}" | ForEach-Object {
    $styles = $_.Keys
    foreach ($style in $styles) {
        $path = "$DeployFolder\qml\QtQuick\Controls\$style"
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
        $path = "$DeployFolder\qml\QtQuick\Controls\$($style)StyleImpl"
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
    }
}
if (Test-Path "$DeployFolder\qml\QtQuick\NativeStyle") {
    Remove-Item -Recurse -Force "$DeployFolder\qml\QtQuick\NativeStyle"
}

# Build Beta MSI using Product-beta.wxs
Write-Host "[Beta Build] Building Beta MSI installer..." -ForegroundColor Green
$AppConfigDir = "$BuildFolder\app\release"
if (-not (Test-Path $AppConfigDir)) { New-Item -ItemType Directory -Path $AppConfigDir | Out-Null }
$BuiltExe = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin\Release","$BuildFolder\app\Release" | Select-Object -First 1
if ($BuiltExe) { Copy-Item $BuiltExe.FullName "$AppConfigDir\" -Force }

msbuild -Restore "$RootDir\wix\DancherLink\DancherLink.wixproj" `
    /p:Configuration="Release" `
    /p:Platform="$Arch" `
    /p:MSBuildProjectExtensionsPath="$BuildFolder/" `
    /p:Version="$Version" `
    /p:ProductWxs="Product-beta.wxs"

# Copy final binary
$FinalExe = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin","$BuildFolder\app" | Select-Object -First 1
if ($FinalExe) { Copy-Item $FinalExe.FullName "$DeployFolder\" -Force }

# Create portable package for Beta
Write-Host "[Beta Build] Creating Beta portable package..." -ForegroundColor Green
Copy-Item "$VcRedistPath\*.dll" "$DeployFolder\" -Force
New-Item "$DeployFolder\portable.dat" -ItemType File -Force | Out-Null
& 7z a "$InstallerFolder\DancherLinkPortable-$Arch-$Version.zip" "$DeployFolder\*"

# Copy MSI to installer folder
$MsiFile = Get-ChildItem -Recurse -Filter "DancherLink.msi" -Path "$BuildFolder" | Select-Object -First 1
if ($MsiFile) {
    Copy-Item $MsiFile.FullName "$InstallerFolder\DancherLink-x86_64-$Version.msi" -Force
}

# Update Beta manifest
if (Test-Path "$RootDir\server") {
    Write-Host "[Beta Build] Updating server/updates-beta.json..." -ForegroundColor Green
    python "$RootDir\server\update_version.py" "$Version" "$Arch" "release" "$RootDir" "beta"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "[Beta Build] Build successful!" -ForegroundColor Green
Write-Host "  Version: $Version" -ForegroundColor Yellow
Write-Host "  MSI: $InstallerFolder\DancherLink-x86_64-$Version.msi" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
