<#
.SYNOPSIS
    DancherLink Build Configuration
.DESCRIPTION
    Centralized configuration for build scripts.
#>

$BuildConfig = @{
    # Qt Configuration
    QtPath = if ($env:QTDIR) { "$env:QTDIR\bin" } else { "C:\Qt\6.10.1\msvc2022_64\bin" }
    QtCMakeDir = "C:\Qt\6.10.1\msvc2022_64\lib\cmake\Qt6"

    # OpenSSL Configuration
    OpenSslInc = "$PSScriptRoot\..\libs\windows\include\x64"

    # Build Configuration
    VcArch = "AMD64"
    CMakeGenerator = "Ninja"
    CMakeBuildType = "Release"

    # Qt Deploy Configuration (windeployqt)
    WindeployqtOptions = @(
        "--release",
        "--qmldir", "app\gui",
        "--no-opengl-sw",
        "--no-compiler-runtime",
        "--no-sql",
        "--no-system-d3d-compiler",
        "--no-system-dxc-compiler",
        "--skip-plugin-types", "qmltooling,generic",
        "--no-ffmpeg",
        "--no-quickcontrols2fusion",
        "--no-quickcontrols2imagine",
        "--no-quickcontrols2universal",
        "--no-quickcontrols2fusionstyleimpl",
        "--no-quickcontrols2imaginestyleimpl",
        "--no-quickcontrols2universalstyleimpl",
        "--no-quickcontrols2windowsstyleimpl",
        "--no-translations"
    )

    # Qt Translation Files
    QtTranslations = @(
        "qt_zh_CN.qm",
        "qtbase_zh_CN.qm",
        "qtquick_zh_CN.qm",
        "qtmultimedia_zh_CN.qm"
    )

    # Unused Qt Styles to Remove
    UnusedQtStyles = @("Fusion", "Imagine", "Universal", "Windows", "NativeStyle")

    # WiX Configuration
    WixExtensions = @("WixToolset.Util.wixext", "WixToolset.Firewall.wixext")
}

# Export config to parent scope
Set-Variable -Name "BuildConfig" -Value $BuildConfig -Scope Global
