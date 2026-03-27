#!/usr/bin/env python3
"""
DancherLink Build Helper - Common build functions

This module provides shared functionality for Release and Beta builds.
Used by PowerShell scripts via subprocess calls.
"""

import os
import sys
import shutil
import subprocess
import re
from pathlib import Path
from typing import Optional, List, Dict, Tuple


def get_qt_path() -> Optional[str]:
    """Get Qt bin directory from QTDIR env or default path."""
    qt_dir = os.environ.get('QTDIR')
    if qt_dir and os.path.exists(os.path.join(qt_dir, 'bin')):
        return os.path.join(qt_dir, 'bin')

    default_path = r"C:\Qt\6.10.1\msvc2022_64\bin"
    if os.path.exists(default_path):
        return default_path

    return None


def verify_qmake() -> bool:
    """Verify qmake is available in PATH."""
    return shutil.which('qmake') is not None


def detect_architecture() -> str:
    """Detect target architecture from Qt path."""
    qt_path = get_qt_path()
    if not qt_path:
        return "x64"

    qt_path_lower = qt_path.lower()
    if 'arm64' in qt_path_lower:
        return 'arm64'
    elif '_64' in qt_path_lower or 'x64' in qt_path_lower:
        return 'x64'
    else:
        return 'x86'


def get_build_paths(root_dir: str, arch: str, build_type: str) -> Dict[str, str]:
    """Get all build directory paths."""
    is_beta = build_type.lower() == 'beta'
    beta_suffix = '-beta' if is_beta else ''

    build_root = os.path.join(root_dir, 'build')
    return {
        'build_folder': os.path.join(build_root, f'build-{arch}{beta_suffix}-release'),
        'deploy_folder': os.path.join(build_root, f'deploy-{arch}{beta_suffix}-release'),
        'installer_folder': os.path.join(build_root, f'installer-{arch}{beta_suffix}-release'),
        'symbols_folder': os.path.join(root_dir, f'symbols-{arch}{beta_suffix}-release'),
    }


def clean_directories(paths: List[str]) -> None:
    """Clean and recreate directories."""
    for path in paths:
        if os.path.exists(path):
            shutil.rmtree(path)
        os.makedirs(path, exist_ok=True)


def read_version(version_file: str, is_beta: bool = False) -> str:
    """Read version from file."""
    with open(version_file, 'r') as f:
        version = f.read().strip()

    if is_beta and not version.endswith('-beta'):
        version = f"{version}-beta"

    return version


def generate_translations(languages_dir: str) -> bool:
    """Generate .qm files from .ts files."""
    if not os.path.exists(languages_dir):
        print(f"Languages directory not found: {languages_dir}")
        return False

    ts_files = list(Path(languages_dir).glob('*.ts'))
    if not ts_files:
        print("No .ts files found")
        return True

    for ts_file in ts_files:
        print(f"  Processing {ts_file.name}...")
        result = subprocess.run(['lrelease', str(ts_file)], capture_output=True)
        if result.returncode != 0:
            print(f"    Warning: lrelease failed for {ts_file.name}")

    return True


def find_vs_installation() -> Optional[str]:
    """Find Visual Studio installation path using vswhere."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    vswhere = os.path.join(script_dir, 'vswhere.exe')

    if not os.path.exists(vswhere):
        # Try system vswhere
        program_files = os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')
        vswhere = os.path.join(program_files, 'Microsoft Visual Studio', 'Installer', 'vswhere.exe')

    if not os.path.exists(vswhere):
        return None

    try:
        result = subprocess.run(
            [vswhere, '-latest', '-property', 'installationPath'],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception as e:
        print(f"Error finding VS: {e}")

    return None


def create_build_batch(
    build_folder: str,
    root_dir: str,
    arch: str,
    build_type: str,
    vs_install_path: str,
    openssl_inc: str,
    openssl_crypto: str,
    openssl_ssl: str,
    qt_path: str
) -> str:
    """Create temporary batch file for native build."""
    vc_arch = "AMD64"
    vcvarsall = os.path.join(vs_install_path, 'VC', 'Auxiliary', 'Build', 'vcvarsall.bat')
    clean_temp = f"C:\\build-temp-{os.getpid()}"

    beta_flag = " -DBUILD_TYPE=\"beta\"" if build_type.lower() == 'beta' else ""
    qt_cmake_dir = os.path.join(os.path.dirname(qt_path), 'lib', 'cmake', 'Qt6')

    batch_content = f"""@echo off
