<#
.SYNOPSIS
    DancherLink Common Build Functions (Python-backed)
.DESCRIPTION
    Shared functions for Release and Beta builds using Python helper.
    More portable and maintainable than pure PowerShell.
#>

# Python helper path
$Script:PythonHelper = "$PSScriptRoot\build_helper.py"
$Script:QtPath = $null

function Get-PythonHelper {
    if (-not (Test-Path $Script:PythonHelper)) {
        Write-Error "Python helper not found: $Script:PythonHelper"
        exit 1
    }
    return $Script:PythonHelper
}

function Invoke-PythonHelper {
    param(
        [string[]]$Args
    )
    $result = & python (Get-PythonHelper) @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return $result
}

function Initialize-BuildEnvironment {
    param([string]$BuildType)

    Write-Host "[$BuildType Build] Starting build process..." -ForegroundColor Green

    # Get Qt path from Python helper
    $qtPath = Invoke-PythonHelper -Args @('get-qt-path')
    if (-not $qtPath) {
        Write-Error "Qt not found. Please install Qt or set QTDIR."
        exit 1
    }
    $Script:QtPath = $qtPath | Select-Object -First 1
    $env:PATH = "$Script:QtPath;$env:PATH"

    # Verify qmake
    $qmakeCheck = Invoke-PythonHelper -Args @('verify-qmake')
    if (-not $qmakeCheck) {
        Write-Error "qmake not found in PATH."
        exit 1
    }

    # Detect architecture
    $Arch = Invoke-PythonHelper -Args @('detect-arch')
    Write-Host "[$BuildType Build] Architecture: $Arch" -ForegroundColor Green

    return $Arch
}

function Get-BuildPaths {
    param(
        [string]$RootDir,
        [string]$Arch,
        [string]$BuildType
    )

    $output = Invoke-PythonHelper -Args @('get-paths', '--root', $RootDir, '--arch', $Arch, '--type', $BuildType)
    $paths = @{}
    foreach ($line in $output) {
        if ($line -match '^(.+?)=(.+)$') {
            $paths[$matches[1]] = $matches[2]
        }
    }
    return $paths
}

function Clean-BuildDirectories {
    param([string[]]$Paths)

    Write-Host "Cleaning output directories..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @('clean') + $Paths
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
    $result = Invoke-PythonHelper -Args @('translations', '--dir', $LanguagesDir)
    Write-Host $result
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

    $qtPath = $Script:QtPath

    # Create batch file using Python helper
    $batchArgs = @(
        'create-batch',
        '--build-folder', $BuildFolder,
        '--root', $RootDir,
        '--arch', $Arch,
        '--type', $BuildType,
        '--vs-path', $VsInstallPath,
        '--openssl-inc', $OpenSslPaths.Inc,
        '--openssl-crypto', $OpenSslPaths.Crypto,
        '--openssl-ssl', $OpenSslPaths.Ssl,
        '--qt-path', $qtPath
    )

    $batchFile = Invoke-PythonHelper -Args $batchArgs
    if (-not $batchFile) {
        return 1
    }

    Write-Host "Running build in native cmd.exe with Ninja..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @('run-build', $batchFile)
    $BuildResult = $LASTEXITCODE

    # Cleanup batch file
    if (Test-Path $batchFile) {
        Remove-Item $batchFile -ErrorAction SilentlyContinue
    }

    return $BuildResult
}

function Find-Executable {
    param(
        [string[]]$SearchPaths,
        [string]$Filter
    )

    $result = Invoke-PythonHelper -Args @('find-exe', '--paths') + $SearchPaths + @('--filter', $Filter)
    return $result
}

function Copy-Symbols {
    param(
        [string]$BuildFolder,
        [string]$SymbolsFolder,
        [string]$Arch,
        [string]$RootDir
    )

    Write-Host "Saving PDBs..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @(
        'copy-symbols',
        '--build-folder', $BuildFolder,
        '--symbols-folder', $SymbolsFolder,
        '--arch', $Arch,
        '--root', $RootDir
    )
}

function Copy-Dependencies {
    param(
        [string]$DeployFolder,
        [string]$Arch,
        [string]$RootDir,
        [string]$BuildFolder
    )

    Write-Host "Copying dependencies..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @(
        'copy-deps',
        '--deploy-folder', $DeployFolder,
        '--arch', $Arch,
        '--root', $RootDir,
        '--build-folder', $BuildFolder
    )
}

function Deploy-Qt {
    param(
        [string]$DeployFolder,
        [string]$RootDir,
        [string]$ExePath
    )

    Write-Host "Deploying Qt dependencies..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @(
        'deploy-qt',
        '--deploy-folder', $DeployFolder,
        '--root', $RootDir,
        '--exe', $ExePath
    )
    Write-Host "Qt deployment complete" -ForegroundColor Green
}

function Deploy-QtTranslations {
    param([string]$DeployFolder)

    $qtPath = $Script:QtPath
    $null = Invoke-PythonHelper -Args @(
        'deploy-qt-translations',
        '--deploy-folder', $DeployFolder,
        '--qt-path', $qtPath
    )
}

function Remove-UnusedQtStyles {
    param([string]$DeployFolder)

    Write-Host "Removing unused Qt styles..." -ForegroundColor Green
    $null = Invoke-PythonHelper -Args @('remove-styles', '--deploy-folder', $DeployFolder)
}

function Build-Msi {
    param(
        [string]$InstallerFolder,
        [string]$DeployFolder,
        [string]$BuildFolder,
        [string]$Version,
        [string]$WxsFile,
        [string[]]$Extensions,
        [string]$BuildType = 'release'
    )

    Write-Host "Building MSI installer..." -ForegroundColor Green

    $msiPath = Invoke-PythonHelper -Args @(
        'build-msi',
        '--installer-folder', $InstallerFolder,
        '--deploy-folder', $DeployFolder,
        '--build-folder', $BuildFolder,
        '--version', $Version,
        '--wxs', $WxsFile,
        '--type', $BuildType
    )

    if ($msiPath) {
        Write-Host "MSI created: $msiPath" -ForegroundColor Green
        return $msiPath
    } else {
        Write-Host "Warning: MSI build failed" -ForegroundColor Yellow
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

    $result = Invoke-PythonHelper -Args @(
        'update-manifest',
        '--root', $RootDir,
        '--version', $Version,
        '--arch', $Arch,
        '--type', $BuildType
    )
    if ($result) {
        Write-Host "Manifest updated" -ForegroundColor Green
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
