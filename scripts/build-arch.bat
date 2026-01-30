@echo off
setlocal enableDelayedExpansion

rem Setup Qt environment
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
where qmake.exe

rem Add Winget links path for Ninja
set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"

rem Run from Qt command prompt with working directory set to root of repo

set BUILD_CONFIG=%1

rem Convert to lower case for windeployqt
if /I "%BUILD_CONFIG%"=="debug" (
    set BUILD_CONFIG=debug
    set CMAKE_BUILD_TYPE=Debug
    set WIX_MUMS=10
) else (
    if /I "%BUILD_CONFIG%"=="release" (
        set BUILD_CONFIG=release
        set CMAKE_BUILD_TYPE=Release
        set WIX_MUMS=10
    ) else (
        if /I "%BUILD_CONFIG%"=="signed-release" (
            set BUILD_CONFIG=release
            set CMAKE_BUILD_TYPE=Release
            set SIGN=1
            set MUST_DEPLOY_SYMBOLS=1

            rem Fail if there are unstaged changes
            rem git diff-index --quiet HEAD --
            rem if !ERRORLEVEL! NEQ 0 (
            rem    echo Signed release builds must not have unstaged changes!
            rem    exit /b 1
            rem )
        ) else (
            echo Invalid build configuration - expected 'debug' or 'release'
            echo Usage: scripts\build-arch.bat ^(release^|debug^)
            exit /b 1
        )
    )
)

rem Find Qt path to determine our architecture
set QT_PATH_FOUND=0
for /F %%i in ('where qmake') do (
    set QT_PATH=%%i
    set QT_PATH_FOUND=1
    goto :FoundQt
)
if "%QT_PATH_FOUND%"=="0" (
    echo Error: qmake not found in PATH!
    exit /b 1
)
:FoundQt

rem Strip the qmake filename off the end to get the Qt bin directory itself
set QT_PATH=%QT_PATH:\qmake.exe=%
set QT_PATH=%QT_PATH:\qmake.bat=%
set QT_PATH=%QT_PATH:\qmake.cmd=%

echo QT_PATH=%QT_PATH%
if not x%QT_PATH:_arm64=%==x%QT_PATH% (
    set ARCH=arm64

    rem Replace the _arm64 suffix with _64 to get the x64 bin path
    set HOSTBIN_PATH=%QT_PATH:_arm64=_64%
    echo HOSTBIN_PATH=!HOSTBIN_PATH!

    if exist %QT_PATH%\windeployqt.exe (
        echo Using windeployqt.exe from QT_PATH
        set WINDEPLOYQT_CMD=windeployqt.exe
    ) else (
        echo Using windeployqt.exe from HOSTBIN_PATH
        set WINDEPLOYQT_CMD=!HOSTBIN_PATH!\windeployqt.exe --qtpaths %QT_PATH%\qtpaths.bat
    )
) else (
    if not x%QT_PATH:_64=%==x%QT_PATH% (
        set ARCH=x64
        set WINDEPLOYQT_CMD=windeployqt.exe
    ) else (
        if not x%QT_PATH:msvc=%==x%QT_PATH% (
            set ARCH=x86
            set WINDEPLOYQT_CMD=windeployqt.exe
        ) else (
            echo Unable to determine Qt architecture
            goto Error
        )
    )
)

echo Detected target architecture: %ARCH%

set SIGNTOOL_PARAMS=sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 /sha1 8b9d0d682ad9459e54f05a79694bc10f9876e297 /v

set BUILD_ROOT=%cd%\build
set SOURCE_ROOT=%cd%
set BUILD_FOLDER=%BUILD_ROOT%\build-%ARCH%-%BUILD_CONFIG%
set DEPLOY_FOLDER=%BUILD_ROOT%\deploy-%ARCH%-%BUILD_CONFIG%
set INSTALLER_FOLDER=%BUILD_ROOT%\installer-%ARCH%-%BUILD_CONFIG%
set SYMBOLS_FOLDER=%BUILD_ROOT%\symbols-%ARCH%-%BUILD_CONFIG%

