@echo off
setlocal enableDelayedExpansion

:: Setup Qt environment
if exist "C:\Qt\6.10.1\msvc2022_64\bin" (
    set PATH=C:\Qt\6.10.1\msvc2022_64\bin;!PATH!
)

:: Add Winget links path for Ninja
set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"

call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
cd /d C:\Users\CyYu\Programs\DancherLink-qt

:: Clean and regenerate build files
rmdir /s /q build\build-x64-release 2>nul
mkdir build\build-x64-release

:: Run CMake
cmake -G Ninja -S . -B build\build-x64-release -DCMAKE_BUILD_TYPE=Release

:: Build
ninja -C build\build-x64-release bin/DancherLink.exe
