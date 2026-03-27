# Test build - wrap nmake to set temp vars before cl.exe is called
$ErrorActionPreference = "Stop"

$RootDir = "C:\Users\CyYu\Programs\DancherLink-qt"
cd $RootDir

# Setup clean temp directory
$CleanTemp = "C:\build-temp"
if (!(Test-Path $CleanTemp)) { New-Item -ItemType Directory -Path $CleanTemp | Out-Null }

# Clean any existing temp files first
Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

Write-Host "Using clean temp: $CleanTemp"

# Create a wrapper batch file that sets temp vars and calls nmake
$WrapperScript = @"
@echo off
set TMP=$CleanTemp
set TEMP=$CleanTemp
set TMPDIR=$CleanTemp
set _CL_=/nologo
"%~1" %*
"@
    $WrapperPath = "$RootDir\build\nmake_wrapper.bat"
Set-Content -Path $WrapperPath -Value $WrapperScript -Encoding ASCII

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

# Apply env vars but skip temp
foreach ($line in $output -split "`n") {
    if ($line -match '^(\w+)=(.*)$') {
        if ($matches[1] -eq 'TEMP' -or $matches[1] -eq 'TMP') { continue }
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}

# Clean and create build dir
$BuildFolder = "$RootDir\build\test-nmake4"
if (Test-Path $BuildFolder) { Remove-Item -Recurse -Force $BuildFolder }
New-Item -ItemType Directory -Path $BuildFolder | Out-Null

# Run cmake with NMake - use wrapper as make program
Write-Host "`nRunning CMake with nmake wrapper..."
cd $BuildFolder

cmake "$RootDir" -G "NMake Makefiles" `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_MAKE_PROGRAM="$WrapperPath;$env:PATH" `
    -DARCH_DIR=x64 `
    -DOPENSSL_INCLUDE_DIR="$RootDir/libs/windows/include/x64" `
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libcrypto.lib" `
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libssl.lib"

Write-Host "`nCMake exit code: $LASTEXITCODE"

# Cleanup
if (Test-Path $CleanTemp) {
    Get-ChildItem $CleanTemp -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
}
Remove-Item $WrapperPath -ErrorAction SilentlyContinue
