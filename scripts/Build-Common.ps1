<#
.SYNOPSIS
    DancherLink Common Build Functions
.DESCRIPTION
    Shared functions for Release and Beta builds.
#>

# Common build configuration
$Script:CommonConfig = @{
    QtPath = if ($env:QTDIR) { "$env:QTDIR\bin" } else { "C:\Qt\6.10.1\msvc2022_64\bin" }
    QtCMakeDir = "C:\Qt\6.10.1\msvc2022_64\lib\cmake\Qt6"
    OpenSslInc = "$PSScriptRoot\..\libs\windows\include\x64"
    VcArch = "AMD64"
    CMakeBuildType = "Release"
}

function Initialize-BuildEnvironment {
    param(
        [string]$BuildType
    )

    Write-Host "[$BuildType Build] Starting build process..." -ForegroundColor Green

    # Setup Qt path
    $env:PATH = "$($Script:CommonConfig.QtPath);$env:PATH"

    # Verify qmake is available
    if (-not (Get-Command qmake -ErrorAction SilentlyContinue)) {
        Write-Error "qmake not found in PATH. Please install Qt or set QTDIR."
        exit 1
    }

    # Detect architecture
    $QtPath = Split-Path (Get-Command qmake).Source -Parent
    if ($QtPath -like "*_arm64*") {
        $Arch = "arm64"
    } elseif ($QtPath -like "*_64*") {
        $Arch = "x64"
    } else {
        $Arch = "x86"
    }

    Write-Host "[$BuildType Build] Architecture: $Arch" -ForegroundColor Green

    return $Arch
}

function Get-BuildPaths {
    param(
        [string]$RootDir,
        [string]$Arch,
        [string]$BuildType
    )

    $isBeta = $BuildType -eq "beta"
    $betaSuffix = if ($isBeta) { "-beta" } else { "" }

    return @{
        BuildRoot = "$RootDir\build"
        BuildFolder = "$RootDir\build\build-$Arch$betaSuffix-release"
        DeployFolder = "$RootDir\build\deploy-$Arch$betaSuffix-release"
        InstallerFolder = "$RootDir\build\installer-$Arch$betaSuffix-release"
        SymbolsFolder = "$RootDir\symbols-$Arch$betaSuffix-release"
    }
}

