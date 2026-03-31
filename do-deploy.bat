@echo off
setlocal
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
cd /d %~dp0

echo Copying build output to deploy folder...
if not exist "build\deploy-x64-release" mkdir "build\deploy-x64-release"
xcopy /Y /E /I "build\build-x64-release\bin\*" "build\deploy-x64-release\"

echo Deploying Qt dependencies...
windeployqt --release --no-compiler-runtime --no-translations --no-opengl-sw "build\deploy-x64-release\DancherLink.exe"

echo Done!
endlocal
