# CLAUDE.md - DancherLink Project Guide

## What is this project?
DancherLink is an enhanced PC game streaming client based on Moonlight, targeting Windows. It connects to NVIDIA GameStream or Sunshine hosts for low-latency game streaming with hardware-accelerated video decoding.

## Build
- **Requirements**: Qt 6.8+ (MSVC 2022 x64), CMake 3.16+, Visual Studio 2022, Ninja
- **Build command**: Open "x64 Native Tools Command Prompt for VS 2022", ensure Qt bin is in PATH, run:
  ```
  scripts\build-arch.bat Release x64
  ```
- **IDE**: Can be opened directly in Qt Creator, Visual Studio, or any CMake-aware IDE
- **Post-build**: MSI automatically copies to `server/` and updates `updates.json`

## Local Distribution
- **Subscription URL**: `\\{host}\Users\{user}\Programs\DancherLink-qt\server\updates.json`
- `server/updates.json` — Manifest for auto-update (arch must be `x86_64` to match Qt)
- `server/update_version.py` — Called by build script to copy MSI and update manifest

## Project Structure
- `app/` — Main application (C++ backend + QML frontend)
- `moonlight-common-c/` — Core streaming protocol (git submodule)
- `qmdnsengine/` — mDNS discovery (git submodule)
- `h264bitstream/` — H.264 parsing library
- `AntiHooking/` — Windows anti-hook DLL
- `libs/windows/` — Prebuilt dependencies (OpenSSL, SDL2, FFmpeg, etc.)
- `wix/` — WiX installer project
- `scripts/` — Build and packaging scripts
- `server/` — Local distribution (updates.json, MSI, update_version.py)

## Key Files
- `app/main.cpp` — Entry point, logging, single instance
- `app/gui/main.qml` — Main UI window
- `app/gui/StreamSegue.qml` — Stream launch splash screen
- `app/streaming/video/ffmpeg.cpp` — Video decoder initialization
- `app/streaming/video/ffmpeg-renderers/d3d11va.cpp` — Primary Windows video renderer
- `app/streaming/session.cpp` — Streaming session lifecycle
- `app/backend/computermanager.cpp` — PC discovery and management
- `app/version.txt` — Version number (format: X.Y.Z.build)

## Conventions
- C++17, Qt 6 QML (Material Design dark theme)
- MSVC on Windows; `/W3` warning level with some suppressions
- Platform workarounds marked with `HACK` comments
- Device-specific fixes (e.g. ThinkPad X1 Fold) are intentional — do not generalize without asking
- Prefer `SDL_Log*` for logging in streaming/video code, `qDebug`/`qWarning` in Qt code
- Thread safety: `SDL_mutex` for D3D11 context, `QReadWriteLock` for shared state, `SDL_Atomic` for flags, `std::atomic` for cancellation flags

## Notes
- Pairing cancellation: `ComputerManager::cancelPendingPairing()` cancels active pairing via atomic flag
- STUN is disabled for privacy (DancherLink-specific)
