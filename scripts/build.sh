#!/bin/bash
#
# DancherLink Build System - Main Entry Point
# Usage: ./build.sh [release|beta] [debug|release]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$ROOT_DIR"

# Default values
BUILD_TYPE="release"      # release or beta
CONFIG="release"          # debug or release

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
        debug)
            CONFIG="debug"
            shift
            ;;
        release)
            CONFIG="release"
            shift
            ;;
        -h|--help)
            echo "DancherLink Build System"
            echo ""
            echo "Usage: ./build.sh [OPTIONS]"
            echo ""
            echo "Build Types (choose one):"
            echo "  release    Build stable release version"
            echo "  beta       Build beta/test version"
            echo ""
            echo "Configurations (choose one):"
            echo "  debug      Build with debug symbols"
            echo "  release    Build with optimizations (default)"
            echo ""
            echo "Examples:"
            echo "  ./build.sh release release   # Build stable release"
            echo "  ./build.sh beta release      # Build beta version"
            echo "  ./build.sh beta debug        # Build beta with debug symbols"
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
echo "Configuration: $CONFIG"
echo "========================================"
echo ""

# Execute the appropriate build script
if [[ "$BUILD_TYPE" == "release" ]]; then
    bash "$SCRIPT_DIR/build-release.sh" "$CONFIG"
else
    bash "$SCRIPT_DIR/build-beta.sh" "$CONFIG"
fi
