@echo off
setlocal enabledelayedexpansion

set MSI_PATH=%~1
set APP_EXE=%~2
set TIMEOUT_SEC=30

echo DancherLink Updater - Starting...
echo Waiting for %APP_EXE% to close (max %TIMEOUT_SEC% seconds)...

set /a elapsed=0
:wait_loop
tasklist /FI "IMAGENAME eq %APP_EXE%" 2>NUL | find /I /N "%APP_EXE%">NUL
if "%ERRORLEVEL%"=="0" (
    timeout /t 1 /nobreak >NUL
    set /a elapsed+=1
    if !elapsed! LSS %TIMEOUT_SEC% (
        goto wait_loop
    ) else (
        echo Timeout reached. Forcing close...
        taskkill /F /IM %APP_EXE% >NUL 2>&1
    )
)

echo Starting installation...
msiexec /i "%MSI_PATH%" /quiet /norestart /l*v "%TEMP%\DancherLink_Update.log"
if "%ERRORLEVEL%"=="0" (
    echo Installation completed successfully.
) else (
    echo Installation failed with error %ERRORLEVEL%. Check log at %TEMP%\DancherLink_Update.log
)

echo Restarting application...
timeout /t 2 /nobreak >NUL
start "" "%APP_EXE%"

endlocal
