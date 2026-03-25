# Architectural Decision Records (ADR) - DancherLink

记录项目中的重要架构决策及其背景。

## ADR Template

```markdown
### ADR-XXX: 决策标题 (YYYY-MM-DD)

**背景:**
- 为什么需要做此决策
- 解决了什么问题

**决策:**
- 选择了什么方案

**备选方案:**
- 方案1 -> 为什么被拒绝
- 方案2 -> 为什么被拒绝

**后果:**
- 好处
- 权衡
```

---

### ADR-001: QML 窗口状态管理方案 (2026-03-26)

**背景:**
- 串流应用需要在多个页面间切换（AppView -> StreamSegue -> QuitSegue -> StreamSegue）
- 退出串流后需要恢复用户之前的窗口状态（窗口化/最大化/全屏）
- 原始实现在 `StreamSegue.StackView.onActivated` 中捕获窗口状态，但在 `QuitSegue` -> `StreamSegue` 转换时会捕获错误的状态

**决策:**
- 采用"显式传递"模式管理窗口状态：
  1. 创建 `StreamSegue` 时显式传递 `previousVisibility` 属性
  2. `StreamSegue` 内部仅在 `previousVisibility === -1` 时捕获当前状态
  3. `-1` 作为哨兵值表示"未显式设置"
  4. `restoreWindowState()` 将 `-1` 视为 `Window.Windowed`

**备选方案:**
- 在 `QuitSegue` 中不调用 `showFullScreen()` -> 拒绝：过渡页面需要全屏显示
- 在 `StreamSegue` 中始终捕获状态，不管来源 -> 拒绝：导致退出串流后恢复错误状态
- 使用全局状态管理窗口状态 -> 拒绝：增加复杂性，当前方案足够简单

**后果:**
- **好处**:
  - 状态传递清晰明确
  - 避免隐式依赖时序问题
  - 易于理解和维护
- **权衡**:
  - 所有创建 `StreamSegue` 的地方都需要传递 `previousVisibility`
  - 需要记住在创建组件时捕获当前状态

---

### ADR-002: 串流窗口样式管理 (Windows) (2026-03-26)

**背景:**
- 串流期间需要隐藏 Qt 窗口，防止干扰用户操作
- Windows 会在用户按键时尝试恢复隐藏的窗口
- 需要在串流结束后正确恢复窗口样式和状态

**决策:**
- 使用 `ITaskbarList` 接口控制任务栏显示（首选方案）
- 回退到 `WS_EX_TOOLWINDOW` 窗口样式修改
- 窗口状态恢复流程：
  1. 串流开始前：调用 `setQtWindowToolStyle(true)` 移除任务栏图标
  2. 串流结束后：调用 `restoreWindowStyle()` 恢复窗口样式
  3. 根据 `previousVisibility` 恢复窗口状态（窗口化/最大化/全屏）

**备选方案:**
- 仅使用 `WS_EX_TOOLWINDOW` -> 拒绝：`ITaskbarList` 更可靠，不修改窗口样式
- 不隐藏 Qt 窗口，而是最小化 -> 拒绝：用户可能看到 Qt 窗口覆盖游戏画面
- 销毁并重新创建 Qt 窗口 -> 拒绝：实现复杂，状态管理困难

**后果:**
- **好处**:
  - 串流期间 Qt 窗口完全不可见
  - 不会干扰用户游戏操作
  - 退出后正确恢复任务栏图标
- **权衡**:
  - 需要确保 `restoreWindowStyle()` 在显示窗口前调用
  - 窗口状态和样式是两个独立的概念，需要分别管理

---