function Clean-BuildDirectories {
    param(
        [string[]]$Paths
    )

    Write-Host "Cleaning output directories..." -ForegroundColor Green
    foreach ($path in $Paths) {
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function Sync-RcVersion {
    param(
        [string]$VersionFile,
        [string]$RcFile
    )

    Write-Host "Syncing version to RC file..." -ForegroundColor Green
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\update_rc_version.ps1" `
        -VersionFile $VersionFile `
        -RcFile $RcFile
}

function Generate-Translations {
    param(
        [string]$LanguagesDir
    )

    Write-Host "Generating translations..." -ForegroundColor Green
    Push-Location $LanguagesDir
    Get-ChildItem *.ts | ForEach-Object {
        Write-Host "  Processing $($_.Name)..."
        lrelease $_.Name
    }
    Pop-Location
}

function Invoke-NativeBuild {
    param(
        [string]$BuildFolder,
        [string]$RootDir,
        [string]$Arch,
        [string]$BuildType,
        [string]$VsInstallPath,
        [hashtable]$OpenSslPaths
    )

    $isBeta = $BuildType -eq "beta"
    $VcVarsAll = "$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"
    $CleanTemp = "C:\build-temp-$(Get-Random)"

    # Build additional cmake args for beta
    $BetaArgs = if ($isBeta) { " -DBUILD_TYPE=`"beta`"" } else { "" }

    $BatchContent = @"
@echo off
echo ========================================
echo DancherLink Build
echo ========================================
call "$VcVarsAll" $CommonConfig.VcArch

echo Setting up clean temp directory...
set CLEAN_TEMP=$CleanTemp
if not exist "%CLEAN_TEMP%" mkdir "%CLEAN_TEMP%"
set TMP=%CLEAN_TEMP%
set TEMP=%CLEAN_TEMP%
set TMPDIR=%CLEAN_TEMP%
echo Using temp dir: %TMP%

echo Setting up Qt path...
set PATH=$($Script:CommonConfig.QtPath);%PATH%
set Qt6_DIR=$($Script:CommonConfig.QtCMakeDir)

cd /d "$BuildFolder"

echo Running cmake configure...
cmake -S "$RootDir" -G "Ninja" -DCMAKE_BUILD_TYPE="$($Script:CommonConfig.CMakeBuildType)" -DARCH_DIR="$Arch"$BetaArgs -DOPENSSL_INCLUDE_DIR="$($OpenSslPaths.Inc)" -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$($OpenSslPaths.Crypto)" -DOPENSSL_SSL_LIBRARY:FILEPATH="$($OpenSslPaths.Ssl)"

if %ERRORLEVEL% neq 0 (
    echo CMake configuration FAILED
    goto :cleanup
)
echo CMake configuration SUCCESS

echo.
echo Building...
cmake --build . --config "$($Script:CommonConfig.CMakeBuildType)"

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

    $BuildBatch = "$BuildFolder\do-build.bat"
    Set-Content -Path $BuildBatch -Value $BatchContent -Encoding ASCII

    Write-Host "Running build in native cmd.exe with Ninja..." -ForegroundColor Green
    cmd.exe /c "$BuildBatch" 2>&1

    $BuildResult = $LASTEXITCODE
    Remove-Item $BuildBatch -ErrorAction SilentlyContinue

    return $BuildResult
}

function Find-Executable {
    param(
        [string[]]$SearchPaths,
        [string]$Filter
    )

    foreach ($path in $SearchPaths) {
        $exe = Get-ChildItem -Recurse -Filter $Filter -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) { return $exe }
    }
    return $null
}

function Copy-Symbols {
    param(
        [string]$BuildFolder,
        [string]$SymbolsFolder,
        [string]$Arch,
        [string]$RootDir
    )

    Write-Host "Saving PDBs..." -ForegroundColor Green
    Get-ChildItem -Recurse -Filter "*.pdb" -Path $BuildFolder | ForEach-Object {
        Copy-Item $_.FullName "$SymbolsFolder\" -Force
    }
    Get-ChildItem "$RootDir\libs\windows\lib\$Arch\*.pdb" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$SymbolsFolder\" -Force
    }
}

function Copy-Dependencies {
    param(
        [string]$DeployFolder,
        [string]$Arch,
        [string]$RootDir,
        [string]$BuildFolder
    )

    Write-Host "Copying dependencies..." -ForegroundColor Green
    Copy-Item "$RootDir\libs\windows\lib\$Arch\*.dll" "$DeployFolder\" -Force -ErrorAction SilentlyContinue

    $MoonlightDll = Get-ChildItem -Recurse -Filter "moonlight-common-c.dll" -Path $BuildFolder | Select-Object -First 1
    if ($MoonlightDll) {
        Copy-Item $MoonlightDll.FullName "$DeployFolder\" -Force
    }

    Copy-Item "$RootDir\app\SDL_GameControllerDB\gamecontrollerdb.txt" "$DeployFolder\" -Force
}

function Deploy-Qt {
    param(
        [string]$DeployFolder,
        [string]$RootDir,
        [string]$ExePath
    )

    Write-Host "Deploying Qt dependencies..." -ForegroundColor Green

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

    # Copy exe to deploy folder for windeployqt
    $DeployBinExe = "$DeployFolder\DancherLink.exe"
    Copy-Item $ExePath $DeployBinExe -Force
    Write-Host "Copied DancherLink.exe to deploy folder for windeployqt" -ForegroundColor Green

    windeployqt @WindeployqtArgs $DeployBinExe

    # Remove exe - WiX will add it separately
    Remove-Item $DeployBinExe -Force
    Write-Host "Removed DancherLink.exe from deploy folder (will be added by WiX)" -ForegroundColor Green
}

