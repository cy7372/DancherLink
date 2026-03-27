#!/bin/bash
#
# DancherLink Build System - Main Entry Point
# Usage: ./build.sh [release|beta]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Default values
BUILD_TYPE="release"      # release or beta

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        release)
            BUILD_TYPE="release"
            shift
            ;;
        beta)
            BUILD_TYPE="beta"
            shift
            ;;
        -h|--help)
            echo "DancherLink Build System"
            echo ""
            echo "Usage: ./build.sh [OPTIONS]"
            echo ""
            echo "Build Types (choose one):"
            echo "  release    Build stable release version (MSI)"
            echo "  beta       Build beta/test version (MSI)"
            echo ""
            echo "Examples:"
            echo "  ./build.sh release           # Build stable release"
            echo "  ./build.sh beta              # Build beta version"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "DancherLink Build System"
echo "========================================"
echo "Build Type: $BUILD_TYPE"
echo "Configuration: Release (optimized)"
echo "========================================"
echo ""

# Execute the appropriate build script
if [[ "$BUILD_TYPE" == "release" ]]; then
    bash "$SCRIPT_DIR/build-release.sh"
else
    bash "$SCRIPT_DIR/build-beta.sh"
fi
