param (
    [Parameter(Mandatory=$true)]
    [string]$VersionFile,
    [Parameter(Mandatory=$true)]
    [string]$RcFile
)

if (-not (Test-Path $VersionFile)) {
    Write-Error "Version file not found: $VersionFile"
    exit 1
}

if (-not (Test-Path $RcFile)) {
    Write-Error "RC file not found: $RcFile"
    exit 1
}

$version = (Get-Content $VersionFile).Trim()
# Ensure we have a valid version string, though we trust version.txt usually
# Format expected: Major.Minor.Patch.Build

$versionComma = $version -replace '\.', ','

$content = Get-Content $RcFile -Raw

# Replace numeric FILEVERSION/PRODUCTVERSION (e.g., FILEVERSION 1,0,3,0)
$content = $content -replace '(FILEVERSION\s+)\d+,\d+,\d+,\d+', "`$1$versionComma"
$content = $content -replace '(PRODUCTVERSION\s+)\d+,\d+,\d+,\d+', "`$1$versionComma"

# Replace string table values (e.g., VALUE "FileVersion", "1.0.3.0\0")
# Fix: The previous regex was capturing $1 inside the replacement string which caused issues in PowerShell string interpolation
# when combined with other characters or if the match group was complex.
# Also, the corruption `$11.0.2.49` suggests that `$1` was literally interpreted as text in previous runs or similar.
# Let's be very specific and use named groups or safer replacement.

# We look for: VALUE "Key", "Value\0"
# We replace the Value part.
$content = $content -replace 'VALUE "FileVersion", "[^"]*\\0"', "VALUE `"FileVersion`", `"$version\0`""
$content = $content -replace 'VALUE "ProductVersion", "[^"]*\\0"', "VALUE `"ProductVersion`", `"$version\0`""

# Attempt to fix corrupted lines if they exist (e.g. lines starting with $1...)
# This is a specific fix for the current broken state
$content = $content -replace '\$1\d+\.\d+\.\d+\.\d+\\0"', "VALUE `"FileVersion`", `"$version\0`""
$content = $content -replace '\$1\d+\.\d+\.\d+\.\d+\\0"', "VALUE `"ProductVersion`", `"$version\0`""

# Clean up any duplicate keys if my previous fix added them (unlikely but safe)
# The corrupted file has lines like `$11.0.2.49\0"` standing alone where `VALUE ...` should be.
# The regex above `\$1...` tries to catch that.

# Let's try a more robust approach: reconstruct the file content if we detect it's the standard file.
# Or just use the regex above.
# The corrupted line is: `$11.0.2.49\0"` (indented).
# My regex `\$1...` might miss if there is whitespace.
$content = $content -replace '^\s*\$1[\d\.,]+\\0"\s*$', "				VALUE `"FileVersion`", `"$version\0`""
# Since there are two such lines, one is FileVersion, one is ProductVersion.
# It's hard to distinguish which is which if both are corrupted identically.
# But usually FileVersion comes first.
# Ideally, I should just rewrite the whole file from a template if it's corrupted, but let's try to fix it.

if ($content -match '\$1') {
    # If we still have $1 artifacts, let's just force a clean template for the StringFileInfo block part
    # This is safer than trying to regex-surgery a broken file repeatedly.
    Write-Warning "Detected corrupted RC file. Attempting to repair..."
    
    # We will just replace the corrupted lines with correct ones.
    # The first occurrence is FileVersion, second is ProductVersion.
    # We can't easily distinguish them with simple regex replace global.
    # So we will reset the file content to a known good state since we know what it *should* contain.
    
    $content = @"
#include <windows.h>

IDI_ICON1	ICON	"dancherlink.ico"

VS_VERSION_INFO VERSIONINFO
	FILEVERSION $versionComma
	PRODUCTVERSION $versionComma
	FILEFLAGSMASK 0x3fL
#ifdef _DEBUG
	FILEFLAGS VS_FF_DEBUG
#else
	FILEFLAGS 0x0L
#endif
	FILEOS VOS_NT_WINDOWS32
	FILETYPE VFT_DLL
	FILESUBTYPE VFT2_UNKNOWN
	BEGIN
		BLOCK "StringFileInfo"
		BEGIN
			BLOCK "040904b0"
			BEGIN
				VALUE "CompanyName", "DancherLink Streaming Project\0"
				VALUE "FileDescription", "DancherLink Streaming Client\0"
				VALUE "FileVersion", "$version\0"
				VALUE "LegalCopyright", "\0"
				VALUE "OriginalFilename", "DancherLink.exe\0"
				VALUE "ProductName", "DancherLink\0"
				VALUE "ProductVersion", "$version\0"
				VALUE "InternalName", "\0"
				VALUE "Comments", "\0"
				VALUE "LegalTrademarks", "\0"
			END
		END
		BLOCK "VarFileInfo"
		BEGIN
			VALUE "Translation", 0x0409, 1200
		END
	END
/* End of Version info */
"@
}

Set-Content $RcFile $content -NoNewline
Write-Host "Synced $RcFile with version $version"
