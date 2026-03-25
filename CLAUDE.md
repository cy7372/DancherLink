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
- `app/streaming/video/ffmpeg.cpp` — Video decoder initialization
- `app/streaming/video/ffmpeg-renderers/d3d11va.cpp` — Primary Windows video renderer
- `app/streaming/video/ffmpeg-renderers/gpuopts.cpp` — GPU optimization (HAGS, priority)
- `app/streaming/session.cpp` — Streaming session lifecycle
- `app/backend/computermanager.cpp` — PC discovery and management
- `moonlight-common-c/src/PlatformSockets.c` — Socket buffer configuration
- `moonlight-common-c/src/VideoStream.c` — RTP packet buffering

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
- Network buffers: Socket RCVBUF min 512KB, RTP buffer 8192 packets (optimized for 4K high bitrate)
- GPU optimization: Auto-detects HAGS, sets GPU process/thread priority for streaming

## Project Memory System

项目维护机构知识在 `docs/project_notes/` 目录中，用于跨会话保持一致性。

### 记忆文件

- **bugs.md** - Bug 日志，含根本原因和解决方案
- **decisions.md** - 架构决策记录 (ADRs)，含背景和权衡
- **key_facts.md** - 项目配置、端口、URL、开发规范
- **issues.md** - 工作日志

### 使用协议

**遇到错误或 Bug 时:**
- 先搜索 `docs/project_notes/bugs.md` 查找类似问题
- 如有已知解决方案，优先应用
- 修复新问题后，记录到 bugs.md

**提议架构变更时:**
- 检查 `docs/project_notes/decisions.md` 中的现有决策
- 确保新方案不与过去决策冲突
- 如需变更，更新决策记录

**查找项目配置时:**
- 检查 `docs/project_notes/key_facts.md` 获取构建配置、端口、URL
- 优先使用文档化的事实而非假设

### 风格指南

- 使用项目列表而非表格，便于编辑
- 保持条目简洁（1-3 行描述）
- 始终包含日期
- 包含 URL 链接（工单、文档等）