rem Increment version number in app/version.txt (Local build only)
if "%CI%"=="" (
    powershell -Command "$v = (Get-Content '%SOURCE_ROOT%\app\version.txt').Trim(); $parts = $v.Split('.'); $parts[-1] = [int]$parts[-1] + 1; $newV = $parts -join '.'; Set-Content '%SOURCE_ROOT%\app\version.txt' $newV -NoNewline; Write-Host 'Incremented version to' $newV"
) else (
    echo Running in CI environment, skipping version increment.
)

rem Sync version to RC file
powershell -ExecutionPolicy Bypass -File "%SOURCE_ROOT%\scripts\update_rc_version.ps1" -VersionFile "%SOURCE_ROOT%\app\version.txt" -RcFile "%SOURCE_ROOT%\app\DancherLink_resource.rc"

rem Allow CI to override the version.txt with an environment variable
if defined CI_VERSION (
    set VERSION=%CI_VERSION%
) else (
    set /p VERSION=<%SOURCE_ROOT%\app\version.txt
)

rem Use the correct VC tools for the specified architecture
if /I "%ARCH%" EQU "x64" (
    rem x64 is a special case that doesn't match %PROCESSOR_ARCHITECTURE%
    set VC_ARCH=AMD64
) else (
    set VC_ARCH=%ARCH%
)

rem If we're not building for the current platform, use the cross compiling toolchain
if /I "%VC_ARCH%" NEQ "%PROCESSOR_ARCHITECTURE%" (
    set VC_ARCH=%PROCESSOR_ARCHITECTURE%_%VC_ARCH%
)

rem Find Visual Studio and run vcvarsall.bat
set VSWHERE="%SOURCE_ROOT%\scripts\vswhere.exe"
set VS_FOUND=0
for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -property installationPath`) do (
    call "%%i\VC\Auxiliary\Build\vcvarsall.bat" %VC_ARCH%
    set VS_FOUND=1
)
if "%VS_FOUND%"=="0" (
    echo Error: Visual Studio not found!
    exit /b 1
)
if !ERRORLEVEL! NEQ 0 goto Error

rem Find VC redistributable DLLs
for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -find VC\Redist\MSVC\*\%ARCH%\Microsoft.VC*.CRT`) do set VC_REDIST_DLL_PATH=%%i

echo Cleaning output directories
rmdir /s /q %DEPLOY_FOLDER%
rmdir /s /q %BUILD_FOLDER%
rmdir /s /q %INSTALLER_FOLDER%
rmdir /s /q %SYMBOLS_FOLDER%
mkdir %BUILD_ROOT%
mkdir %DEPLOY_FOLDER%
mkdir %BUILD_FOLDER%
mkdir %INSTALLER_FOLDER%
mkdir %SYMBOLS_FOLDER%

echo Generating translations...
if defined HOSTBIN_PATH (
    set LRELEASE_CMD="%HOSTBIN_PATH%\lrelease.exe"
    set QT_HOST_PATH_ARG=-DQT_HOST_PATH="!HOSTBIN_PATH!\.."
) else (
    set LRELEASE_CMD="%QT_PATH%\lrelease.exe"
    set QT_HOST_PATH_ARG=
)

pushd "%SOURCE_ROOT%\app\languages"
for %%f in (*.ts) do (
    %LRELEASE_CMD% "%%f"
    if !ERRORLEVEL! NEQ 0 goto Error
)
popd

echo Configuring the project with CMake
set "SOURCE_ROOT_CMAKE=%SOURCE_ROOT:\=/%"

if "%ARCH%"=="arm64" (
    set OPENSSL_INC="%SOURCE_ROOT_CMAKE%/libs/windows/include/arm64"
) else (
    set OPENSSL_INC="%SOURCE_ROOT_CMAKE%/libs/windows/include/x64"
)

