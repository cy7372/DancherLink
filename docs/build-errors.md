# DancherLink 构建系统错误知识库

## 1. MSVC 临时文件错误 D8037

### 错误信息
```
cl: 命令行 error D8037 :无法创建临时 il 文件；清除临时目录中的旧 il 文件
```

### 根本原因
1. PowerShell 设置的环境变量在传递给 CMake/nmake/cl.exe 时没有被正确继承
2. `vcvarsall.bat` 会覆盖 `TMP` 和 `TEMP` 环境变量，指向用户临时目录（`C:\Users\CyYu\AppData\Local\Temp`）
3. 用户临时目录有大量旧临时文件，导致 MSVC 编译器冲突

### 解决方案
使用原生 `cmd.exe` 批处理文件运行整个构建过程：

```powershell
# 在 PowerShell 中生成批处理文件
$BatchContent = @"
@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" AMD64

set CLEAN_TEMP=C:\build-temp-%RANDOM%
if not exist "%CLEAN_TEMP%" mkdir "%CLEAN_TEMP%"
set TMP=%CLEAN_TEMP%
set TEMP=%CLEAN_TEMP%
set TMPDIR=%CLEAN_TEMP%

cd /d "$BuildFolder"
cmake -S "$RootDir" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release ...
cmake --build . --config Release --parallel 1

if exist "%CLEAN_TEMP%" rmdir /s /q "%CLEAN_TEMP%"
"@

Set-Content -Path "$BuildFolder\do-build.bat" -Value $BatchContent
cmd.exe /c "$BuildFolder\do-build.bat"
```

**关键点**：
- 在 `vcvarsall.bat` **之后** 设置 `TMP`/`TEMP`
- 先创建临时目录，再设置环境变量
- 使用 `--parallel 1` 避免并行编译时的临时文件冲突
- 每个构建使用唯一的临时目录名

---

## 2. WiX MSI 构建失败 - .NET Aspire 兼容性

### 错误信息
```
error MSB4184: 无法计算表达式"[MSBuild]::NormalizePath(..., \\CombinedComponentSchema.json)"
UNC 路径的形式应为 \\server\share
```

### 根本原因
WiX Toolset SDK 项目模板（`<Project Sdk="WixToolset.Sdk/6.0.2">`）自动引入了 .NET Aspire 支持，与当前 MSBuild 版本不兼容。

### 解决方案
使用 WiX CLI (`wix build`) 代替 MSBuild 构建 MSI：

```powershell
# 安装必要扩展
wix extension add WixToolset.Util.wixext/6.0.2
wix extension add WixToolset.Firewall.wixext/6.0.2

# 使用 WiX CLI 构建
$WixArgs = @("build",
    "-arch", "x64",
    "-out", "$InstallerFolder\DancherLink-x86_64-$Version.msi",
    "-b", "$DeployFolder",
    "-d", "Version=$Version",
    "-d", "BuildDir=$BuildFolder",
    "-d", "DeployDir=$DeployFolder",
    "-d", "Configuration=$Configuration",
    "-ext", "WixToolset.Util.wixext",
    "-ext", "WixToolset.Firewall.wixext",
    "$RootDir\wix\DancherLink\Product.wxs")

& wix $WixArgs
```

---

## 3. WiX 组件 GUID 冲突

### 错误信息
```
error WIX0369: Component/@Id='Moonlight' with source path '...\DancherLink.exe'
has a @Guid value '{3EA66A64-D14F-533F-81D0-C47C56D4FE5D}' that duplicates another component
```

### 根本原因
DeployFolder 中已经有 `DancherLink.exe`（用于 windeployqt），而 `<Files Include="$(var.DeployDir)\**" />` 会包含所有文件，导致与单独定义的 `DancherLinkExe` 组件 GUID 冲突。

### 解决方案
在 windeployqt 完成后、构建 MSI 前删除 DeployFolder 中的 `DancherLink.exe`：

