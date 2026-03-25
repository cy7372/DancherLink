# Work Log - DancherLink

记录项目工作历史。

## Entry Template

```markdown
### YYYY-MM-DD - 简述
- **状态**: 已完成/进行中/阻塞
- **描述**: 工作内容
- **备注**: 重要上下文
```

---

### 2026-03-26 - 修复窗口状态恢复bug
- **状态**: 已完成
- **描述**:
  - 问题：退出串流后出现全屏且不在任务栏的窗口
  - 修复：修改 `StreamSegue.qml`, `QuitSegue.qml`, `AppView.qml`, `CliStartStreamSegue.qml` 中的窗口状态传递逻辑
  - 构建：成功构建 release 版本
  - 文档：创建项目记忆系统，记录 bug 和架构决策
- **涉及文件**:
  - `app/gui/StreamSegue.qml`
  - `app/gui/QuitSegue.qml`
  - `app/gui/AppView.qml`
  - `app/gui/CliStartStreamSegue.qml`
- **备注**: 根本原因是在 `QuitSegue` -> `StreamSegue` 转换时，`previousVisibility` 被错误捕获为全屏状态

---

### 2026-03-25 - 修复点击串流按钮无响应问题
- **状态**: 已完成
- **描述**:
  - 问题：点击"串流"按钮无反应，控制台报错
  - 修复：
    1. 合并 `StreamSegue.qml` 中重复的 `StackView.onActivated` 处理程序
    2. 在 `AppView.qml` 中添加组件状态检查
    3. 在 `appmodel.h` 中添加 `Q_INVOKABLE` 到 `stopLatencyMeasurement()`
    4. 添加过渡页面全屏显示
- **涉及文件**:
  - `app/gui/StreamSegue.qml`
  - `app/gui/AppView.qml`
  - `app/gui/appmodel.h`
- **备注**: 根本原因是 QML 中重复定义信号处理程序导致组件创建失败

---
