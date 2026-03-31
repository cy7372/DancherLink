# Simple build script for DancherLink release
$ErrorActionPreference = "Stop"

Set-Location "C:\Users\CyYu\Programs\DancherLink-qt"

# Set paths
$Env:PATH = "C:\Qt\6.10.1\msvc2022_64\bin;" + $Env:PATH

# Run build
& .\scripts\Build.ps1 -Type release -Incremental

Write-Host "Build complete!"
