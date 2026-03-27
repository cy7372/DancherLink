<#
.SYNOPSIS
    DancherLink Release Build Script
.DESCRIPTION
    Builds the stable release version of DancherLink.
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

Write-Host "[Release Build] Starting build process..." -ForegroundColor Green

# Detect architecture
$QtPath = Split-Path (Get-Command qmake).Source -Parent
if ($QtPath -like "*_arm64*") {
    $Arch = "arm64"
} elseif ($QtPath -like "*_64*") {
    $Arch = "x64"
} else {
    $Arch = "x86"
}

Write-Host "[Release Build] Architecture: $Arch" -ForegroundColor Green

# Read version
$Version = Get-Content "$RootDir\app\version.txt" | ForEach-Object { $_.Trim() }
Write-Host "[Release Build] Version: $Version" -ForegroundColor Green

# Build directories
$BuildRoot = "$RootDir\build"
$BuildFolder = "$BuildRoot\build-$Arch-release"
$DeployFolder = "$BuildRoot\deploy-$Arch-release"
$InstallerFolder = "$BuildRoot\installer-$Arch-release"
$SymbolsFolder = "$BuildRoot\symbols-$Arch-release"

# Clean output directories
Write-Host "[Release Build] Cleaning output directories..." -ForegroundColor Green
if (Test-Path $DeployFolder) { Remove-Item -Recurse -Force $DeployFolder }
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
if (Test-Path $InstallerFolder) { Remove-Item -Recurse -Force $InstallerFolder }
if (Test-Path $SymbolsFolder) { Remove-Item -Recurse -Force $SymbolsFolder }
New-Item -ItemType Directory -Path $DeployFolder, $BuildFolder, $InstallerFolder, $SymbolsFolder -Force | Out-Null

# Sync version to RC file
Write-Host "[Release Build] Syncing version to RC file..." -ForegroundColor Green
& powershell -ExecutionPolicy Bypass -File "$ScriptDir\update_rc_version.ps1" `
    -VersionFile "$RootDir\app\version.txt" `
    -RcFile "$RootDir\app\DancherLink_resource.rc"

# Generate translations
Write-Host "[Release Build] Generating translations..." -ForegroundColor Green
Push-Location "$RootDir\app\languages"
Get-ChildItem *.ts | ForEach-Object {
    Write-Host "  Processing $($_.Name)..."
    lrelease $_.Name
}
Pop-Location

# Find Visual Studio and setup environment
Write-Host "[Release Build] Setting up Visual Studio environment..." -ForegroundColor Green
$VsWhere = "$ScriptDir\vswhere.exe"
$VsInstallPath = & $VsWhere -latest -property installationPath
$VcArch = "AMD64"

Write-Host "[Release Build] Using native cmd.exe for build to avoid MSVC temp file issues..." -ForegroundColor Green

# Create a temporary batch file that runs the entire build in a clean cmd.exe environment
$BuildBatch = "$BuildFolder\do-build.bat"
$VcVarsAll = "$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"

# Generate unique temp directory for this build
$CleanTemp = "C:\build-temp-$(Get-Random)"

# Define OpenSSL paths
$OpenSslInc = "$RootDir\libs\windows\include\x64"

# Create the build batch file
$BatchContent = @"
@echo off
echo ========================================
echo DancherLink Release Build
echo ========================================
call "$VcVarsAll" $VcArch

echo Setting up clean temp directory...
set CLEAN_TEMP=$CleanTemp
if not exist "%CLEAN_TEMP%" mkdir "%CLEAN_TEMP%"
set TMP=%CLEAN_TEMP%
set TEMP=%CLEAN_TEMP%
set TMPDIR=%CLEAN_TEMP%
echo Using temp dir: %TMP%

echo Setting up Qt path...
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
set Qt6_DIR=C:\Qt\6.10.1\msvc2022_64\lib\cmake\Qt6

cd /d "$BuildFolder"

echo Running cmake configure...
cmake -S "$RootDir" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE="$CMakeBuildType" -DCMAKE_VERBOSE_MAKEFILE=ON -DARCH_DIR="$Arch" -DOPENSSL_INCLUDE_DIR="$OpenSslInc" -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/$Arch/libcrypto.lib" -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/$Arch/libssl.lib"

