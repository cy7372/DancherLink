# Key Facts - DancherLink

项目配置、端口、URL 和其他重要信息。

## 项目概述

DancherLink 是基于 Moonlight 的增强版 PC 游戏串流客户端，支持 Windows 平台。

## 构建设置

### 要求
- Qt 6.8+ (MSVC 2022 x64)
- CMake 3.16+
- Visual Studio 2022
- Ninja

### 构建命令
```cmd
# 打开 "x64 Native Tools Command Prompt for VS 2022"
# 确保 Qt bin 在 PATH 中
scripts\build-arch.bat release
```

### 输出目录
- 构建输出: `build/build-x64-release/`
- 部署输出: `build/deploy-x64-release/`
- 安装包: `build/installer-x64-release/`
- 符号文件: `build/symbols-x64-release/`

## 本地分发

- 订阅 URL: `\\{host}\Users\{user}\Release\DancherLink\updates.json`
- 更新清单: `server/updates.json` (自动复制到 C:\Users\CyYu\Release\DancherLink)
- 版本脚本: `server/update_version.py`
- **发布目录**: `C:\Users\CyYu\Release\DancherLink`

## 代码规范

- C++17, Qt 6 QML (Material Design dark theme)
- MSVC on Windows; `/W3` 警告级别
- 平台 workaround 标记为 `HACK` 注释
- 设备特定修复（如 ThinkPad X1 Fold）不要泛化
- 流式/视频代码使用 `SDL_Log*`，Qt 代码使用 `qDebug`/`qWarning`
- 线程安全：
  - `SDL_mutex` 用于 D3D11 上下文
  - `QReadWriteLock` 用于共享状态
  - `SDL_Atomic` 用于标志位
  - `std::atomic` 用于取消标志

## 关键文件

| 文件 | 用途 |
|------|------|
| `app/main.cpp` | 入口点、日志、单例实例 |
| `app/gui/main.qml` | 主 UI 窗口 |
| `app/streaming/video/ffmpeg.cpp` | 视频解码器初始化 |
| `app/streaming/video/ffmpeg-renderers/d3d11va.cpp` | Windows 主视频渲染器 |
| `app/streaming/video/ffmpeg-renderers/gpuopts.cpp` | GPU 优化（HAGS、优先级） |
| `app/streaming/session.cpp` | 串流会话生命周期 |
| `app/backend/computermanager.cpp` | PC 发现和管理 |
| `moonlight-common-c/src/PlatformSockets.c` | Socket 缓冲区配置 |
| `moonlight-common-c/src/VideoStream.c` | RTP 包缓冲 |

## 网络配置

- STUN 已禁用（隐私考虑）
- Socket RCVBUF 最小 512KB
- RTP 缓冲区 8192 包（针对 4K 高码率优化）

## 窗口状态常量 (Qt Quick Window)

```qml
Window.Windowed    // 0 - 窗口化
Window.Minimized   // 1 - 最小化
Window.Maximized   // 2 - 最大化
Window.FullScreen  // 3 - 全屏
Window.Hidden      // 4 - 隐藏
```

## UI 显示模式 (StreamingPreferences)

```cpp
UI_WINDOWED   // 窗口化（默认）
UI_MAXIMIZED  // 最大化
UI_FULLSCREEN // 全屏
```

## 调试提示

- 使用 `--verbose` 启动参数启用详细日志
- 日志文件位置: `%APPDATA%/DancherLink/logs/`
- Windows 窗口样式问题：检查 `WS_EX_TOOLWINDOW` 和 `ITaskbarList` 使用

## 相关文档

- 项目记忆系统: `docs/project_notes/`
  - `bugs.md` - Bug 日志
  - `decisions.md` - 架构决策记录
  - `issues.md` - 工作日志
