# QML 稳定性修复验证清单

## 修复汇总

本次完整检查共修复 **7 个文件** 的稳定性问题。

### 修复的文件列表

| # | 文件 | 问题类型 | 修复内容 |
|---|------|----------|----------|
| 1 | `StreamSegue.qml` | 组件创建 + 信号断开 | `quitStarting()` 添加组件状态检查；`onDeactivating` 添加 session null 检查 |
| 2 | `CliStartStreamSegue.qml` | 信号泄漏 + 组件创建 | 添加 `StackView.onDeactivating`；`onSessionCreated` 添加状态检查 |
| 3 | `CliPair.qml` | 信号泄漏 | 添加 `StackView.onDeactivating` 信号断开 |
| 4 | `CliQuitStreamSegue.qml` | 信号泄漏 | 添加 `StackView.onDeactivating` 信号断开 |
| 5 | `PcView.qml` | 空指针访问 | `createModel()` 添加 null 检查；两处 AppView 创建添加状态检查 |
| 6 | `AppView.qml` | 空指针访问 + 组件创建 | `createModel()` 添加 null 检查；`quitApp()` 添加组件状态检查 |
| 7 | `QuitSegue.qml` | 组件创建 | `quitAppCompleted()` 添加 StreamSegue 创建状态检查 |

## 问题分类统计

### 1. 信号连接泄漏 (4 个文件)
- **症状**: 页面反复进入/退出后，信号被触发多次
- **修复**: 添加 `StackView.onDeactivating` 断开信号
- **文件**: CliStartStreamSegue.qml, CliPair.qml, CliQuitStreamSegue.qml

### 2. 动态组件创建失败未处理 (5 个文件)
- **症状**: 点击按钮无反应、页面跳转失败
- **修复**: 检查 `component.status !== Component.Ready` 和 `createObject()` 返回值
- **文件**: StreamSegue.qml, CliStartStreamSegue.qml, PcView.qml, AppView.qml, QuitSegue.qml

### 3. QML 对象创建失败未处理 (2 个文件)
- **症状**: 空指针访问导致崩溃
- **修复**: 检查 `Qt.createQmlObject()` 返回值
- **文件**: PcView.qml, AppView.qml

### 4. 信号断开时对象已被销毁 (1 个文件)
- **症状**: 退出页面时崩溃
- **修复**: 断开信号前检查对象是否为 null
- **文件**: StreamSegue.qml

## 验证测试建议

### 1. 重复进入/退出测试
```
步骤:
1. 进入 PC 列表 -> 进入 App 列表 -> 开始串流 -> 退出串流
2. 重复上述步骤 5-10 次
3. 观察是否有重复触发或崩溃

预期结果: 每次都能正常进入和退出，无重复信号触发
```

### 2. 快速切换测试
```
步骤:
1. 快速连续点击不同 PC 进入 App 列表
2. 快速连续点击串流按钮
3. 在串流启动过程中快速按退出键

预期结果: 无崩溃， gracefully 处理快速操作
```

### 3. 错误注入测试
```
步骤:
1. 临时修改 QML 文件路径为不存在的文件（用于测试错误处理）
2. 观察是否能正确捕获错误并显示日志

预期结果: 控制台显示 "Failed to create X component"，无崩溃
```

### 4. 内存监控测试
```
步骤:
1. 长时间运行应用（30分钟以上）
2. 反复进入/退出串流页面
3. 监控内存使用情况

预期结果: 内存使用稳定，无持续增长
```

### 5. CLI 启动测试
```
步骤:
1. 使用命令行参数直接启动串流
2. 测试 CLI 配对流程
3. 测试 CLI 退出应用流程

预期结果: CLI 流程正常工作，无信号泄漏
```

## 代码审查检查清单

### 新增代码审查项目

- [ ] **信号连接模式**: 每个 `connect()` 都有对应的 `disconnect()`
- [ ] **信号断开位置**: `disconnect()` 在 `StackView.onDeactivating` 或 `Component.onDestruction` 中
- [ ] **信号断开安全**: 断开信号前检查对象是否为 null
- [ ] **组件创建检查**: `Qt.createComponent()` 后检查 `status !== Component.Ready`
- [ ] **对象创建检查**: `createObject()` 后检查结果是否为 null
- [ ] **QML 对象检查**: `Qt.createQmlObject()` 后检查结果是否为 null
- [ ] **错误处理**: 失败时有适当的错误处理和日志输出
- [ ] **资源释放**: 动态创建的对象有明确的销毁机制

### 禁止模式

```qml
// ❌ 禁止: 没有断开信号
StackView.onActivated: {
    source.signal.connect(handler)
}

// ❌ 禁止: 没有检查组件状态
var component = Qt.createComponent("Something.qml")
var obj = component.createObject(parent)
stackView.push(obj)

// ❌ 禁止: 没有检查 QML 对象创建
var model = Qt.createQmlObject('...', parent, '')
model.initialize()
```

### 推荐模式

```qml
// ✅ 推荐: 完整的信号连接/断开
StackView.onActivated: {
    source.signal.connect(handler)
}
StackView.onDeactivating: {
    if (source) {
        source.signal.disconnect(handler)
    }
}

// ✅ 推荐: 完整的组件创建检查
var component = Qt.createComponent("Something.qml")
if (component.status !== Component.Ready) {
    console.error("Failed to create component:", component.errorString())
    return
}
var obj = component.createObject(parent, params)
if (!obj) {
    console.error("Failed to create object")
    return
}
stackView.push(obj)

// ✅ 推荐: QML 对象创建检查
var model = Qt.createQmlObject('...', parent, '')
if (!model) {
    console.error("Failed to create model")
    return null
}
model.initialize()
```

## 日志检查

构建后运行应用，检查控制台是否有以下错误：

```
❌ 错误信号 (不应该出现):
- "Cannot read property 'X' of null"
- "Property 'X' of object Y is not a function"
- "Component is not ready"
- "Cannot disconnect signal from null object"

✅ 预期日志 (修复后正常):
- "StreamSegue: restoreWindowState() called, previousVisibility = ..."
- "Failed to create X component: ..." (错误注入测试时)
```

## 后续维护建议

1. **定期审查**: 每次添加新功能时，检查是否引入新的信号连接或动态组件创建
2. **代码审查**: 将本检查清单纳入代码审查流程
3. **自动化测试**: 考虑添加重复进入/退出的自动化测试
4. **日志监控**: 发布版本保留关键日志，便于远程诊断问题
