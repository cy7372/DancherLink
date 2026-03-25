# QML 关键路径稳定性分析

## 概述

本文档记录 DancherLink 项目中 QML 代码的关键路径稳定性问题及其修复方案。这些问题是导致"修改代码后之前的 bug 频繁重现"的根本原因。

## 问题分类

### 1. 信号连接泄漏 (Signal Connection Leaks)

**症状**: 页面反复进入/退出后，信号被触发多次，导致重复操作或崩溃。

**根本原因**: QML 中使用 `StackView.onActivated` 连接信号，但没有在 `StackView.onDeactivating` 中断开。

**涉及文件**:
- `CliStartStreamSegue.qml` - launcher 信号
- `CliPair.qml` - launcher 信号

**修复模式**:
```qml
StackView.onActivated: {
    launcher.someSignal.connect(someHandler)
}

StackView.onDeactivating: {
    launcher.someSignal.disconnect(someHandler)
}
```

### 2. 动态组件创建失败未处理

**症状**: 点击按钮无反应、页面跳转失败、控制台报错 "Component is not ready"。

**根本原因**: 使用 `Qt.createComponent()` 和 `createObject()` 时没有检查返回值。

**涉及文件**:
- `StreamSegue.qml` - QuitSegue 创建
- `CliStartStreamSegue.qml` - StreamSegue 创建
- `CliPair.qml` - QuitSegue 创建（quitAppDialog.quitApp）
- `PcView.qml` - AppView 创建（两处）
- `AppView.qml` - QuitSegue 创建
- `QuitSegue.qml` - StreamSegue 创建

**修复模式**:
```qml
var component = Qt.createComponent("SomeFile.qml")
if (component.status !== Component.Ready) {
    console.error("Failed to create component:", component.errorString())
    return
}
var obj = component.createObject(parent, params)
if (!obj) {
    console.error("Failed to create object")
    return
}
```

### 3. QML 对象创建失败未处理

**症状**: 空指针访问导致崩溃或异常行为。

**根本原因**: 使用 `Qt.createQmlObject()` 创建对象时没有检查 null。

**涉及文件**:
- `PcView.qml` - ComputerModel 创建
- `AppView.qml` - AppModel 创建

**修复模式**:
```qml
var model = Qt.createQmlObject('...', parent, '')
if (!model) {
    console.error("Failed to create model")
    return null
}
```

### 4. 信号断开时对象已被销毁

**症状**: 退出页面时崩溃或报错 "Cannot disconnect signal from null object"。

**根本原因**: 在 `StackView.onDeactivating` 中断开信号时，对象可能已经被销毁。

**涉及文件**:
- `StreamSegue.qml` - session 对象

**修复模式**:
```qml
StackView.onDeactivating: {
    if (session) {
        session.someSignal.disconnect(someHandler)
    }
}
```

7. `CliQuitStreamSegue.qml`
   - 缺少 `StackView.onDeactivating` 信号断开
   - 导致 launcher 信号泄漏

## 修复汇总

### StreamSegue.qml

**问题**:
1. `quitStarting()` 未检查组件状态
2. `StackView.onDeactivating` 未检查 session 是否为 null

**修复**:
```qml
function quitStarting() {
    var component = Qt.createComponent("QuitSegue.qml")
    if (component.status !== Component.Ready) {
        console.error("Failed to create QuitSegue component:", component.errorString())
        return
    }
    var segue = component.createObject(stackView, {"appName": appName})
    if (!segue) {
        console.error("Failed to create QuitSegue object")
        return
    }
    stackView.replace(stackView.currentItem, segue, StackView.Immediate)
    window.showNormal()
}

StackView.onDeactivating: {
    toolBar.visible = true
    SdlGamepadKeyNavigation.enable()
    if (session) {  // 添加 null 检查
        session.stageStarting.disconnect(stageStarting)
        // ... 其他信号
    }
}
```

### CliStartStreamSegue.qml

