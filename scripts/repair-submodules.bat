@echo off
setlocal enableDelayedExpansion

rem Set working directory to repo root (one level up from scripts)
pushd "%~dp0.."

echo Checking for git...
where git.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Error: git.exe not found in PATH.
    echo Please install Git or add it to your PATH.
    popd
    pause
    exit /b 1
)

echo.
echo ========================================================
echo Repairing corrupted files in submodules...
echo This will discard uncommitted changes in ALL submodules.
echo ========================================================
echo.

rem Recursively restore all submodules
git submodule foreach --recursive "git restore ."

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] Submodules have been restored to their committed state.
) else (
    echo.
    echo [ERROR] Failed to restore submodules.
)

popd
pause