```powershell
# 复制到 DeployFolder 用于 windeployqt
Copy-Item $ExePath.FullName "$DeployFolder\DancherLink.exe" -Force
windeployqt @WindeployqtArgs "$DeployFolder\DancherLink.exe"

# 删除 exe，让 WiX 单独处理
Remove-Item "$DeployFolder\DancherLink.exe" -Force
```

---

## 4. CMake 配置到源目录

### 错误信息
```
Build files have been written to: C:/Users/CyYu/Programs/DancherLink-qt
```
（应该写入 build 目录）

### 根本原因
源目录有残留的 `CMakeCache.txt`，导致 CMake 误用源目录作为构建目录。

### 解决方案
清理源目录的 CMake 产物：

```powershell
# 清理源目录
Remove-Item "C:\Users\CyYu\Programs\DancherLink-qt\CMakeCache.txt" -Force
Remove-Item "C:\Users\CyYu\Programs\DancherLink-qt\CMakeFiles" -Recurse -Force
```

确保在批处理文件中正确切换目录：

```batch
set BuildFolder=C:\Users\CyYu\Programs\DancherLink-qt\build\test-cmd
if not exist "%BuildFolder%" mkdir "%BuildFolder%"
cd /d "%BuildFolder%"
cmake -S "%RootDir%" ...
```

---

## 5. NMake Makefiles 并行构建问题

### 错误信息
```
Warning: NMake does not support parallel builds. Ignoring parallel build command line option.
```

### 说明
这不是错误，是 NMake 的正常行为。NMake 不支持并行构建，`--parallel` 参数会被忽略。

如果需要并行构建，可以考虑：
- 使用 Visual Studio 生成器（如果 CMake 支持 VS 2026）
- 接受串行构建

---

## 6. 批处理文件中 PowerShell 反引号无效

### 错误信息
```
'-DCMAKE_BUILD_TYPE' is not recognized as an internal or external command
```

### 根本原因
在批处理文件中使用 PowerShell 风格的行继续符（反引号 `` ` ``），但批处理文件使用 `^` 作为转义符，或用空格分隔所有参数。

### 解决方案
在批处理文件内容中使用单行命令或正确语法：

```powershell
# 错误 - PowerShell 语法
cmake -S "$RootDir" -G "NMake Makefiles" `
    -DCMAKE_BUILD_TYPE="Release" `
    ...

# 正确 - 单行或批处理语法
$BatchContent = @"
cmake -S "$RootDir" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE="Release" -DARCH_DIR="$Arch" ...
"@
```

---

## 7. vswhere.exe 在批处理文件中找不到

### 错误信息
```
'vswhere.exe' is not recognized as an internal or external command
```

### 根本原因
在批处理文件中使用 PowerShell 变量 `$VsWhere`，但批处理文件使用 `%VAR%` 语法。

### 解决方案
在批处理文件中硬编码路径或使用批处理变量：

```powershell
$BatchContent = @"
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" AMD64
"@
```

或者在 PowerShell 中解析所有变量后再写入批处理文件。

---

## 总结

### 构建系统架构（最终方案）

```
PowerShell 脚本 (Build-Release.ps1)
    │
    ├── 预处理（版本同步、翻译生成）
    │
    ▼
生成临时批处理文件 (do-build.bat)
    │
    ├── 调用 vcvarsall.bat 设置 MSVC 环境
    ├── 设置干净的临时目录
    ├── 运行 CMake 配置
    └── 运行 CMake 构建 (--parallel 1)
    │
    ▼
PowerShell 脚本继续
    │
    ├── Qt 部署 (windeployqt)
    ├── MSI 构建 (wix build)
    └── 更新清单 (update_version.py)
```

### 关键文件修改
- `scripts/Build-Release.ps1` - 使用 cmd.exe 包装器运行构建
- `scripts/Build-Beta.ps1` - 同上
- `scripts/Build-Native.bat` - 独立的原生构建脚本（可选）

### 依赖项
- Qt 6.10+ (MSVC 2022 x64)
- Visual Studio 2026 (或 2022)
- CMake 3.16+
- WiX Toolset 6.0+ (CLI)
- 7-Zip（如果不需要便携版可移除）
- Ninja（可选，当前使用 NMake）