if %ERRORLEVEL% neq 0 (
    echo CMake configuration FAILED
    goto :cleanup
)
echo CMake configuration SUCCESS

echo.
echo Building...
cmake --build . --config "$CMakeBuildType" --parallel 1

echo.
echo Build exit code: %ERRORLEVEL%

:cleanup
echo Cleaning up temp directory...
if exist "%CLEAN_TEMP%" rmdir /s /q "%CLEAN_TEMP%"
if %ERRORLEVEL% neq 0 (
    echo Build FAILED
    exit /b %ERRORLEVEL%
)
echo Build SUCCESS
"@

Set-Content -Path $BuildBatch -Value $BatchContent -Encoding ASCII

# Run the build in native cmd.exe
Write-Host "[Release Build] Running build in native cmd.exe environment..." -ForegroundColor Green
cmd.exe /c "$BuildBatch" 2>&1

$BuildResult = $LASTEXITCODE

# Cleanup batch file
Remove-Item $BuildBatch -ErrorAction SilentlyContinue

if ($BuildResult -ne 0) {
    Write-Error "[Release Build] Build failed with exit code $BuildResult"
    exit $BuildResult
}

Write-Host "[Release Build] Verifying build output..." -ForegroundColor Green
$ExePath = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin","$BuildFolder\app" | Select-Object -First 1
if (-not $ExePath) {
    Write-Error "[Release Build] DancherLink.exe not found in build output!"
    exit 1
}
Write-Host "[Release Build] Build output verified: $($ExePath.FullName)" -ForegroundColor Green

# Find VC redistributable
$VcRedistPath = & $VsWhere -latest -find "VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT"

# Save PDBs
Write-Host "[Release Build] Saving PDBs..." -ForegroundColor Green
Get-ChildItem -Recurse -Filter "*.pdb" -Path "$BuildFolder" | ForEach-Object {
    Copy-Item $_.FullName "$SymbolsFolder\" -Force
}
Get-ChildItem "$RootDir\libs\windows\lib\$Arch\*.pdb" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName "$SymbolsFolder\" -Force
}

# Copy dependencies
Write-Host "[Release Build] Copying dependencies..." -ForegroundColor Green
Copy-Item "$RootDir\libs\windows\lib\$Arch\*.dll" "$DeployFolder\" -Force -ErrorAction SilentlyContinue

# Copy moonlight-common-c.dll
$MoonlightDll = Get-ChildItem -Recurse -Filter "moonlight-common-c.dll" -Path "$BuildFolder" | Select-Object -First 1
if ($MoonlightDll) {
    Copy-Item $MoonlightDll.FullName "$DeployFolder\" -Force
}

# Copy GC mapping
Copy-Item "$RootDir\app\SDL_GameControllerDB\gamecontrollerdb.txt" "$DeployFolder\" -Force

# Deploy Qt
Write-Host "[Release Build] Deploying Qt dependencies..." -ForegroundColor Green
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

$ExePath = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin","$BuildFolder\app" | Select-Object -First 1
if (-not $ExePath) {
    Write-Error "DancherLink.exe not found in build output!"
    exit 1
}
Write-Host "[Release Build] Found DancherLink.exe: $($ExePath.FullName)" -ForegroundColor Green

# Copy executable to deploy folder temporarily for windeployqt
$DeployBinExe = "$DeployFolder\DancherLink.exe"
Copy-Item $ExePath.FullName $DeployBinExe -Force
Write-Host "[Release Build] Copied DancherLink.exe to deploy folder for windeployqt" -ForegroundColor Green

windeployqt @WindeployqtArgs $DeployBinExe

# Remove the exe from deploy folder - WiX will add it separately
Remove-Item $DeployBinExe -Force
Write-Host "[Release Build] Removed DancherLink.exe from deploy folder (will be added by WiX)" -ForegroundColor Green