pushd %BUILD_FOLDER%
cmake -S "%SOURCE_ROOT%" -B . -G "Ninja" ^
    -DCMAKE_BUILD_TYPE=%CMAKE_BUILD_TYPE% ^
    -DCMAKE_VERBOSE_MAKEFILE=ON ^
    -DARCH_DIR=%ARCH% ^
    !QT_HOST_PATH_ARG! ^
    -DOPENSSL_INCLUDE_DIR=!OPENSSL_INC! ^
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="%SOURCE_ROOT_CMAKE%/libs/windows/lib/%ARCH%/libcrypto.lib" ^
    -DOPENSSL_SSL_LIBRARY:FILEPATH="%SOURCE_ROOT_CMAKE%/libs/windows/lib/%ARCH%/libssl.lib"
if !ERRORLEVEL! NEQ 0 goto Error
popd

echo Compiling DancherLink in %CMAKE_BUILD_TYPE% configuration
pushd %BUILD_FOLDER%
cmake --build . --config %CMAKE_BUILD_TYPE% --parallel
if !ERRORLEVEL! NEQ 0 goto Error
popd

echo Saving PDBs
for /r "%BUILD_FOLDER%" %%f in (*.pdb) do (
    copy "%%f" %SYMBOLS_FOLDER%
    if !ERRORLEVEL! NEQ 0 goto Error
)
copy %SOURCE_ROOT%\libs\windows\lib\%ARCH%\*.pdb %SYMBOLS_FOLDER%
if !ERRORLEVEL! NEQ 0 goto Error
7z a %SYMBOLS_FOLDER%\MoonlightDebuggingSymbols-%ARCH%-%VERSION%.zip %SYMBOLS_FOLDER%\*.pdb
if !ERRORLEVEL! NEQ 0 goto Error

if "%ML_SYMBOL_STORE%" NEQ "" (
    echo Publishing PDBs to symbol store: %ML_SYMBOL_STORE%
    symstore add /f %SYMBOLS_FOLDER%\*.pdb /s %ML_SYMBOL_STORE% /t Moonlight
    if !ERRORLEVEL! NEQ 0 goto Error
) else (
    if "%MUST_DEPLOY_SYMBOLS%"=="1" (
        echo "A symbol server must be specified in ML_SYMBOL_STORE for signed release builds"
        exit /b 1
    )
)

if "%ML_SYMBOL_ARCHIVE%" NEQ "" (
    echo Copying PDB ZIP to symbol archive: %ML_SYMBOL_ARCHIVE%
    copy %SYMBOLS_FOLDER%\MoonlightDebuggingSymbols-%ARCH%-%VERSION%.zip %ML_SYMBOL_ARCHIVE%
    if !ERRORLEVEL! NEQ 0 goto Error
) else (
    if "%MUST_DEPLOY_SYMBOLS%"=="1" (
        echo "A symbol archive directory must be specified in ML_SYMBOL_ARCHIVE for signed release builds"
        exit /b 1
    )
)

echo Copying DLL dependencies
copy %SOURCE_ROOT%\libs\windows\lib\%ARCH%\*.dll %DEPLOY_FOLDER%
if !ERRORLEVEL! NEQ 0 goto Error

echo Copying moonlight-common-c.dll
if exist "%BUILD_FOLDER%\bin\moonlight-common-c.dll" (
    copy %BUILD_FOLDER%\bin\moonlight-common-c.dll %DEPLOY_FOLDER%
) else (
    if exist "%BUILD_FOLDER%\moonlight-common-c\moonlight-common-c\%BUILD_CONFIG%\moonlight-common-c.dll" (
        copy "%BUILD_FOLDER%\moonlight-common-c\moonlight-common-c\%BUILD_CONFIG%\moonlight-common-c.dll" %DEPLOY_FOLDER%
    ) else (
        echo Warning: moonlight-common-c.dll not found
    )
)
if !ERRORLEVEL! NEQ 0 goto Error

