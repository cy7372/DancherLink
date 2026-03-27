# Simple test build script
$ErrorActionPreference = "Continue"

$RootDir = "C:\Users\CyYu\Programs\DancherLink-qt"
cd $RootDir

# Setup clean temp directory
$CleanTemp = "C:\build-temp"
if (!(Test-Path $CleanTemp)) { New-Item -ItemType Directory -Path $CleanTemp | Out-Null }

# Clean any existing temp files first
Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

# Set ALL temp-related environment variables
$env:TMP = $CleanTemp
$env:TEMP = $CleanTemp
$env:TMPDIR = $CleanTemp
$env:USERPROFILE = $env:USERPROFILE  # Keep user profile

# Also set VS-specific temp vars
$env:VCIDEInstallDir = $env:VCIDEInstallDir
$env:VSINSTALLDIR = $env:VSINSTALLDIR

# Use [Environment] class to ensure process-level setting
[System.Environment]::SetEnvironmentVariable("TMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TEMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TMPDIR", $CleanTemp, "Process")

Write-Host "Using clean temp: $CleanTemp"
Write-Host "TMP: $env:TMP"
Write-Host "TEMP: $env:TEMP"
Write-Host ".NET GetTempPath: $([System.IO.Path]::GetTempPath())"

# Setup Qt
$env:PATH = "C:\Qt\6.10.1\msvc2022_64\bin;$env:PATH"

# Setup VS Environment
$VsInstallPath = "C:\Program Files\Microsoft Visual Studio\18\Community"
$VcVarsAll = "$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c `"$VcVarsAll`" AMD64 && set"
$psi.RedirectStandardOutput = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::Start($psi)
$output = $process.StandardOutput.ReadToEnd()
$process.WaitForExit()

foreach ($line in $output -split "`n") {
    if ($line -match '^(\w+)=(.*)$') {
        # Skip TEMP and TMP - we'll set them to our clean temp directory
        if ($matches[1] -eq 'TEMP' -or $matches[1] -eq 'TMP') {
            continue
        }
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# NOW set clean temp directory (after vcvarsall has been applied)
[System.Environment]::SetEnvironmentVariable("TMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TEMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TMPDIR", $CleanTemp, "Process")
$env:TMP = $CleanTemp
$env:TEMP = $CleanTemp
$env:TMPDIR = $CleanTemp

Write-Host "Final TMP: $env:TMP"
Write-Host "Final TEMP: $env:TEMP"
Write-Host "Final .NET GetTempPath: $([System.IO.Path]::GetTempPath())"

Write-Host "VCInstallDir: $env:VCInstallDir"

# Clean and create build dir
$BuildFolder = "$RootDir\build\test-nmake"
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
New-Item -ItemType Directory -Path $BuildFolder | Out-Null

# Run cmake
Write-Host "`nRunning CMake..."
cd $BuildFolder
cmake "$RootDir" -G "NMake Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DARCH_DIR=x64 `
    -DOPENSSL_INCLUDE_DIR="$RootDir/libs/windows/include/x64" `
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libcrypto.lib" `
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libssl.lib"

Write-Host "`nCMake exit code: $LASTEXITCODE"

# Cleanup
Remove-Item -Recurse -Force $CleanTemp -ErrorAction SilentlyContinue
