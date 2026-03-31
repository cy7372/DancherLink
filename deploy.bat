@echo off
cd /d C:\Users\CyYu\Programs\DancherLink-qt
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%

REM Copy build output to deploy folder
xcopy /Y /I build\build-x64-release\bin\* build\deploy-x64-release\

REM Deploy Qt dependencies
windeployqt --release --no-compiler-runtime --no-translations --no-opengl-sw "build\deploy-x64-release\DancherLink.exe"

echo Deploy complete!
