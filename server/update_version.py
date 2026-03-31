#!/usr/bin/env python3
"""
Update updates.json and copy MSI to server directory.
Usage: python update_version.py <version> <arch> <config> <source_root> [build_type]

build_type: "release" (default) or "beta"
"""

import json
import os
import platform
import shutil
import sys
from pathlib import Path


def main():
    if len(sys.argv) < 5:
        print("Usage: python update_version.py <version> <arch> <config> <source_root> [build_type]")
        sys.exit(1)

    version = sys.argv[1]
    build_arch = sys.argv[2]  # e.g., "x64" from build script
    config = sys.argv[3]
    source_root = Path(sys.argv[4])
    build_type = sys.argv[5] if len(sys.argv) > 5 else "release"

    # Convert build arch to QSysInfo format
    # x64 -> x86_64, x86 -> i386, arm64 -> arm64
    arch_map = {"x64": "x86_64", "x86": "i386", "arm64": "arm64"}
    arch = arch_map.get(build_arch, build_arch)

    # Paths
    server_dir = source_root / "server"
    build_dir = source_root / "build"
    # New elegant structure: build/out/{beta|release}/
    out_folder = build_dir / f"out/{build_type}"

    # Both release and beta use updates.json
    updates_json = server_dir / "updates.json"

    print(f"Version: {version}")
    print(f"Arch: {arch} (from build arch: {build_arch})")
    print(f"Config: {config}")
    print(f"Server dir: {server_dir}")
    print(f"Build dir: {build_dir}")
    print(f"Out folder: {out_folder}")

    # Ensure server directory exists
    server_dir.mkdir(parents=True, exist_ok=True)

    # Find the MSI file from out folder
    # New structure: build/out/{beta|release}/DancherLink-{arch}-{version}.msi
    msi_file = out_folder / f"DancherLink-{arch}-{version}.msi"

    if not msi_file.exists():
        print(f"Error: MSI not found: {msi_file}")
        sys.exit(1)

    print(f"Found MSI: {msi_file}")
    print(f"MSI size: {msi_file.stat().st_size / 1024 / 1024:.2f} MB")

    # Copy MSI to server directory
    # Beta versions get -beta suffix in filename
    msi_suffix = "-beta" if build_type == "beta" else ""
    dest_msi = server_dir / f"DancherLink-{arch}-{version}{msi_suffix}.msi"
    shutil.copy2(msi_file, dest_msi)
    print(f"Copied: {dest_msi}")

    # Check for patch file
    patch_file = out_folder / f"DancherLink-{arch}-{version}.patch"
    patch_url = None
    if patch_file.exists():
        dest_patch = server_dir / f"DancherLink-{arch}-{version}{msi_suffix}.patch"
        shutil.copy2(patch_file, dest_patch)
        print(f"Copied patch: {dest_patch}")
        patch_url = f"DancherLink-{arch}-{version}{msi_suffix}.patch"

    # browser_url - relative path (no server/ prefix since updates.json is already in server dir)
    browser_url = f"DancherLink-{arch}-{version}{msi_suffix}.msi"

    # Determine build type from the build_type parameter
    # build_type is passed as 5th argument: "release" or "beta"
    is_beta = (build_type.lower() == "beta")

    # Update manifest entry
    manifest_entry = {
        "platform": "windows",
        "arch": arch,
        "version": version,
        "browser_url": browser_url
    }

    if is_beta:
        manifest_entry["isBeta"] = True

    # Add patch URL if available (for incremental updates)
    if patch_url:
        manifest_entry["patch_url"] = patch_url
        # Also include previous version for patch base detection
        if manifest:
            for prev_entry in manifest:
                if prev_entry.get("arch") == arch and prev_entry.get("isBeta") == is_beta:
                    manifest_entry["base_version"] = prev_entry.get("version")
                    break

    # Read existing manifest and merge
    manifest = []
    if updates_json.exists():
        try:
            with open(updates_json, 'r', encoding='utf-8') as f:
                existing = json.load(f)
                for entry in existing:
                    # Keep entries with different arch or different type (beta/release)
                    entry_arch = entry.get("arch", "")
                    entry_version = entry.get("version", "")
                    entry_is_beta = entry.get("isBeta", False)

                    # Skip old entry for same arch and same type
                    if entry_arch == arch and entry_is_beta == is_beta:
                        continue
                    manifest.append(entry)
        except (json.JSONDecodeError, KeyError):
            print("Warning: Could not parse existing updates.json, overwriting")

    manifest.append(manifest_entry)

    # Write updated manifest
    with open(updates_json, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write('\n')

    print(f"Updated: {updates_json}")
    print("Done!")


if __name__ == "__main__":
    main()
