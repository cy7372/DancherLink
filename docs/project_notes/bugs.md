# Bug Log - DancherLink

记录项目中修复的bug，包括根本原因和解决方案。

## Bug Entry Template

```markdown
### YYYY-MM-DD - 简述
- **症状**: 问题表现
- **根本原因**: 为什么发生
- **解决方案**: 如何修复
- **涉及文件**: 修改的文件列表
- **预防**: 如何避免再次发生
```

---

### 2026-03-26 - 退出串流后窗口全屏且不显示任务栏图标
- **症状**: 退出串流后，Qt窗口显示为全屏模式，不在任务栏中显示，无法通过Alt+Tab切换
- **根本原因**:
  - `QuitSegue.qml` 在切换到 `StreamSegue.qml` 后调用 `window.showFullScreen()`
  - `StreamSegue.qml` 的 `StackView.onActivated` 在激活时捕获 `window.visibility` 作为 `previousVisibility`
  - 由于此时窗口已是全屏状态，`previousVisibility` 被错误地记录为 `Window.FullScreen`
  - 串流结束后，`restoreWindowState()` 根据 `previousVisibility` 恢复窗口状态，导致窗口恢复为全屏
  - 同时 `session.restoreWindowStyle()` 恢复了窗口样式（移除了 `WS_EX_TOOLWINDOW`），但窗口状态已是全屏
  - 结果：全屏窗口 + 正常样式 = 不在任务栏显示的全屏窗口
- **解决方案**:
  1. `StreamSegue.qml`: 将 `previousVisibility` 默认值改为 `-1`（表示"未设置"）
  2. 在 `StackView.onActivated` 中，仅在 `previousVisibility === -1` 时捕获当前状态
  3. 所有创建 `StreamSegue` 的地方（`AppView.qml`, `QuitSegue.qml`, `CliStartStreamSegue.qml`）都显式传递 `previousVisibility`
  4. `restoreWindowState()` 将 `-1` 视为 `Window.Windowed`
- **涉及文件**:
  - `app/gui/StreamSegue.qml` - 修改 `previousVisibility` 逻辑
  - `app/gui/QuitSegue.qml` - 显式传递 `previousVisibility`
  - `app/gui/AppView.qml` - 显式传递 `previousVisibility`
  - `app/gui/CliStartStreamSegue.qml` - 显式传递 `previousVisibility`
- **预防**:
  - 当组件的状态捕获依赖于外部状态时，应通过属性传递而非在生命周期事件中捕获
  - 对于跨页面状态传递，显式传递属性比隐式捕获更可靠

---

### 2026-03-25 - 点击串流按钮无响应（TypeError: Cannot read property 'restartRequested' of null）
- **症状**: 点击"串流"按钮后没有任何反应，控制台报错 `TypeError: Cannot read property 'restartRequested' of null`
- **根本原因**:
  - `StreamSegue.qml` 存在两个 `StackView.onActivated` 处理程序（行33和行208）
  - QML 不允许一个属性被设置多次，导致组件创建失败
  - 错误信息 `QQmlComponent: Component is not ready` 和 `TypeError: Cannot read property 'restartRequested' of null`
- **解决方案**:
  1. 合并 `StreamSegue.qml` 中两个 `StackView.onActivated` 处理程序为一个
  2. 在 `AppView.qml` 中添加组件状态检查，防止空对象访问
  3. 在 `appmodel.h` 中添加 `Q_INVOKABLE` 到 `stopLatencyMeasurement()` 使其可从 QML 调用
  4. 在 `StreamSegue` 激活时调用 `window.showFullScreen()` 确保过渡页面全屏显示
- **涉及文件**:
  - `app/gui/StreamSegue.qml` - 合并 onActivated 处理程序
  - `app/gui/AppView.qml` - 添加组件状态检查
  - `app/gui/appmodel.h` - 添加 Q_INVOKABLE
- **预防**:
  - 在 QML 中避免重复定义同一个信号处理程序
  - 动态创建组件时始终检查 `component.status === Component.Ready`
  - 从 QML 调用的 C++ 方法必须标记为 `Q_INVOKABLE`

---

### 2026-03-31 - 鼠标悬停时卡片一直显示高亮效果
- **症状**: 鼠标悬停在 QT 界面任意位置，卡片都显示高亮背景色，看起来像 hover 效果无处不在
- **根本原因**:
  - Qt GridView 有内置行为：当用户与任何卡片交互（鼠标点击或悬停）时，GridView 会自动获得焦点并设置 `currentIndex` 指向当前项目
  - 使用 `grid.currentItem === this` 来判断卡片是否应该高亮时，这个条件会一直为真
  - 因为 GridView 自动设置 `currentIndex = 0`（第一个卡片），导致第一个卡片的 `highlighted` 始终为 `true`
  - 背景颜色一直显示高亮色，用户误以为这是 hover 效果
- **解决方案**:
  1. 在 GridView 中添加独立的 `keyboardSelectedIndex` 属性（初始值 -1），专门追踪键盘/游戏 pad 选择状态
  2. 在 NavigableItemDelegate 中使用 `grid.keyboardSelectedIndex === cardIndex` 替代 `grid.currentItem === this`
  3. 只在键盘方向键按下时更新 `keyboardSelectedIndex`
  4. 鼠标交互不会更新 `keyboardSelectedIndex`，保持 hover 和高亮状态分离
- **涉及文件**:
  - `app/gui/PcView.qml` - 添加 keyboardSelectedIndex 属性
  - `app/gui/AppView.qml` - 添加 keyboardSelectedIndex 属性
  - `app/gui/NavigableItemDelegate.qml` - 修改 highlighted 判断逻辑
- **预防**:
  - 在 QML GridView 中使用自定义高亮逻辑时，避免依赖 `currentIndex` 或 `currentItem`
  - 使用独立的属性追踪键盘/游戏 pad 选择状态
  - 明确区分鼠标 hover 状态和键盘选择状态

---
