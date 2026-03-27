$tempDirs = @($env:TEMP, $env:TMP, 'C:\Windows\Temp')
foreach ($dir in $tempDirs) {
    if (Test-Path $dir) {
        Write-Host "Checking: $dir"
        $ilFiles = Get-ChildItem -Path $dir -Filter '*.il' -ErrorAction SilentlyContinue
        if ($ilFiles) {
            Write-Host "Found $($ilFiles.Count) .il files, removing..."
            $ilFiles | Remove-Item -Force
        }
        $fileCount = (Get-ChildItem -Path $dir -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "Files in dir: $fileCount"
    }
}
