<#
.SYNOPSIS
    DancherLink Common Build Functions
.DESCRIPTION
    Shared functions for Release and Beta builds.
#>

# Import configuration
& "$PSScriptRoot\Build-Config.ps1"

# Build log file
$Script:BuildLogFile = $null

function Start-BuildLogging {
    param([string]$LogDir)

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:BuildLogFile = "$LogDir\build-$timestamp.log"

    # Redirect all output to log file
    Start-Transcript -Path $Script:BuildLogFile -Append -Force | Out-Null

    Write-Host "Build log: $Script:BuildLogFile" -ForegroundColor Cyan
}

function Stop-BuildLogging {
    if ($Script:BuildLogFile) {
        Stop-Transcript | Out-Null
        Write-Host "Build log saved to: $Script:BuildLogFile" -ForegroundColor Cyan
    }
}

function Initialize-BuildEnvironment {
    param([string]$BuildType)

    Write-Host "[$BuildType Build] Starting build process..." -ForegroundColor Green

    # Setup Qt path
    $env:PATH = "$($BuildConfig.QtPath);$env:PATH"

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
        [string]$BuildType,
        [switch]$Incremental
    )

    $isBeta = $BuildType -eq "beta"
    $betaSuffix = if ($isBeta) { "-beta" } else { "" }

    # Final release output directory
    $ReleaseBase = "C:\Users\CyYu\Release\DancherLink"
    $ReleaseFolder = if ($isBeta) { "$ReleaseBase\beta" } else { "$ReleaseBase" }

    $paths = @{
        BuildRoot = "$RootDir\build"
        BuildFolder = "$RootDir\build\build-$Arch$betaSuffix-release"
        DeployFolder = "$RootDir\build\deploy-$Arch$betaSuffix-release"
        InstallerFolder = "$RootDir\build\installer-$Arch$betaSuffix-release"
        SymbolsFolder = "$RootDir\symbols-$Arch$betaSuffix-release"
        LogDir = "$RootDir\build\logs"
        ReleaseFolder = $ReleaseFolder
    }

    # Clean only if not incremental build
    if (-not $Incremental) {
        foreach ($key in @('DeployFolder', 'BuildFolder', 'InstallerFolder', 'SymbolsFolder')) {
            if (Test-Path $paths[$key]) {
                Remove-Item -Recurse -Force $paths[$key]
            }
            New-Item -ItemType Directory -Path $paths[$key] -Force | Out-Null
        }
        # Ensure release folder exists
        if (-not (Test-Path $ReleaseFolder)) {
            New-Item -ItemType Directory -Path $ReleaseFolder -Force | Out-Null
        }
        Write-Host "Output directories cleaned (full build)" -ForegroundColor Green
    } else {
        Write-Host "Incremental build (preserving build directory)" -ForegroundColor Yellow
        # Only ensure directories exist
        foreach ($key in @('DeployFolder', 'InstallerFolder', 'SymbolsFolder')) {
            if (-not (Test-Path $paths[$key])) {
                New-Item -ItemType Directory -Path $paths[$key] -Force | Out-Null
            }
        }
        if (-not (Test-Path $ReleaseFolder)) {
            New-Item -ItemType Directory -Path $ReleaseFolder -Force | Out-Null
        }
    }

    return $paths
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
    param([string]$LanguagesDir)

    Write-Host "Generating translations..." -ForegroundColor Green
    Push-Location $LanguagesDir
    $tsFiles = Get-ChildItem *.ts
    if ($tsFiles.Count -eq 0) {
        Write-Host "  No .ts files found" -ForegroundColor Yellow
        Pop-Location
        return
    }

    foreach ($ts in $tsFiles) {
        Write-Host "  Processing $($ts.Name)..."
        lrelease $ts.Name | Out-Null
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
        [hashtable]$OpenSslPaths,
        [switch]$SkipConfigure
    )

    $VcVarsAll = "$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"
    $VcArch = "AMD64"
    $CleanTemp = "C:\build-temp-$PID-$(Get-Random)"

    $isBeta = $BuildType -eq "beta"
    $BetaArgs = if ($isBeta) { " -DBUILD_TYPE=`"beta`"" } else { "" }

    $BatchContent = @"
@echo off
echo ========================================
echo DancherLink Build
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
set PATH=$($BuildConfig.QtPath);%PATH%
set Qt6_DIR=$($BuildConfig.QtCMakeDir)

cd /d "$BuildFolder"
"@

    if (-not $SkipConfigure) {
        $BatchContent += @"

echo Running cmake configure...
cmake -S "$RootDir" -G "$($BuildConfig.CMakeGenerator)" -DCMAKE_BUILD_TYPE="$($BuildConfig.CMakeBuildType)" -DARCH_DIR="$Arch"$BetaArgs -DOPENSSL_INCLUDE_DIR="$($OpenSslPaths.Inc)" -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$($OpenSslPaths.Crypto)" -DOPENSSL_SSL_LIBRARY:FILEPATH="$($OpenSslPaths.Ssl)"
if %ERRORLEVEL% neq 0 (
    echo CMake configuration FAILED
    goto :cleanup
)
echo CMake configuration SUCCESS
"@
    }

    $BatchContent += @"

echo.
echo Building...
cmake --build . --config "$($BuildConfig.CMakeBuildType)"

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
    if ($SkipConfigure) {
        Write-Host "Skipping CMake configure (incremental)" -ForegroundColor Yellow
    }

    # Temporarily disable Stop on error to allow vcvarsall.bat warnings
    $PrevErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Run build and capture output
    $output = cmd.exe /c "$BuildBatch" 2>&1
    Write-Host $output
    $BuildResult = $LASTEXITCODE

    # Restore error preference
    $ErrorActionPreference = $PrevErrorAction

    Remove-Item $BuildBatch -ErrorAction SilentlyContinue

    return $BuildResult
}

function Find-Executable {
    param(
        [string[]]$SearchPaths,
        [string]$Filter
    )

    foreach ($path in $SearchPaths) {
        if (-not (Test-Path $path)) { continue }
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
    $count = 0
    Get-ChildItem -Recurse -Filter "*.pdb" -Path $BuildFolder | ForEach-Object {
        Copy-Item $_.FullName "$SymbolsFolder\" -Force
        $count++
    }
    Get-ChildItem "$RootDir\libs\windows\lib\$Arch\*.pdb" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$SymbolsFolder\" -Force
        $count++
    }
    Write-Host "  Copied $count PDB files" -ForegroundColor Gray
}

function Copy-Dependencies {
    param(
        [string]$DeployFolder,
        [string]$Arch,
        [string]$RootDir,
        [string]$BuildFolder
    )

    Write-Host "Copying dependencies..." -ForegroundColor Green
    $dllCount = 0
    Get-ChildItem "$RootDir\libs\windows\lib\$Arch\*.dll" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$DeployFolder\" -Force
        $dllCount++
    }
    Write-Host "  Copied $dllCount DLL files" -ForegroundColor Gray

    $MoonlightDll = Get-ChildItem -Recurse -Filter "moonlight-common-c.dll" -Path $BuildFolder | Select-Object -First 1
    if ($MoonlightDll) {
        Copy-Item $MoonlightDll.FullName "$DeployFolder\" -Force
        Write-Host "  Copied moonlight-common-c.dll" -ForegroundColor Gray
    }

    Copy-Item "$RootDir\app\SDL_GameControllerDB\gamecontrollerdb.txt" "$DeployFolder\" -Force
}

function Deploy-Qt {
    param(
        [string]$DeployFolder,
        [string]$RootDir,
        [string]$ExePath,
        [string]$GuiDir
    )

    Write-Host "Deploying Qt dependencies..." -ForegroundColor Green

    $DeployBinExe = "$DeployFolder\DancherLink.exe"
    Copy-Item $ExePath $DeployBinExe -Force

    $WindeployqtArgs = @(
        "--dir", $DeployFolder
        $BuildConfig.WindeployqtOptions
    )

    if ($GuiDir) {
        $WindeployqtArgs += @("--qmldir", "$RootDir\$GuiDir")
    }

    $result = windeployqt @WindeployqtArgs $DeployBinExe 2>&1

    # Remove exe - WiX will add it separately
    Remove-Item $DeployBinExe -Force

    return $result
}

function Deploy-QtTranslations {
    param([string]$DeployFolder)

    $TranslationsDir = "$DeployFolder\translations"
    New-Item -ItemType Directory -Path $TranslationsDir -Force | Out-Null

    $count = 0
    foreach ($qmFile in $BuildConfig.QtTranslations) {
        $src = "$($BuildConfig.QtPath)\..\translations\$qmFile"
        if (Test-Path $src) {
            Copy-Item $src "$TranslationsDir\" -Force
            $count++
        }
    }
    Write-Host "  Deployed $count Qt translation files" -ForegroundColor Gray
}

function Remove-UnusedQtStyles {
    param([string]$DeployFolder)

    Write-Host "Removing unused Qt styles..." -ForegroundColor Green
    $removedCount = 0

    foreach ($style in $BuildConfig.UnusedQtStyles) {
        $paths = @(
            "$DeployFolder\qml\QtQuick\Controls\$style",
            "$DeployFolder\qml\QtQuick\Controls\$($style)StyleImpl"
        )
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Remove-Item -Recurse -Force $path
                $removedCount++
            }
        }
    }
    Write-Host "  Removed $removedCount style directories" -ForegroundColor Gray
}

function Build-Msi {
    param(
        [string]$InstallerFolder,
        [string]$DeployFolder,
        [string]$BuildFolder,
        [string]$Version,
        [string]$WxsFile,
        [string[]]$Extensions,
        [switch]$VerboseOutput
    )

    Write-Host "Building MSI installer..." -ForegroundColor Green

    $AppConfigDir = "$BuildFolder\app\release"
    if (-not (Test-Path $AppConfigDir)) {
        New-Item -ItemType Directory -Path $AppConfigDir | Out-Null
    }

    $BuiltExe = Find-Executable -SearchPaths @("$BuildFolder\bin", "$BuildFolder\app") -Filter "DancherLink.exe"
    if ($BuiltExe) {
        Copy-Item $BuiltExe.FullName "$AppConfigDir\" -Force
    }

    $WixArgs = @("build",
        "-arch", "x64",
        "-out", "$InstallerFolder\DancherLink-x86_64-$Version.msi",
        "-b", $DeployFolder,
        "-d", "Version=$Version",
        "-d", "BuildDir=$BuildFolder",
        "-d", "DeployDir=$DeployFolder",
        "-d", "Configuration=Release"
    )

    foreach ($ext in $Extensions) {
        $WixArgs += @("-ext", $ext)
    }

    $WixArgs += $WxsFile

    Write-Host "Running: wix build..." -ForegroundColor Green
    if ($VerboseOutput) {
        $WixOutput = & wix $WixArgs 2>&1
        Write-Host $WixOutput
    } else {
        $WixOutput = & wix $WixArgs 2>&1 | Out-String
    }

    $MsiFile = "$InstallerFolder\DancherLink-x86_64-$Version.msi"
    if (Test-Path $MsiFile) {
        $msiSize = [math]::Round((Get-Item $MsiFile).Length / 1MB, 2)
        Copy-Item $MsiFile "$BuildFolder\DancherLink.msi" -Force
        Write-Host "MSI created: $MsiFile ($msiSize MB)" -ForegroundColor Green
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
        $result = python "$RootDir\server\update_version.py" "$Version" "$Arch" "release" "$RootDir" $BuildType 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: update_version.py returned non-zero exit code" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Skipping manifest update (server directory not found)" -ForegroundColor Yellow
    }
}

function Copy-ReleaseFiles {
    param(
        [string]$DeployFolder,
        [string]$ReleaseFolder,
        [string]$MsiFile,
        [string]$Version,
        [string]$RootDir
    )

    Write-Host "  Preparing release files..." -ForegroundColor Green

    # Clean release folder
    if (Test-Path $ReleaseFolder) {
        Remove-Item -Recurse -Force $ReleaseFolder\* -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $ReleaseFolder -Force | Out-Null

    # Copy MSI if available
    if ($MsiFile -and (Test-Path $MsiFile)) {
        $MsiName = "DancherLink-x86_64-$Version.msi"
        Copy-Item $MsiFile "$ReleaseFolder\$MsiName" -Force
        Write-Host "  Copied MSI: $MsiName" -ForegroundColor Green
    }

    # Copy server files
    if (Test-Path "$RootDir\server") {
        Write-Host "  Copying server files..." -ForegroundColor Green
        Copy-Item "$RootDir\server\*" $ReleaseFolder -Recurse -Force
    }
}

function Write-BuildSuccess {
    param(
        [string]$BuildType,
        [string]$Version,
        [string]$MsiPath,
        [string]$BuildDuration
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "[$BuildType Build] Build successful!" -ForegroundColor Green
    Write-Host "  Version: $Version" -ForegroundColor Yellow
    Write-Host "  MSI: $MsiPath" -ForegroundColor Yellow
    if ($BuildDuration) {
        Write-Host "  Duration: $BuildDuration" -ForegroundColor Yellow
    }
    Write-Host "========================================" -ForegroundColor Green
}
