# Test build - proper environment setup without invalid flags
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

# Apply ALL env vars from vcvarsall (including TEMP/TMP pointing to user temp)
foreach ($line in $output -split "`n") {
    if ($line -match '^(\w+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# NOW override temp vars AFTER vcvarsall
[System.Environment]::SetEnvironmentVariable("TMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TEMP", $CleanTemp, "Process")
[System.Environment]::SetEnvironmentVariable("TMPDIR", $CleanTemp, "Process")
$env:TMP = $CleanTemp
$env:TEMP = $CleanTemp
$env:TMPDIR = $CleanTemp

Write-Host "TMP: $env:TMP"
Write-Host "TEMP: $env:TEMP"

# Verify temp dir is writable
try {
    $testFile = "$CleanTemp\test_write_$([System.DateTime]::Now.Ticks).tmp"
    Set-Content -Path $testFile -Value "test"
    Remove-Item $testFile
    Write-Host "Temp dir write test: PASSED"
} catch {
    Write-Host "Temp dir write test: FAILED - $_"
}

# Clean and create build dir
$BuildFolder = "$RootDir\build\test-nmake5"
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
New-Item -ItemType Directory -Path $BuildFolder | Out-Null

# Run cmake with NMake - NO /TMPDIR flag
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
if (Test-Path $CleanTemp) {
    Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
