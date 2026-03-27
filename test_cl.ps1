if (!(Test-Path 'C:\build-temp')) { New-Item -ItemType Directory -Path 'C:\build-temp' | Out-Null }

$CleanTemp = 'C:\build-temp'
$env:TMP = $CleanTemp
$env:TEMP = $CleanTemp
[System.Environment]::SetEnvironmentVariable('TMP', $CleanTemp, 'Process')
[System.Environment]::SetEnvironmentVariable('TEMP', $CleanTemp, 'Process')

# Create simple test file
$testFile = 'C:\build-temp\test.c'
Set-Content -Path $testFile -Value 'int main() { return 0; }'

# Try to compile
Write-Host 'Testing cl.exe directly...'
& 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\bin\Hostx64\x64\cl.exe' /I'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.50.35717\include' $testFile 2>&1
Write-Host 'Exit code:' $LASTEXITCODE

# Check temp dir
Write-Host 'Contents of C:\build-temp:'
Get-ChildItem 'C:\build-temp' | Select-Object Name
