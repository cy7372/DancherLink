@echo off
cd /d %~dp0
set PATH=C:\Qt\6.10.1\msvc2022_64\bin;%PATH%
powershell -ExecutionPolicy Bypass -File scripts\Build.ps1 -Type release