echo ========================================
echo DancherLink Build
echo ========================================
call "{vcvarsall}" {vc_arch}

echo Setting up clean temp directory...
set CLEAN_TEMP={clean_temp}
if not exist "%CLEAN_TEMP%" mkdir "%CLEAN_TEMP%"
set TMP=%CLEAN_TEMP%
set TEMP=%CLEAN_TEMP%
set TMPDIR=%CLEAN_TEMP%
echo Using temp dir: %TMP%

echo Setting up Qt path...
set PATH={qt_path};%PATH%
set Qt6_DIR={qt_cmake_dir}

cd /d "{build_folder}"

echo Running cmake configure...
cmake -S "{root_dir}" -G "Ninja" -DCMAKE_BUILD_TYPE="Release" -DARCH_DIR="{arch}"{beta_flag} -DOPENSSL_INCLUDE_DIR="{openssl_inc}" -DOPENSSL_CRYPTO_LIBRARY:FILEPATH="{openssl_crypto}" -DOPENSSL_SSL_LIBRARY:FILEPATH="{openssl_ssl}"

if %ERRORLEVEL% neq 0 (
    echo CMake configuration FAILED
    goto :cleanup
)
echo CMake configuration SUCCESS

echo.
echo Building...
cmake --build . --config Release

echo.
echo Build exit code: %ERRORLEVEL%

