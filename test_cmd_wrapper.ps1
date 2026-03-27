# Create a batch file that runs the build with proper environment
$RootDir = "C:\Users\CyYu\Programs\DancherLink-qt"
$BuildFolder = "$RootDir\build\test-cmd"

# Setup VS Environment
$VsInstallPath = "C:\Program Files\Microsoft Visual Studio\18\Community"
$VcVarsAll = "$VsInstallPath\VC\Auxiliary\Build\vcvarsall.bat"

# Create wrapper that calls vcvarsall then our build script
$WrapperScript = @"
@echo off
echo ========================================
echo DancherLink Test Build
echo ========================================
call "$VcVarsAll" AMD64

echo Setting clean temp directory...
set TMP=C:\build-temp
set TEMP=C:\build-temp
set TMPDIR=C:\build-temp
echo Final TMP=%TMP%
echo Final TEMP=%TEMP%

echo Setting up Qt path...
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
set Qt6_DIR=C:\Qt\6.10.1\msvc2022_64\lib\cmake\Qt6

cd /d "$BuildFolder"
if not exist "$BuildFolder" mkdir "$BuildFolder"
del /q /f "$BuildFolder\*" 2>nul

echo Running cmake...
cmake "$RootDir" -G "NMake Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DARCH_DIR=x64 ^
    -DOPENSSL_INCLUDE_DIR="$RootDir/libs/windows/include/x64" ^
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libcrypto.lib" ^
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$RootDir/libs/windows/lib/x64/libssl.lib"

echo CMake exit code: %ERRORLEVEL%
if %ERRORLEVEL% neq 0 (
    echo CMake configuration FAILED
    exit /b %ERRORLEVEL%
)
echo CMake configuration SUCCESS
"@

$WrapperPath = "$RootDir\build\test-cmd-wrapper.bat"
Set-Content -Path $WrapperPath -Value $WrapperScript -Encoding ASCII

Write-Host "Running build wrapper..."
Write-Host "Wrapper: $WrapperPath"

# Run the wrapper
cmd.exe /c "$WrapperPath" 2>&1