**问题**:
1. 缺少 `StackView.onDeactivating` 信号断开
2. `onSessionCreated` 未检查组件状态
3. `quitAppDialog.quitApp` 未检查组件状态

**修复**:
- 添加完整的 `StackView.onDeactivating` 处理器
- 在 `onSessionCreated` 和 `quitApp` 中添加组件状态检查

### CliPair.qml

**问题**:
1. 缺少 `StackView.onDeactivating` 信号断开

**修复**:
```qml
StackView.onDeactivating: {
    launcher.searchingComputer.disconnect(onSearchingComputer)
    launcher.pairing.disconnect(onPairing)
    launcher.failed.disconnect(onFailed)
    launcher.success.disconnect(onSuccess)
}
```

### PcView.qml

**问题**:
1. `createModel()` 未检查 Qt.createQmlObject 返回值
2. AppView 创建（两处）未检查组件状态

**修复**:
- `createModel()` 返回 null 检查
- 所有 `Qt.createComponent("AppView.qml")` 添加状态检查

### AppView.qml

**问题**:
1. `createModel()` 未检查 Qt.createQmlObject 返回值
2. `quitAppDialog.quitApp()` 未检查组件状态

**修复**:
- `createModel()` 返回 null 检查
- `quitApp()` 添加组件状态检查

### QuitSegue.qml

**问题**:
1. `quitAppCompleted` 中 StreamSegue 创建未检查组件状态

**修复**:
```qml
var component = Qt.createComponent("StreamSegue.qml")
if (component.status !== Component.Ready) {
    console.error("Failed to create StreamSegue component:", component.errorString())
    stackView.pop()
    return
}
var segue = component.createObject(stackView, {...})
if (!segue) {
    console.error("Failed to create StreamSegue object")
    stackView.pop()
    return
}
stackView.replace(segue)
```

## 预防指南

#### CliQuitStreamSegue.qml

**问题**:
- 缺少 `StackView.onDeactivating` 信号断开

**修复**:
```qml
StackView.onDeactivating: {
    launcher.searchingComputer.disconnect(onSearchingComputer)
    launcher.quittingApp.disconnect(onQuittingApp)
    launcher.failed.disconnect(onFailure)
}
```

## 代码审查检查清单

1. **信号连接**
   - [ ] 每个 `connect()` 都有对应的 `disconnect()`
   - [ ] `disconnect()` 在 `StackView.onDeactivating` 或 `Component.onDestruction` 中
   - [ ] 断开信号前检查对象是否为 null

2. **动态组件创建**
   - [ ] `Qt.createComponent()` 后检查 `status !== Component.Ready`
   - [ ] `createObject()` 后检查结果是否为 null
   - [ ] 失败时有适当的错误处理和日志

3. **QML 对象创建**
   - [ ] `Qt.createQmlObject()` 后检查结果是否为 null
   - [ ] 失败时返回 null 或适当的默认值

### 常见模式

**信号连接模式**:
```qml
Item {
    function handler() { ... }

    StackView.onActivated: {
        source.signal.connect(handler)
    }

    StackView.onDeactivating: {
        if (source) {
            source.signal.disconnect(handler)
        }
    }
}
```

**组件创建模式**:
```qml
function createSomething() {
    var component = Qt.createComponent("Something.qml")
    if (component.status !== Component.Ready) {
        console.error("Failed to create Something:", component.errorString())
        return null
    }
    var obj = component.createObject(parent, params)
    if (!obj) {
        console.error("Failed to create Something object")
        return null
    }
    return obj
}
```

## 测试建议

1. **重复进入/退出测试**: 快速多次进入和退出串流页面，检查是否有重复信号触发
2. **错误注入测试**: 临时修改 QML 文件路径为不存在的文件，检查错误处理
3. **内存监控**: 长时间运行后检查内存使用，确保没有泄漏
4. **边界条件测试**: 在页面切换过程中快速操作，检查竞态条件