:cleanup
echo Cleaning up temp directory...
if exist "%CLEAN_TEMP%" rmdir /s /q "%CLEAN_TEMP%"
if %ERRORLEVEL% neq 0 (
    echo Build FAILED
    exit /b %ERRORLEVEL%
)
echo Build SUCCESS
"""

    batch_file = os.path.join(build_folder, 'do-build.bat')
    os.makedirs(build_folder, exist_ok=True)
    with open(batch_file, 'w') as f:
        f.write(batch_content)

    return batch_file


def run_build(batch_file: str) -> int:
    """Run build batch file in cmd.exe."""
    result = subprocess.run(['cmd.exe', '/c', batch_file])
    return result.returncode


def cleanup_batch(batch_file: str) -> None:
    """Remove temporary batch file."""
    if os.path.exists(batch_file):
        os.remove(batch_file)


def find_executable(search_paths: List[str], filter_pattern: str) -> Optional[str]:
    """Find executable file in search paths."""
    for search_path in search_paths:
        if not os.path.exists(search_path):
            continue
        for root, dirs, files in os.walk(search_path):
            for file in files:
                if file.lower() == filter_pattern.lower():
                    return os.path.join(root, file)
    return None


def copy_symbols(build_folder: str, symbols_folder: str, arch: str, root_dir: str) -> None:
    """Copy PDB files to symbols folder."""
    os.makedirs(symbols_folder, exist_ok=True)

    # Copy from build folder
    for root, dirs, files in os.walk(build_folder):
        for file in files:
            if file.endswith('.pdb'):
                src = os.path.join(root, file)
                dst = os.path.join(symbols_folder, file)
                shutil.copy2(src, dst)

    # Copy from libs
    libs_pdb_dir = os.path.join(root_dir, 'libs', 'windows', 'lib', arch)
    if os.path.exists(libs_pdb_dir):
        for pdb in Path(libs_pdb_dir).glob('*.pdb'):
            shutil.copy2(str(pdb), symbols_folder)


def copy_dependencies(deploy_folder: str, arch: str, root_dir: str, build_folder: str) -> None:
    """Copy dependency DLLs to deploy folder."""
    os.makedirs(deploy_folder, exist_ok=True)

    # Copy from libs
    libs_dll_dir = os.path.join(root_dir, 'libs', 'windows', 'lib', arch)
    if os.path.exists(libs_dll_dir):
        for dll in Path(libs_dll_dir).glob('*.dll'):
            shutil.copy2(str(dll), deploy_folder)

    # Copy moonlight-common-c.dll
    moonlight = find_executable([build_folder], 'moonlight-common-c.dll')
    if moonlight:
        shutil.copy2(moonlight, deploy_folder)

    # Copy game controller DB
    gcdb = os.path.join(root_dir, 'app', 'SDL_GameControllerDB', 'gamecontrollerdb.txt')
    if os.path.exists(gcdb):
        shutil.copy2(gcdb, deploy_folder)


def deploy_qt(deploy_folder: str, root_dir: str, exe_path: str) -> bool:
    """Deploy Qt dependencies using windeployqt."""
    os.makedirs(deploy_folder, exist_ok=True)

    # Copy exe temporarily
    deploy_exe = os.path.join(deploy_folder, 'DancherLink.exe')
    shutil.copy2(exe_path, deploy_exe)

    args = [
        'windeployqt',
        '--dir', deploy_folder,
        '--release',
        '--qmldir', os.path.join(root_dir, 'app', 'gui'),
        '--no-opengl-sw',
        '--no-compiler-runtime',
        '--no-sql',
        '--no-system-d3d-compiler',
        '--no-system-dxc-compiler',
        '--skip-plugin-types', 'qmltooling,generic',
        '--no-ffmpeg',
        '--no-quickcontrols2fusion',
        '--no-quickcontrols2imagine',
        '--no-quickcontrols2universal',
        '--no-quickcontrols2fusionstyleimpl',
        '--no-quickcontrols2imaginestyleimpl',
        '--no-quickcontrols2universalstyleimpl',
        '--no-quickcontrols2windowsstyleimpl',
        '--no-translations',
        deploy_exe
    ]

    result = subprocess.run(args, capture_output=True, text=True)

    # Remove exe (WiX will add it separately)
    if os.path.exists(deploy_exe):
        os.remove(deploy_exe)

    return result.returncode == 0


def deploy_qt_translations(deploy_folder: str, qt_path: str) -> None:
    """Deploy Qt translation files."""
    translations_dir = os.path.join(deploy_folder, 'translations')
    os.makedirs(translations_dir, exist_ok=True)

    qt_translations = [
        os.path.join(qt_path, '..', 'translations', 'qt_zh_CN.qm'),
        os.path.join(qt_path, '..', 'translations', 'qtbase_zh_CN.qm'),
        os.path.join(qt_path, '..', 'translations', 'qtquick_zh_CN.qm'),
        os.path.join(qt_path, '..', 'translations', 'qtmultimedia_zh_CN.qm'),
    ]

    for src in qt_translations:
        if os.path.exists(src):
            shutil.copy2(src, translations_dir)


def remove_unused_qt_styles(deploy_folder: str) -> None:
    """Remove unused Qt Quick Control styles."""
    styles = ['Fusion', 'Imagine', 'Universal', 'Windows', 'NativeStyle']

    for style in styles:
        paths_to_remove = [
            os.path.join(deploy_folder, 'qml', 'QtQuick', 'Controls', style),
            os.path.join(deploy_folder, 'qml', 'QtQuick', 'Controls', f'{style}StyleImpl'),
        ]

        for path in paths_to_remove:
            if os.path.exists(path):
                shutil.rmtree(path)


def build_msi(
    installer_folder: str,
    deploy_folder: str,
    build_folder: str,
    version: str,
    wxs_file: str,
    extensions: List[str],
    is_beta: bool = False
) -> Optional[str]:
    """Build MSI installer using WiX CLI."""
    os.makedirs(installer_folder, exist_ok=True)

    # Ensure app config dir has the exe
    app_config_dir = os.path.join(build_folder, 'app', 'release')
    os.makedirs(app_config_dir, exist_ok=True)

    built_exe = find_executable(
        [os.path.join(build_folder, 'bin'), os.path.join(build_folder, 'app')],
        'DancherLink.exe'
    )
    if built_exe:
        shutil.copy2(built_exe, app_config_dir)

    msi_output = os.path.join(installer_folder, f'DancherLink-x86_64-{version}.msi')

    args = [
        'wix', 'build',
        '-arch', 'x64',
        '-out', msi_output,
        '-b', deploy_folder,
        '-d', f'Version={version}',
        '-d', f'BuildDir={build_folder}',
        '-d', f'DeployDir={deploy_folder}',
        '-d', 'Configuration=Release'
    ]

    for ext in extensions:
        args.extend(['-ext', ext])

    args.append(wxs_file)

    print(f"Running: wix build...")
    result = subprocess.run(args, capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr)

    if os.path.exists(msi_output):
        # Copy to build folder
        build_msi = os.path.join(build_folder, 'DancherLink.msi')
        shutil.copy2(msi_output, build_msi)
        return msi_output

    return None


def update_manifest(root_dir: str, version: str, arch: str, build_type: str) -> bool:
    """Update server manifest using update_version.py."""
    script = os.path.join(root_dir, 'server', 'update_version.py')
    if not os.path.exists(script):
        return False

    args = [
        'python', script,
        version, arch, 'release', root_dir, build_type
    ]

    result = subprocess.run(args)
    return result.returncode == 0


def main():
    """CLI entry point."""
    import argparse

    parser = argparse.ArgumentParser(description='DancherLink Build Helper')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # detect-arch
    subparsers.add_parser('detect-arch', help='Detect architecture')

    # get-qt-path
    subparsers.add_parser('get-qt-path', help='Get Qt path')

    # get-paths
    paths_parser = subparsers.add_parser('get-paths', help='Get build paths')
    paths_parser.add_argument('--root', required=True, help='Root directory')
    paths_parser.add_argument('--arch', required=True, help='Architecture')
    paths_parser.add_argument('--type', required=True, help='Build type (release/beta)')

    # clean
    clean_parser = subparsers.add_parser('clean', help='Clean directories')
    clean_parser.add_argument('paths', nargs='+', help='Directories to clean')

    # verify-qmake
    subparsers.add_parser('verify-qmake', help='Verify qmake is available')

    # translations
    trans_parser = subparsers.add_parser('translations', help='Generate translations')
    trans_parser.add_argument('--dir', required=True, help='Languages directory')

    # find-vs
    subparsers.add_parser('find-vs', help='Find Visual Studio installation')

    # create-batch
    batch_parser = subparsers.add_parser('create-batch', help='Create build batch file')
    batch_parser.add_argument('--build-folder', required=True)
    batch_parser.add_argument('--root', required=True)
    batch_parser.add_argument('--arch', required=True)
    batch_parser.add_argument('--type', required=True)
    batch_parser.add_argument('--vs-path', required=True)
    batch_parser.add_argument('--openssl-inc', required=True)
    batch_parser.add_argument('--openssl-crypto', required=True)
    batch_parser.add_argument('--openssl-ssl', required=True)
    batch_parser.add_argument('--qt-path', required=True)

    # run-build
    run_parser = subparsers.add_parser('run-build', help='Run build batch file')
    run_parser.add_argument('batch_file', help='Batch file to run')

    # find-exe
    find_parser = subparsers.add_parser('find-exe', help='Find executable')
    find_parser.add_argument('--paths', nargs='+', required=True)
    find_parser.add_argument('--filter', required=True)

    # copy-symbols
    symbols_parser = subparsers.add_parser('copy-symbols', help='Copy PDB files')
    symbols_parser.add_argument('--build-folder', required=True)
    symbols_parser.add_argument('--symbols-folder', required=True)
    symbols_parser.add_argument('--arch', required=True)
    symbols_parser.add_argument('--root', required=True)

    # copy-deps
    deps_parser = subparsers.add_parser('copy-deps', help='Copy dependencies')
    deps_parser.add_argument('--deploy-folder', required=True)
    deps_parser.add_argument('--arch', required=True)
    deps_parser.add_argument('--root', required=True)
    deps_parser.add_argument('--build-folder', required=True)

    # deploy-qt
    qt_parser = subparsers.add_parser('deploy-qt', help='Deploy Qt dependencies')
    qt_parser.add_argument('--deploy-folder', required=True)
    qt_parser.add_argument('--root', required=True)
    qt_parser.add_argument('--exe', required=True)

    # deploy-qt-translations
    qt_trans_parser = subparsers.add_parser('deploy-qt-translations', help='Deploy Qt translations')
    qt_trans_parser.add_argument('--deploy-folder', required=True)
    qt_trans_parser.add_argument('--qt-path', required=True)

    # remove-styles
    styles_parser = subparsers.add_parser('remove-styles', help='Remove unused Qt styles')
    styles_parser.add_argument('--deploy-folder', required=True)

    # build-msi
    msi_parser = subparsers.add_parser('build-msi', help='Build MSI installer')
    msi_parser.add_argument('--installer-folder', required=True)
    msi_parser.add_argument('--deploy-folder', required=True)
    msi_parser.add_argument('--build-folder', required=True)
    msi_parser.add_argument('--version', required=True)
    msi_parser.add_argument('--wxs', required=True)
    msi_parser.add_argument('--type', default='release')

    # update-manifest
    manifest_parser = subparsers.add_parser('update-manifest', help='Update server manifest')
    manifest_parser.add_argument('--root', required=True)
    manifest_parser.add_argument('--version', required=True)
    manifest_parser.add_argument('--arch', required=True)
    manifest_parser.add_argument('--type', required=True)

    # read-version
    version_parser = subparsers.add_parser('read-version', help='Read version from file')
    version_parser.add_argument('--file', required=True)
    version_parser.add_argument('--beta', action='store_true')

    args = parser.parse_args()

    if args.command == 'detect-arch':
        print(detect_architecture())
    elif args.command == 'get-qt-path':
        path = get_qt_path()
        if path:
            print(path)
        else:
            sys.exit(1)
    elif args.command == 'verify-qmake':
        if verify_qmake():
            print('OK')
        else:
            sys.exit(1)
    elif args.command == 'get-paths':
        paths = get_build_paths(args.root, args.arch, args.type)
        for key, value in paths.items():
            print(f"{key}={value}")
    elif args.command == 'clean':
        clean_directories(args.paths)
        print('OK')
    elif args.command == 'translations':
        if generate_translations(args.dir):
            print('OK')
        else:
            sys.exit(1)
    elif args.command == 'find-vs':
        vs_path = find_vs_installation()
        if vs_path:
            print(vs_path)
        else:
            sys.exit(1)
    elif args.command == 'create-batch':
        batch_file = create_build_batch(
            args.build_folder, args.root, args.arch, args.type,
            args.vs_path, args.openssl_inc, args.openssl_crypto,
            args.openssl_ssl, args.qt_path
        )
        print(batch_file)
    elif args.command == 'run-build':
        exit_code = run_build(args.batch_file)
        sys.exit(exit_code)
    elif args.command == 'find-exe':
        exe = find_executable(args.paths, args.filter)
        if exe:
            print(exe)
        else:
            sys.exit(1)
    elif args.command == 'copy-symbols':
        copy_symbols(args.build_folder, args.symbols_folder, args.arch, args.root)
        print('OK')
    elif args.command == 'copy-deps':
        copy_dependencies(args.deploy_folder, args.arch, args.root, args.build_folder)
        print('OK')
    elif args.command == 'deploy-qt':
        if deploy_qt(args.deploy_folder, args.root, args.exe):
            print('OK')
        else:
            sys.exit(1)
    elif args.command == 'deploy-qt-translations':
        deploy_qt_translations(args.deploy_folder, args.qt_path)
        print('OK')
    elif args.command == 'remove-styles':
        remove_unused_qt_styles(args.deploy_folder)
        print('OK')
    elif args.command == 'build-msi':
        is_beta = args.type.lower() == 'beta'
        extensions = [] if is_beta else ['WixToolset.Util.wixext', 'WixToolset.Firewall.wixext']
        wxs_file = args.wxs
        msi_path = build_msi(
            args.installer_folder, args.deploy_folder, args.build_folder,
            args.version, wxs_file, extensions, is_beta
        )
        if msi_path:
            print(msi_path)
        else:
            sys.exit(1)
    elif args.command == 'update-manifest':
        if update_manifest(args.root, args.version, args.arch, args.type):
            print('OK')
        else:
            sys.exit(1)
    elif args.command == 'read-version':
        version = read_version(args.file, args.beta)
        print(version)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
