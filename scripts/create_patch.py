#!/usr/bin/env python3
"""
DancherLink Patch Generator
Creates differential update patches between two versions
"""

import os
import sys
import json
import hashlib
import struct
import zlib
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# Try to import bsdiff4 for binary diff, fall back to simple replacement
try:
    import bsdiff4
    HAS_BSDIFF = True
    print("Using bsdiff4 for binary diff")
except ImportError:
    HAS_BSDIFF = False
    print("Warning: bsdiff4 not installed, using full file replacement")
    print("Install with: pip install bsdiff4")


class PatchGenerator:
    PATCH_MAGIC = b"DANCHERPATCH"
    PATCH_VERSION = 1

    def __init__(self, old_dir: str, new_dir: str):
        self.old_dir = Path(old_dir)
        self.new_dir = Path(new_dir)
        self.files_added: List[str] = []
        self.files_removed: List[str] = []
        self.files_modified: List[str] = []
        self.files_unchanged: List[str] = []

    def sha256_file(self, path: Path) -> bytes:
        """Calculate SHA256 hash of a file"""
        h = hashlib.sha256()
        with open(path, 'rb') as f:
            while chunk := f.read(8192):
                h.update(chunk)
        return h.digest()

    def get_all_files(self, directory: Path) -> set:
        """Get all files in directory (relative paths)"""
        files = set()
        for root, _, filenames in os.walk(directory):
            for filename in filenames:
                full_path = Path(root) / filename
                rel_path = full_path.relative_to(directory)
                files.add(str(rel_path))
        return files

    def diff_files(self, old_files: set, new_files: set) -> Tuple[List[str], List[str], List[str]]:
        """Compare file sets and categorize changes"""
        added = list(new_files - old_files)
        removed = list(old_files - new_files)
        common = old_files & new_files

        modified = []
        unchanged = []

        for rel_path in common:
            old_path = self.old_dir / rel_path
            new_path = self.new_dir / rel_path

            # Compare by hash
            old_hash = self.sha256_file(old_path)
            new_hash = self.sha256_file(new_path)

            if old_hash != new_hash:
                modified.append(rel_path)
            else:
                unchanged.append(rel_path)

        return sorted(added), sorted(removed), sorted(modified), sorted(unchanged)

    def create_binary_diff(self, old_path: Path, new_path: Path) -> Optional[bytes]:
        """Create binary diff between two files"""
        with open(old_path, 'rb') as f:
            old_data = f.read()
        with open(new_path, 'rb') as f:
            new_data = f.read()

        if HAS_BSDIFF:
            # Use bsdiff for efficient binary diff
            diff_data = bsdiff4.diff(old_data, new_data)
            # Compress the diff
            compressed = zlib.compress(diff_data, level=9)
            print(f"  bsdiff: {len(old_data):,} -> {len(new_data):,} bytes, diff: {len(diff_data):,}, compressed: {len(compressed):,}")
            return compressed
        else:
            # Fallback: just compress the new file
            compressed = zlib.compress(new_data, level=9)
            print(f"  replace: {len(old_data):,} -> {len(new_data):,} bytes, compressed: {len(compressed):,}")
            return compressed

    def create_patch(self, output_path: str) -> dict:
        """Create patch file and return metadata"""
        print(f"\nScanning old directory: {self.old_dir}")
        old_files = self.get_all_files(self.old_dir)
        print(f"  Found {len(old_files)} files")

        print(f"\nScanning new directory: {self.new_dir}")
        new_files = self.get_all_files(self.new_dir)
        print(f"  Found {len(new_files)} files")

        print("\nComparing files...")
        added, removed, modified, unchanged = self.diff_files(old_files, new_files)
        self.files_added, self.files_removed, self.files_modified, self.files_unchanged = added, removed, modified, unchanged

        print(f"\nChanges detected:")
        print(f"  Added:    {len(added)}")
        print(f"  Removed:  {len(removed)}")
        print(f"  Modified: {len(modified)}")
        print(f"  Unchanged: {len(unchanged)}")

        # Calculate total sizes
        old_total = sum((self.old_dir / f).stat().st_size for f in old_files)
        new_total = sum((self.new_dir / f).stat().st_size for f in new_files)

        print(f"\nTotal sizes:")
        print(f"  Old: {old_total:,} bytes ({old_total / 1024 / 1024:.2f} MB)")
        print(f"  New: {new_total:,} bytes ({new_total / 1024 / 1024:.2f} MB)")

        # Create patch file
        print(f"\nCreating patch: {output_path}")
        patch_size = 0

        with open(output_path, 'wb') as patch_file:
            # Write header
            patch_file.write(self.PATCH_MAGIC)  # 12 bytes
            patch_file.write(struct.pack('>I', self.PATCH_VERSION))  # 4 bytes
            patch_file.write(struct.pack('>Q', old_total))  # 8 bytes
            patch_file.write(struct.pack('>Q', new_total))  # 8 bytes
            patch_file.write(struct.pack('>I', len(added) + len(removed) + len(modified)))  # 4 bytes

            # Process added files
            for rel_path in added:
                new_path = self.new_dir / rel_path
                new_data = new_path.read_bytes()
                new_hash = self.sha256_file(new_path)
                compressed = zlib.compress(new_data, level=9)

                self._write_file_entry(
                    patch_file, rel_path,
                    source_size=0, target_size=len(new_data),
                    source_hash=b'\x00' * 32, target_hash=new_hash,
                    is_added=True, is_deleted=False, is_replaced=False,
                    diff_data=compressed
                )
                patch_size += len(compressed)
                print(f"  + {rel_path}")

            # Process removed files
            for rel_path in removed:
                old_path = self.old_dir / rel_path
                old_hash = self.sha256_file(old_path)

                self._write_file_entry(
                    patch_file, rel_path,
                    source_size=old_path.stat().st_size, target_size=0,
                    source_hash=old_hash, target_hash=b'\x00' * 32,
                    is_added=False, is_deleted=True, is_replaced=False,
                    diff_data=b''
                )
                print(f"  - {rel_path}")

            # Process modified files
            for rel_path in modified:
                old_path = self.old_dir / rel_path
                new_path = self.new_dir / rel_path
                old_hash = self.sha256_file(old_path)
                new_hash = self.sha256_file(new_path)

                diff_data = self.create_binary_diff(old_path, new_path)
                if not diff_data:
                    # Fallback to full replacement
                    diff_data = zlib.compress(new_path.read_bytes(), level=9)
                    is_replaced = True
                else:
                    is_replaced = False

                self._write_file_entry(
                    patch_file, rel_path,
                    source_size=old_path.stat().st_size,
                    target_size=new_path.stat().st_size,
                    source_hash=old_hash, target_hash=new_hash,
                    is_added=False, is_deleted=False, is_replaced=is_replaced,
                    diff_data=diff_data
                )
                patch_size += len(diff_data)
                print(f"  ~ {rel_path}")

        print(f"\nPatch created: {output_path}")
        print(f"  Patch size: {patch_size:,} bytes ({patch_size / 1024 / 1024:.2f} MB)")

        # Calculate savings
        if new_total > 0:
            savings = (1 - patch_size / new_total) * 100
            print(f"  Savings: {savings:.1f}% (vs full download)")

        # Return metadata
        return {
            "patch_size": patch_size,
            "files_added": len(added),
            "files_removed": len(removed),
            "files_modified": len(modified),
            "old_total": old_total,
            "new_total": new_total,
            "savings_percent": savings if new_total > 0 else 0
        }

    def _write_file_entry(self, patch_file, rel_path: str, source_size: int,
                          target_size: int, source_hash: bytes, target_hash: bytes,
                          is_added: bool, is_deleted: bool, is_replaced: bool,
                          diff_data: bytes):
        """Write a file entry to the patch"""
        # Relative path (with length prefix)
        path_bytes = rel_path.encode('utf-8')
        patch_file.write(struct.pack('>I', len(path_bytes)))
        patch_file.write(path_bytes)

        # Sizes
        patch_file.write(struct.pack('>Q', source_size))
        patch_file.write(struct.pack('>Q', target_size))

        # Hashes
        patch_file.write(source_hash)
        patch_file.write(target_hash)

        # Flags
        patch_file.write(b'\x01' if is_added else b'\x00')
        patch_file.write(b'\x01' if is_deleted else b'\x00')
        patch_file.write(b'\x01' if is_replaced else b'\x00')

        # Diff data (with length prefix)
        patch_file.write(struct.pack('>I', len(diff_data)))
        patch_file.write(diff_data)


def main():
    if len(sys.argv) < 4:
        print("Usage: python create_patch.py <old_dir> <new_dir> <output.patch>")
        print("\nExample:")
        print("  python create_patch.py build/out/beta/app build/out/release/app patch.patch")
        sys.exit(1)

    old_dir = sys.argv[1]
    new_dir = sys.argv[2]
    output_path = sys.argv[3]

    if not os.path.isdir(old_dir):
        print(f"Error: Old directory not found: {old_dir}")
        sys.exit(1)

    if not os.path.isdir(new_dir):
        print(f"Error: New directory not found: {new_dir}")
        sys.exit(1)

    generator = PatchGenerator(old_dir, new_dir)
    metadata = generator.create_patch(output_path)

    # Save metadata
    metadata_path = output_path + '.json'
    with open(metadata_path, 'w') as f:
        json.dump(metadata, f, indent=2)
    print(f"\nMetadata saved to: {metadata_path}")

    print("\n[OK] Patch generation complete!")


if __name__ == "__main__":
    main()
