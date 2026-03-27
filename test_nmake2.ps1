# Test build with NMake - passing temp vars through CMake
$ErrorActionPreference = "Stop"

$RootDir = "C:\Users\CyYu\Programs\DancherLink-qt"
cd $RootDir

# Setup clean temp directory
$CleanTemp = "C:\build-temp"
if (!(Test-Path $CleanTemp)) { New-Item -ItemType Directory -Path $CleanTemp | Out-Null }

# Clean any existing temp files first
Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "Using clean temp: $CleanTemp"

# Setup Qt
$env:PATH = "C:\Qt\6.10.1\msvc2022_64\bin;$env:PATH"

# Setup VS Environment FIRST
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

# Apply env vars but skip temp, then set clean temp
foreach ($line in $output -split "`n") {
    if ($line -match '^(\w+)=(.*)$') {
        if ($matches[1] -eq 'TEMP' -or $matches[1] -eq 'TMP') { continue }
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# Set clean temp AFTER vcvarsall
[System.Environment]::SetEnvironmentVariable("TMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TEMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TMPDIR", $CleanTemp, "Process")
$env:TMP = $CleanTemp
$env:TEMP = $CleanTemp
$env:TMPDIR = $CleanTemp

# Also set CMAKE_TMPDIR if it exists
$env:CMAKE_TMPDIR = $CleanTemp

Write-Host "Final TMP: $env:TMP"
Write-Host "Final TEMP: $env:TEMP"

# Clean and create build dir
$BuildFolder = "$RootDir\build\test-nmake2"
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
New-Item -ItemType Directory -Path $BuildFolder | Out-Null

# Run cmake with NMake - pass temp as cache variable
Write-Host "`nRunning CMake..."
cd $BuildFolder

cmake "$RootDir" -G "NMake Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_TMPDIR:PATH="$CleanTemp" `
    -DARCH_DIR=x64 `
    -DOPENSSL_INCLUDE_DIR="$RootDir/libs/windows/include/x64" `
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libcrypto.lib" `
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libssl.lib"

Write-Host "`nCMake exit code: $LASTEXITCODE"

# Cleanup
if (Test-Path $CleanTemp) {
    Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
