$acl = Get-Acl 'C:\build-temp'
Write-Host "Directory: C:\build-temp"
Write-Host "Owner: $($acl.Owner)"
Write-Host "Access:"
$acl.Access | Format-Table -AutoSize

# Check if directory is writable
$testFile = "C:\build-temp\test_write.tmp"
try {
    Set-Content -Path $testFile -Value "test"
    Write-Host "Write test: SUCCESS"
    Remove-Item $testFile
} catch {
    Write-Host "Write test: FAILED - $_"
}
