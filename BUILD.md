# DancherLink 构建系统文档

## 快速开始

### 构建正式版
```powershell
.\scripts\Build.ps1 -Type release
```

### 构建 Beta 版
```powershell
.\scripts\Build.ps1 -Type beta
```

## 构建产物

| 文件 | 位置 | 说明 |
|------|------|------|
| MSI 安装程序 | `build/installer-x64-*/DancherLink-x86_64-*.msi` | Windows 安装程序 |
| 更新清单 | `server/updates.json` | 自动更新配置 |

## 构建要求

| 依赖 | 版本 | 说明 |
|------|------|------|
| Qt | 6.10+ MSVC 2022 x64 | GUI 框架 |
| Visual Studio | 2022/2026 | C++ 编译器 |
| CMake | 3.16+ | 构建系统 |
| WiX Toolset | 6.0+ | MSI 打包 |
| 7-Zip | 任意 | 压缩（可选） |

## 构建脚本说明

### 主入口：`Build.ps1`
- 调用 `Build-Release.ps1` 或 `Build-Beta.ps1`
- 显示帮助信息

### 核心构建：`Build-Release.ps1` / `Build-Beta.ps1`
构建流程：
1. 版本同步到 RC 文件
2. 翻译生成（lrelease）
3. CMake 配置（NMake Makefiles）
4. CMake 构建（--parallel 1）
5. Qt 部署（windeployqt）
6. MSI 打包（wix build）
7. 更新清单生成

### 辅助脚本：`Build-Native.bat`
- 独立的批处理构建脚本
- 用于调试或无 PowerShell 环境

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `QTDIR` | Qt 安装路径 | `C:\Qt\6.10.1\msvc2022_64` |
| `PATH` | 需要包含 Qt bin | 自动添加 |

## 输出目录结构

```
build/
├── build-x64-release/      # CMake 构建目录
│   ├── bin/
│   │   └── DancherLink.exe
│   ├── app/
│   │   └── release/
│   │       └── DancherLink.exe
│   └── DancherLink.msi
├── deploy-x64-release/     # 部署文件
│   ├── DancherLink.exe
│   ├── Qt6*.dll
│   └── qml/
├── installer-x64-release/  # 安装包
│   └── DancherLink-x86_64-*.msi
└── symbols-x64-release/    # 调试符号
    └── *.pdb
```

## Beta 版本特性

- 独立安装目录：`DancherLink Beta Streaming`
- 独立注册表：`HKCU\Software\DancherLink Beta Streaming Project`
- 独立更新清单：`server/updates-beta.json`
- 可与正式版共存

## 常见问题

### MSVC 临时文件错误 D8037
构建脚本已自动处理：使用独立临时目录，避免冲突。

### WiX 扩展缺失
```powershell
wix extension add WixToolset.Util.wixext/6.0.2
wix extension add WixToolset.Firewall.wixext/6.0.2
```

### 找不到 Qt
确保 `C:\Qt\6.10.1\msvc2022_64\bin` 在 PATH 中，或设置 `QTDIR` 环境变量。

## 相关文档

- `docs/build-errors.md` - 构建错误知识库
- `docs/project_notes/` - 项目记忆系统
