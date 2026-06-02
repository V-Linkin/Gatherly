# 自动更新设计文档

## 概述

将现有的「检查更新 → 打开浏览器」流程改为「检查更新 → 直接下载 DMG → 确认后自动安装替换并重启」。

## 现状问题

`UpdateChecker.openReleasePage()` 存在但未被 UI 调用。「前往下载」按钮实际调用 `resetUpdateStatus()`，点击无任何反应。

## 目标流程

```
用户点击「检查更新」
  → GitHub API 获取 latest release
  → 比较版本号
  → 有新版本 → 显示「v{version} · 下载更新」
  → 用户点击 → 下载 DMG（显示进度条）
  → 下载完成 → 弹窗「新版本已下载，是否安装？」
  → 点「安装」→ 执行安装脚本 → 退出 app → 脚本替换旧版本 → 重新打开
  → 点「稍后」→ 保留 DMG，下次启动再提示
```

## 方案选型

| 方案 | 描述 | 优劣 |
|------|------|------|
| **A. Shell 脚本替换** ✅ | DMG 下载 → 挂载 → ditto 替换 → 重启 | 简单可靠，无外部依赖 |
| B. AppleScript | 用 AppleScript 的 `do shell script` | 语法脆弱，调试困难 |
| C. Sparkle 框架 | 引入第三方自动更新框架 | 过重，个人项目不需要 |

## 技术设计

### 1. DMG 下载

- 下载地址：`https://github.com/V-Linkin/Archiver/releases/download/v{version}/Archiver_v{version}.dmg`
- 存储位置：`NSTemporaryDirectory()/Archiver_update.dmg`
- 使用 `URLSession.downloadTask` 支持进度回调
- 下载前检查可用空间（DMG 大小 × 2）

### 2. 安装脚本

嵌入 app bundle 的 `Resources/install_update.sh`：

```bash
#!/bin/bash
set -e

DMG_PATH="$1"
APP_NAME="Archiver"
APP_DISPLAY_NAME="拾屿"
INSTALL_DIR="/Applications"

# 挂载 DMG
MOUNT_POINT=$(hdiutil attach -nobrowse -quiet "$DMG_PATH" | tail -1 | awk '{print $NF}')

# 在挂载卷中查找 .app
APP_PATH=$(find "$MOUNT_POINT" -name "${APP_NAME}.app" -maxdepth 1 | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: 找不到 ${APP_NAME}.app"
    hdiutil detach "$MOUNT_POINT" -quiet
    exit 1
fi

# 检查是否在 /Applications
CURRENT_APP=$(osascript -e 'tell application "System Events" to get path of first process whose name is "'"$APP_NAME"'"' 2>/dev/null || echo "")

if [[ "$CURRENT_APP" == "${INSTALL_DIR}"* ]]; then
    # 在 /Applications，执行替换
    sleep 1  # 等待旧 app 完全退出
    ditto --norsrc "$APP_PATH" "${INSTALL_DIR}/${APP_NAME}.app"
    hdiutil detach "$MOUNT_POINT" -quiet
    rm -f "$DMG_PATH"
    open "${INSTALL_DIR}/${APP_NAME}.app"
else
    # 不在 /Applications，打开 DMG 让用户手动安装
    open "$MOUNT_POINT"
fi
```

### 3. UpdateStatus 枚举变更

```swift
enum UpdateStatus {
    case idle
    case checking
    case upToDate
    case updateAvailable(version: String, release: GitHubRelease)
    case downloading(progress: Double)        // 新增
    case downloaded(dmgPath: URL, version: String)  // 新增
    case error(String)
}
```

### 4. UpdateChecker 新增方法

```swift
// 下载 DMG
func downloadUpdate(version: String, dmgURL: URL) async

// 执行安装
func installUpdate(dmgPath: URL)

// 检查是否有已下载的更新（app 启动时调用）
func checkForDownloadedUpdate()
```

### 5. UI 变更（SettingsView）

| 状态 | 显示 | 点击行为 |
|------|------|----------|
| `idle` | 「检查」 | 触发检查 |
| `checking` | 转圈动画 | 无 |
| `updateAvailable` | 「v{version} · 下载更新」 | 开始下载 |
| `downloading` | 进度条 + 百分比 | 取消下载 |
| `downloaded` | 「安装」+「稍后」 | 安装 or 保留 |
| `upToDate` | 「已是最新」 | 重置为 idle |
| `error` | 「检查失败」（红色） | 重置为 idle |

### 6. 错误处理

| 场景 | 处理 |
|------|------|
| 网络断开 / 下载失败 | 弹窗提示，状态回退到 `updateAvailable` |
| DMG 挂载失败 | 弹窗提示「安装包损坏」，删除临时文件 |
| app 不在 `/Applications` | 弹窗提示手动安装，打开 DMG |
| 磁盘空间不足 | 下载前检查，不足时弹窗提示 |
| 下载中途关闭设置页 | 后台继续下载，再打开时显示进度 |
| 旧版本运行中 | 脚本 `sleep 1` 等待退出后再替换 |

## 涉及文件

| 文件 | 变更 |
|------|------|
| `Services/UpdateChecker.swift` | 新增下载/安装方法，扩展 UpdateStatus 枚举 |
| `Views/Settings/SettingsView.swift` | 更新按钮 UI，新增进度条和安装确认弹窗 |
| `Resources/install_update.sh`（新增） | 安装脚本 |
| `project.yml` | 确保 install_update.sh 被打包进 bundle |