echo Copying GC mapping list
copy %SOURCE_ROOT%\app\SDL_GameControllerDB\gamecontrollerdb.txt %DEPLOY_FOLDER%
if !ERRORLEVEL! NEQ 0 goto Error

if not x%QT_PATH:\5.=%==x%QT_PATH% (
    echo Copying qt.conf for Qt 5
    copy %SOURCE_ROOT%\app\qt_qt5.conf %DEPLOY_FOLDER%\qt.conf
    if !ERRORLEVEL! NEQ 0 goto Error

    rem Qt 5.15
    set WINDEPLOYQT_ARGS=--no-qmltooling --no-virtualkeyboard
) else (
    rem Qt 6.5+
    set WINDEPLOYQT_ARGS=--no-system-d3d-compiler --no-system-dxc-compiler --skip-plugin-types qmltooling,generic --no-ffmpeg
    set WINDEPLOYQT_ARGS=!WINDEPLOYQT_ARGS! --no-quickcontrols2fusion --no-quickcontrols2imagine --no-quickcontrols2universal
    set WINDEPLOYQT_ARGS=!WINDEPLOYQT_ARGS! --no-quickcontrols2fusionstyleimpl --no-quickcontrols2imaginestyleimpl --no-quickcontrols2universalstyleimpl --no-quickcontrols2windowsstyleimpl
)

echo Deploying Qt dependencies
rem Locate the built executable. Visual Studio generator puts it in app/Release/ or app/Debug/
if exist "%BUILD_FOLDER%\bin\%CMAKE_BUILD_TYPE%\DancherLink.exe" (
    set EXE_PATH=%BUILD_FOLDER%\bin\%CMAKE_BUILD_TYPE%\DancherLink.exe
) else (
    if exist "%BUILD_FOLDER%\app\%CMAKE_BUILD_TYPE%\DancherLink.exe" (
        set EXE_PATH=%BUILD_FOLDER%\app\%CMAKE_BUILD_TYPE%\DancherLink.exe
    ) else (
        rem Fallback for NMake or single-config generators
        if exist "%BUILD_FOLDER%\bin\DancherLink.exe" (
            set EXE_PATH=%BUILD_FOLDER%\bin\DancherLink.exe
        ) else (
            set EXE_PATH=%BUILD_FOLDER%\app\DancherLink.exe
        )
    )
)

%WINDEPLOYQT_CMD% --dir %DEPLOY_FOLDER% --%BUILD_CONFIG% --qmldir %SOURCE_ROOT%\app\gui --no-opengl-sw --no-compiler-runtime --no-sql %WINDEPLOYQT_ARGS% "!EXE_PATH!"
if !ERRORLEVEL! NEQ 0 goto Error

echo Deleting unused styles
rem Qt 5.x directories
rmdir /s /q %DEPLOY_FOLDER%\QtQuick\Controls.2\Fusion
rmdir /s /q %DEPLOY_FOLDER%\QtQuick\Controls.2\Imagine
rmdir /s /q %DEPLOY_FOLDER%\QtQuick\Controls.2\Universal
rem Qt 6.5+ directories
rmdir /s /q %DEPLOY_FOLDER%\qml\QtQuick\Controls\Fusion
rmdir /s /q %DEPLOY_FOLDER%\qml\QtQuick\Controls\Imagine
rmdir /s /q %DEPLOY_FOLDER%\qml\QtQuick\Controls\Universal
rmdir /s /q %DEPLOY_FOLDER%\qml\QtQuick\Controls\Windows
rmdir /s /q %DEPLOY_FOLDER%\qml\QtQuick\NativeStyle

if "%SIGN%"=="1" (
    echo Signing deployed binaries
    set FILES_TO_SIGN=%DEPLOY_FOLDER%\DancherLink.exe
    for /r "%DEPLOY_FOLDER%" %%f in (*.dll *.exe) do (
        set FILES_TO_SIGN=!FILES_TO_SIGN! %%f
    )
    signtool %SIGNTOOL_PARAMS% !FILES_TO_SIGN!
    if !ERRORLEVEL! NEQ 0 goto Error
)

