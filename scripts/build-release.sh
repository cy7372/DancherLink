#!/bin/bash
#
# DancherLink Release Build Script
# Usage: ./build-release.sh
#
# Note: Only Release (optimized) builds are supported.
# Debug builds are not intended for distribution.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Fixed configuration - Release only
CONFIG="release"
CMAKE_BUILD_TYPE="Release"

# Setup environment
export PATH="$LOCALAPPDATA/Microsoft/WinGet/Links:$PATH"

# Find Qt
if [[ -n "$QTDIR" ]]; then
    export PATH="$QTDIR/bin:$PATH"
elif [[ -d "C:/Qt/6.10.1/msvc2022_64/bin" ]]; then
    export PATH="C:/Qt/6.10.1/msvc2022_64/bin:$PATH"
fi

if ! command -v qmake &> /dev/null; then
    echo "Error: qmake not found in PATH"
    exit 1
fi

echo "[Release Build] Starting build process..."

# Detect architecture
QT_PATH="$(dirname "$(which qmake)")"
if [[ "$QT_PATH" == *"_arm64"* ]]; then
    ARCH="arm64"
elif [[ "$QT_PATH" == *"_64"* ]]; then
    ARCH="x64"
else
    ARCH="x86"
fi

echo "[Release Build] Architecture: $ARCH"

# Read version
VERSION="$(cat "$ROOT_DIR/app/version.txt" | tr -d '[:space:]')"
echo "[Release Build] Version: $VERSION"

# Build directories
BUILD_ROOT="$ROOT_DIR/build"
BUILD_FOLDER="$BUILD_ROOT/build-$ARCH-release"
DEPLOY_FOLDER="$BUILD_ROOT/deploy-$ARCH-release"
INSTALLER_FOLDER="$BUILD_ROOT/installer-$ARCH-release"
SYMBOLS_FOLDER="$BUILD_ROOT/symbols-$ARCH-release"

# Clean output directories
echo "[Release Build] Cleaning output directories..."
rm -rf "$DEPLOY_FOLDER" "$BUILD_FOLDER" "$INSTALLER_FOLDER" "$SYMBOLS_FOLDER"
mkdir -p "$BUILD_ROOT" "$DEPLOY_FOLDER" "$BUILD_FOLDER" "$INSTALLER_FOLDER" "$SYMBOLS_FOLDER"

# Sync version to RC file
echo "[Release Build] Syncing version to RC file..."
powershell -ExecutionPolicy Bypass -File "$SCRIPT_DIR/update_rc_version.ps1" \
    -VersionFile "$ROOT_DIR/app/version.txt" \
    -RcFile "$ROOT_DIR/app/DancherLink_resource.rc"

# Translate
echo "[Release Build] Generating translations..."
cd "$ROOT_DIR/app/languages"
for ts_file in *.ts; do
    lrelease "$ts_file"
done
cd "$ROOT_DIR"

# Find Visual Studio
VSWHERE="$SCRIPT_DIR/vswhere.exe"
VS_INSTALL_PATH=$("$VSWHERE" -latest -property installationPath)
VC_ARCH="AMD64"
call "$VS_INSTALL_PATH/VC/Auxiliary/Build/vcvarsall.bat" "$VC_ARCH"

# Find VC redistributable
VC_REDIST_DLL_PATH=$("$VSWHERE" -latest -find "VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT")

# Configure CMake
echo "[Release Build] Configuring CMake..."
OPENSSL_INC="$ROOT_DIR/libs/windows/include/x64"

cmake -S "$ROOT_DIR" -B "$BUILD_FOLDER" -G "Ninja" \
    -DCMAKE_BUILD_TYPE="$CMAKE_BUILD_TYPE" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DARCH_DIR="$ARCH" \
    -DOPENSSL_INCLUDE_DIR="$OPENSSL_INC" \
    -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="$ROOT_DIR/libs/windows/lib/$ARCH/libcrypto.lib" \
    -DOPENSSL_SSL_LIBRARY:FILEPATH="$ROOT_DIR/libs/windows/lib/$ARCH/libssl.lib"

# Build
echo "[Release Build] Compiling..."
cmake --build "$BUILD_FOLDER" --config "$CMAKE_BUILD_TYPE" --parallel

# Save PDBs
echo "[Release Build] Saving PDBs..."
find "$BUILD_FOLDER" -name "*.pdb" -exec cp {} "$SYMBOLS_FOLDER/" \;
cp "$ROOT_DIR/libs/windows/lib/$ARCH/"*.pdb "$SYMBOLS_FOLDER/" 2>/dev/null || true

# Copy dependencies
echo "[Release Build] Copying dependencies..."
cp "$ROOT_DIR/libs/windows/lib/$ARCH/"*.dll "$DEPLOY_FOLDER/"

# Copy moonlight-common-c.dll
if [[ -f "$BUILD_FOLDER/bin/moonlight-common-c.dll" ]]; then
    cp "$BUILD_FOLDER/bin/moonlight-common-c.dll" "$DEPLOY_FOLDER/"
elif [[ -f "$BUILD_FOLDER/moonlight-common-c/moonlight-common-c/release/moonlight-common-c.dll" ]]; then
    cp "$BUILD_FOLDER/moonlight-common-c/moonlight-common-c/release/moonlight-common-c.dll" "$DEPLOY_FOLDER/"