function Deploy-QtTranslations {
    param(
        [string]$DeployFolder
    )

    $TranslationsDir = "$DeployFolder\translations"
    New-Item -ItemType Directory -Path $TranslationsDir -Force | Out-Null

    $QtTranslations = @(
        "$($Script:CommonConfig.QtPath)\..\translations\qt_zh_CN.qm",
        "$($Script:CommonConfig.QtPath)\..\translations\qtbase_zh_CN.qm",
        "$($Script:CommonConfig.QtPath)\..\translations\qtquick_zh_CN.qm",
        "$($Script:CommonConfig.QtPath)\..\translations\qtmultimedia_zh_CN.qm"
    )

    $QtTranslations | Where-Object { Test-Path $_ } | ForEach-Object {
        Copy-Item $_ "$TranslationsDir\" -Force
    }
}

function Remove-UnusedQtStyles {
    param(
        [string]$DeployFolder
    )

    Write-Host "Removing unused Qt styles..." -ForegroundColor Green

    $styles = @("Fusion", "Imagine", "Universal", "Windows", "NativeStyle")
    foreach ($style in $styles) {
        $path = "$DeployFolder\qml\QtQuick\Controls\$style"
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
        $path = "$DeployFolder\qml\QtQuick\Controls\$($style)StyleImpl"
        if (Test-Path $path) { Remove-Item -Recurse -Force $path }
    }
}

function Build-Msi {
    param(
        [string]$InstallerFolder,
        [string]$DeployFolder,
        [string]$BuildFolder,
        [string]$Version,
        [string]$WxsFile,
        [string[]]$Extensions
    )

    Write-Host "Building MSI installer..." -ForegroundColor Green

    # Ensure app config dir exists and has the exe
    $AppConfigDir = "$BuildFolder\app\release"
    if (-not (Test-Path $AppConfigDir)) { New-Item -ItemType Directory -Path $AppConfigDir | Out-Null }
    $BuiltExe = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
    if ($BuiltExe) { Copy-Item $BuiltExe.FullName "$AppConfigDir\" -Force }

    $WixArgs = @("build",
        "-arch", "x64",
        "-out", "$InstallerFolder\DancherLink-x86_64-$Version.msi",
        "-b", "$DeployFolder",
        "-d", "Version=$Version",
        "-d", "BuildDir=$BuildFolder",
        "-d", "DeployDir=$DeployFolder",
        "-d", "Configuration=Release"
    )

    # Add extensions if provided
    foreach ($ext in $Extensions) {
        $WixArgs += @("-ext", $ext)
    }

    $WixArgs += $WxsFile

    Write-Host "Running: wix build..." -ForegroundColor Green
    $WixOutput = & wix $WixArgs 2>&1
    Write-Host $WixOutput

    # Copy MSI to build folder
    $MsiFile = "$InstallerFolder\DancherLink-x86_64-$Version.msi"
    if (Test-Path $MsiFile) {
        Copy-Item $MsiFile "$BuildFolder\DancherLink.msi" -Force
        Write-Host "MSI created: $MsiFile" -ForegroundColor Green
        return $MsiFile
    } else {
        Write-Host "Warning: MSI file not found after build" -ForegroundColor Yellow
        return $null
    }
}

function Update-Manifest {
    param(
        [string]$RootDir,
        [string]$Version,
        [string]$Arch,
        [string]$BuildType
    )

    $manifestFile = if ($BuildType -eq "beta") { "updates-beta.json" } else { "updates.json" }

    if ((Test-Path "$RootDir\server") -and (Test-Path "$RootDir\server\update_version.py")) {
        Write-Host "Updating server/$manifestFile..." -ForegroundColor Green
        python "$RootDir\server\update_version.py" "$Version" "$Arch" "release" "$RootDir" $BuildType
    }
}

function Write-BuildSuccess {
    param(
        [string]$BuildType,
        [string]$Version,
        [string]$MsiPath
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "[$BuildType Build] Build successful!" -ForegroundColor Green
    Write-Host "  Version: $Version" -ForegroundColor Yellow
    Write-Host "  MSI: $MsiPath" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Green
}