# Deploy translations
$TranslationsDir = "$DeployFolder\translations"
New-Item -ItemType Directory -Path $TranslationsDir -Force | Out-Null
$QtPath = "C:\Qt\6.10.1\msvc2022_64\bin"
"$QtPath\..\translations\qt_zh_CN.qm",
"$QtPath\..\translations\qtbase_zh_CN.qm",
"$QtPath\..\translations\qtquick_zh_CN.qm",
"$QtPath\..\translations\qtmultimedia_zh_CN.qm" | Where-Object { Test-Path $_ } | ForEach-Object {
    Copy-Item $_ "$TranslationsDir\" -Force
}

# Delete unused styles
Write-Host "[Release Build] Removing unused Qt styles..." -ForegroundColor Green
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

# Build MSI
Write-Host "[Release Build] Building MSI installer..." -ForegroundColor Green
$AppConfigDir = "$BuildFolder\app\release"
if (-not (Test-Path $AppConfigDir)) { New-Item -ItemType Directory -Path $AppConfigDir | Out-Null }
$BuiltExe = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin","$BuildFolder\app" | Select-Object -First 1
if ($BuiltExe) { Copy-Item $BuiltExe.FullName "$AppConfigDir\" -Force }

# Use WiX CLI instead of MSBuild to avoid Aspire compatibility issues
$WixExe = "wix"
Write-Host "[Release Build] Using WiX CLI: $WixExe" -ForegroundColor Green
$Configuration = "Release"

# Build MSI using wix build command with extensions
$WixArgs = @("build",
    "-arch", "x64",
    "-out", "$InstallerFolder\DancherLink-x86_64-$Version.msi",
    "-b", "$DeployFolder",
    "-d", "Version=$Version",
    "-d", "BuildDir=$BuildFolder",
    "-d", "DeployDir=$DeployFolder",
    "-d", "Configuration=$Configuration",
    "-ext", "WixToolset.Util.wixext",
    "-ext", "WixToolset.Firewall.wixext",
    "$RootDir\wix\DancherLink\Product.wxs")

Write-Host "[Release Build] Running: wix build..." -ForegroundColor Green
$WixOutput = & $WixExe $WixArgs 2>&1
Write-Host $WixOutput

# Copy MSI to build folder for update_version.py
$MsiFile = "$InstallerFolder\DancherLink-x86_64-$Version.msi"
if (Test-Path $MsiFile) {
    Copy-Item $MsiFile "$BuildFolder\DancherLink.msi" -Force
    Write-Host "[Release Build] MSI created: $MsiFile" -ForegroundColor Green
} else {
    Write-Host "[Release Build] Warning: MSI file not found after build" -ForegroundColor Yellow
}

# Copy final binary (already copied above, just verify)
$FinalExe = Get-ChildItem -Recurse -Filter "DancherLink.exe" -Path "$BuildFolder\bin","$BuildFolder\app" | Select-Object -First 1
if ($FinalExe -and -not (Test-Path "$DeployFolder\DancherLink.exe")) {
    Copy-Item $FinalExe.FullName "$DeployFolder\" -Force
}

# Create portable package
Write-Host "[Release Build] Creating portable package..." -ForegroundColor Green
Copy-Item "$VcRedistPath\*.dll" "$DeployFolder\" -Force
New-Item "$DeployFolder\portable.dat" -ItemType File -Force | Out-Null
& 7z a "$InstallerFolder\DancherLinkPortable-$Arch-$Version.zip" "$DeployFolder\*"

# Copy MSI to installer folder
$MsiFile = Get-ChildItem -Recurse -Filter "DancherLink.msi" -Path "$BuildFolder" | Select-Object -First 1
if ($MsiFile) {
    Copy-Item $MsiFile.FullName "$InstallerFolder\DancherLink-x86_64-$Version.msi" -Force
}

# Update manifest
if ((Test-Path "$RootDir\server") -and (Test-Path "$RootDir\server\update_version.py")) {
    Write-Host "[Release Build] Updating server/updates.json..." -ForegroundColor Green
    python "$RootDir\server\update_version.py" "$Version" "$Arch" "release" "$RootDir" "release"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "[Release Build] Build successful!" -ForegroundColor Green
Write-Host "  Version: $Version" -ForegroundColor Yellow
Write-Host "  MSI: $InstallerFolder\DancherLink-x86_64-$Version.msi" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green