fi

# Copy GC mapping
cp "$ROOT_DIR/app/SDL_GameControllerDB/gamecontrollerdb.txt" "$DEPLOY_FOLDER/"

# Deploy Qt
WINDEPLOYQT_ARGS="--no-system-d3d-compiler --no-system-dxc-compiler --skip-plugin-types qmltooling,generic --no-ffmpeg"
WINDEPLOYQT_ARGS="$WINDEPLOYQT_ARGS --no-quickcontrols2fusion --no-quickcontrols2imagine --no-quickcontrols2universal"
WINDEPLOYQT_ARGS="$WINDEPLOYQT_ARGS --no-quickcontrols2fusionstyleimpl --no-quickcontrols2imaginestyleimpl --no-quickcontrols2universalstyleimpl --no-quickcontrols2windowsstyleimpl"
WINDEPLOYQT_ARGS="$WINDEPLOYQT_ARGS --no-translations"

EXE_PATH="$BUILD_FOLDER/bin/Release/DancherLink.exe"
if [[ ! -f "$EXE_PATH" ]]; then
    EXE_PATH="$BUILD_FOLDER/app/Release/DancherLink.exe"
fi

echo "[Release Build] Deploying Qt dependencies..."
windeployqt --dir "$DEPLOY_FOLDER" --release --qmldir "$ROOT_DIR/app/gui" \
    --no-opengl-sw --no-compiler-runtime --no-sql $WINDEPLOYQT_ARGS "$EXE_PATH"

# Deploy translations
mkdir -p "$DEPLOY_FOLDER/translations"
[[ -f "$QT_PATH/../translations/qt_zh_CN.qm" ]] && cp "$QT_PATH/../translations/qt_zh_CN.qm" "$DEPLOY_FOLDER/translations/"
[[ -f "$QT_PATH/../translations/qtbase_zh_CN.qm" ]] && cp "$QT_PATH/../translations/qtbase_zh_CN.qm" "$DEPLOY_FOLDER/translations/"
[[ -f "$QT_PATH/../translations/qtquick_zh_CN.qm" ]] && cp "$QT_PATH/../translations/qtquick_zh_CN.qm" "$DEPLOY_FOLDER/translations/"
[[ -f "$QT_PATH/../translations/qtmultimedia_zh_CN.qm" ]] && cp "$QT_PATH/../translations/qtmultimedia_zh_CN.qm" "$DEPLOY_FOLDER/translations/"

# Delete unused styles
rm -rf "$DEPLOY_FOLDER/qml/QtQuick/Controls/Fusion"
rm -rf "$DEPLOY_FOLDER/qml/QtQuick/Controls/Imagine"
rm -rf "$DEPLOY_FOLDER/qml/QtQuick/Controls/Universal"
rm -rf "$DEPLOY_FOLDER/qml/QtQuick/Controls/Windows"
rm -rf "$DEPLOY_FOLDER/qml/QtQuick/NativeStyle"

# Build MSI
echo "[Release Build] Building MSI installer..."
mkdir -p "$BUILD_FOLDER/app/release"
cp "$BUILD_FOLDER/bin/DancherLink.exe" "$BUILD_FOLDER/app/release/DancherLink.exe" 2>/dev/null || \
cp "$BUILD_FOLDER/app/Release/DancherLink.exe" "$BUILD_FOLDER/app/release/DancherLink.exe" 2>/dev/null || true

msbuild -Restore "$ROOT_DIR/wix/DancherLink/DancherLink.wixproj" \
    /p:Configuration="Release" \
    /p:Platform="$ARCH" \
    /p:MSBuildProjectExtensionsPath="$BUILD_FOLDER/" \
    /p:Version="$VERSION"

# Copy final binary
cp "$BUILD_FOLDER/bin/DancherLink.exe" "$DEPLOY_FOLDER/" 2>/dev/null || \
cp "$BUILD_FOLDER/app/DancherLink.exe" "$DEPLOY_FOLDER/"

# Create portable package
echo "[Release Build] Creating portable package..."
cp "$VC_REDIST_DLL_PATH"/*.dll "$DEPLOY_FOLDER/"
touch "$DEPLOY_FOLDER/portable.dat"
7z a "$INSTALLER_FOLDER/DancherLinkPortable-$ARCH-$VERSION.zip" "$DEPLOY_FOLDER/"*

# Copy MSI to installer folder
MSI_FILE=$(find "$BUILD_FOLDER" -name "DancherLink.msi" 2>/dev/null | head -1)
if [[ -n "$MSI_FILE" ]]; then
    cp "$MSI_FILE" "$INSTALLER_FOLDER/DancherLink-x86_64-$VERSION.msi"
fi

# Update manifest
if [[ -d "$ROOT_DIR/server" ]] && [[ -f "$ROOT_DIR/server/update_version.py" ]]; then
    echo "[Release Build] Updating server/updates.json..."
    python "$ROOT_DIR/server/update_version.py" "$VERSION" "$ARCH" "release" "$ROOT_DIR" "release"
fi

echo ""
echo "========================================"
echo "[Release Build] Build successful!"
echo "  Version: $VERSION"
echo "  MSI: $INSTALLER_FOLDER/DancherLink-x86_64-$VERSION.msi"
echo "========================================"
