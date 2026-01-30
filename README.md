# DancherLink

[![Build - Windows](https://github.com/cy7372/DancherLink/actions/workflows/build-windows.yml/badge.svg)](https://github.com/cy7372/DancherLink/actions/workflows/build-windows.yml)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/cy7372/DancherLink)](https://github.com/cy7372/DancherLink/releases)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/cy7372/DancherLink?include_prereleases&label=nightly)](https://github.com/cy7372/DancherLink/releases/tag/nightly)

**DancherLink** is a specialized PC client for NVIDIA GameStream and [Sunshine](https://github.com/LizardByte/Sunshine), built upon the robust foundation of [Moonlight PC](https://moonlight-stream.org).

It focuses on enhanced window management, stability during resolution changes, and a polished user experience on Windows.

## Downloads

*   **Stable Release**: [Latest Release](https://github.com/cy7372/DancherLink/releases/latest)
*   **Nightly Build**: [Nightly Release](https://github.com/cy7372/DancherLink/releases/tag/nightly) (Updated with every commit to main)

## DancherLink Enhancements

DancherLink represents a comprehensive refactor of the Moonlight codebase, designed to be modern, stable, and extensible.

*   **Modernized Core**:
    *   **Qt 6 & CMake**: Fully ported to Qt 6 and CMake, updating library structures and dependencies from the legacy codebase.
    *   **Infrastructure Overhaul**: Refactored underlying architecture to fix bugs and pave the way for rapid feature expansion.

*   **Smart Display Adaptation**:
    *   **Dynamic Resolution**: Automatically detects local resolution and adapts.
    *   **Monitor Hot-Plug Support**: Intelligently prompts to sync resolution when connecting or disconnecting external displays during a stream.
    *   **Robust Dialogs**: Uses system-modal, always-on-top dialogs for resolution changes so they never get lost behind game windows.

*   **Enhanced Experience**:
    *   **Auto-Exit on Sleep**: Automatically quits the stream when the system sleeps or the lid is closed.
    *   **Seamless Windowing**: Initializes directly in the correct fullscreen/windowed state without visual glitches or resizing animations.
    *   **State Restoration**: Remembers and restores your window state (Maximized/Windowed) across sessions.

*   **Performance & Optimization**:
    *   **Resource Scheduling**: Superior decoding resource scheduling compared to the original, ensuring smoother playback.
    *   **Memory Management**: Refactored memory handling logic for better efficiency and lower overhead.

*   **Stability & Polish**:
    *   **Codebase Hardening**: Extensive cleanup of compiler warnings and legacy code issues.
    *   **Visual Fixes**: Resolved overlay transparency and z-ordering bugs.

---

## Core Features (Inherited from Moonlight)

- Hardware accelerated video decoding on Windows, Mac, and Linux
- H.264, HEVC, and AV1 codec support (AV1 requires Sunshine and a supported host GPU)
- YUV 4:4:4 support (Sunshine only)
- HDR streaming support
- 7.1 surround sound audio support
- 10-point multitouch support (Sunshine only)
- Gamepad support with force feedback and motion controls for up to 16 players
- Support for both pointer capture (for games) and direct mouse control (for remote desktop)
- Support for passing system-wide keyboard shortcuts like Alt+Tab to the host

## Building

### Windows Build Requirements
* **Qt 6.8 SDK** or later (MSVC 2022 64-bit)
* **CMake 3.16** or later
* [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/) (Community edition is fine)
* [Ninja](https://ninja-build.org/) (Recommended generator)
* [7-Zip](https://www.7-zip.org/) (for packaging)

### Build Instructions
To build a binary for use on non-development machines:
1. Open a "x64 Native Tools Command Prompt for VS 2022".
2. Ensure Qt `bin` directory is in your `%PATH%`.
3. Run `scripts\build-arch.bat Release x64` from the root of the repository.

*Note: The project uses standard CMake, so you can also open it directly in IDEs like Qt Creator, Visual Studio, or Trae that support CMake.*

## Release Process (Maintainers Only)

To publish a new stable release:

1.  Update the version number in `app/version.txt`.
2.  Commit the change: `git commit -am "Bump version to X.Y.Z"`.
3.  Create a git tag: `git tag vX.Y.Z`.
4.  Push changes and tags: `git push && git push --tags`.

GitHub Actions will automatically build and publish the release with the corresponding version number.

## Credits

DancherLink is based on the open-source [Moonlight PC](https://github.com/moonlight-stream/moonlight-qt) project.
Hosting for original Moonlight Debian and L4T package repositories is provided by [Cloudsmith](https://cloudsmith.com).

## License
This project is licensed under the [GNU General Public License v3.0](LICENSE).
