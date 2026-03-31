@echo off
setlocal
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
cd /d %~dp0

echo Building DancherLink Beta...
cd build\build-x64-beta-release
cmake --build .
cd ..\..

echo Copying build output to beta deploy folder...
if not exist "build\deploy-x64-beta-release" mkdir "build\deploy-x64-beta-release"
xcopy /Y /E /I "build\build-x64-beta-release\bin\*" "build\deploy-x64-beta-release\"

echo Deploying Qt dependencies...
windeployqt --release --no-compiler-runtime --no-translations --no-opengl-sw "build\deploy-x64-beta-release\DancherLink.exe"

echo Done! Deploy folder: build\deploy-x64-beta-release
endlocal