if "%ML_SYMBOL_STORE%" NEQ "" (
    echo Publishing binaries to symbol store: %ML_SYMBOL_STORE%
    symstore add /r /f %DEPLOY_FOLDER%\*.* /s %ML_SYMBOL_STORE% /t DancherLink
    if !ERRORLEVEL! NEQ 0 goto Error
    
    if exist "%BUILD_FOLDER%\bin\DancherLink.exe" (
        symstore add /r /f %BUILD_FOLDER%\bin\DancherLink.exe /s %ML_SYMBOL_STORE% /t DancherLink
    ) else (
        symstore add /r /f %BUILD_FOLDER%\app\%BUILD_CONFIG%\Moonlight.exe /s %ML_SYMBOL_STORE% /t DancherLink
    )
    if !ERRORLEVEL! NEQ 0 goto Error
)

echo Building MSI
if not exist "%BUILD_FOLDER%\app\%BUILD_CONFIG%" mkdir "%BUILD_FOLDER%\app\%BUILD_CONFIG%"
if exist "%BUILD_FOLDER%\bin\DancherLink.exe" (
    copy "%BUILD_FOLDER%\bin\DancherLink.exe" "%BUILD_FOLDER%\app\%BUILD_CONFIG%\DancherLink.exe"
)
cmd /c "msbuild -Restore %SOURCE_ROOT%\wix\DancherLink\DancherLink.wixproj /p:Configuration=%BUILD_CONFIG% /p:Platform=%ARCH% /p:MSBuildProjectExtensionsPath=%BUILD_FOLDER%\ /p:Version=%VERSION%"
if !ERRORLEVEL! NEQ 0 goto Error

echo Copying application binary to deployment directory
rem The qmake build still outputs Moonlight.exe because the target name is defined in app.pro
rem and we haven't changed the qmake TARGET variable yet, or we only changed the installer name.
rem Let's check which file exists and copy/rename it.

if exist "%BUILD_FOLDER%\bin\DancherLink.exe" (
    copy %BUILD_FOLDER%\bin\DancherLink.exe %DEPLOY_FOLDER%
) else (
    if exist "%BUILD_FOLDER%\bin\Moonlight.exe" (
        copy %BUILD_FOLDER%\bin\Moonlight.exe %DEPLOY_FOLDER%\DancherLink.exe
    ) else (
        echo Could not find compiled executable!
        goto Error
    )
)
if !ERRORLEVEL! NEQ 0 goto Error

echo Building portable package
rem This must be done after WiX harvesting and signing, since the VCRT dlls are MS signed
rem and should not be harvested for inclusion in the full installer
copy "%VC_REDIST_DLL_PATH%\*.dll" %DEPLOY_FOLDER%
if !ERRORLEVEL! NEQ 0 goto Error
rem This file tells DancherLink that it's a portable installation
echo. > %DEPLOY_FOLDER%\portable.dat
if !ERRORLEVEL! NEQ 0 goto Error
7z a %INSTALLER_FOLDER%\DancherLinkPortable-%ARCH%-%VERSION%.zip %DEPLOY_FOLDER%\*
if !ERRORLEVEL! NEQ 0 goto Error

if exist "%SOURCE_ROOT%\server\" (
    if exist "%SOURCE_ROOT%\server\update_version.py" (
        echo Updating server\updates.json
        python "%SOURCE_ROOT%\server\update_version.py" "%VERSION%" "%ARCH%" "%BUILD_CONFIG%"
        if !ERRORLEVEL! NEQ 0 goto Error
    )
)

echo Build successful for DancherLink v%VERSION% %ARCH% binaries!
exit /b 0

:Error
echo Build failed!
exit /b !ERRORLEVEL!
