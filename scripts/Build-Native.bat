@echo off
echo ========================================
echo DancherLink Full Build
echo ========================================
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" AMD64

echo Setting up clean temp directory...
set BUILD_ID=%RANDOM%_%RANDOM%
set CLEAN_TEMP=C:\build-temp-%BUILD_ID%
if not exist "%CLEAN_TEMP%" mkdir "%CLEAN_TEMP%"
set TMP=%CLEAN_TEMP%
set TEMP=%CLEAN_TEMP%
set TMPDIR=%CLEAN_TEMP%
echo Using temp dir: %TMP%

echo Setting up Qt path...
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
set Qt6_DIR=C:\Qt\6.10.1\msvc2022_64\lib\cmake\Qt6

set RootDir=C:\Users\CyYu\Programs\DancherLink-qt
set BuildFolder=%RootDir%\build\build-x64-release
if not exist "%BuildFolder%" mkdir "%BuildFolder%"
cd /d "%BuildFolder%"

echo Build folder: %BuildFolder%

:: Check if CMakeCache.txt exists, if not run cmake
if not exist "CMakeCache.txt" (
    echo Running cmake configure...
    cmake "%RootDir%" -G "NMake Makefiles" ^
        -DCMAKE_BUILD_TYPE=Release ^
        -DARCH_DIR=x64 ^
        -DOPENSSL_INCLUDE_DIR="%RootDir%/libs/windows/include/x64" ^
        -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="%RootDir%/libs/windows/lib/x64/libcrypto.lib" ^
        -DOPENSSL_SSL_LIBRARY:FILEPATH="%RootDir%/libs/windows/lib/x64/libssl.lib"

    if %ERRORLEVEL% neq 0 (
        echo CMake configuration FAILED
        goto :cleanup
    )
    echo CMake configuration SUCCESS
)

echo.
echo Building (single job for stability)...
cmake --build . --config Release --parallel 1

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
