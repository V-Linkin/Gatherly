#!/bin/bash
set -e

DMG_PATH="$1"
APP_NAME="Archiver"
INSTALL_DIR="/Applications"

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG path not provided or file not found"
    exit 1
fi

# 挂载 DMG
echo "Mounting DMG..."
MOUNT_OUTPUT=$(hdiutil attach -nobrowse -quiet "$DMG_PATH" 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | head -1 | awk '{print $NF}')

if [ -z "$MOUNT_POINT" ]; then
    echo "ERROR: Failed to mount DMG"
    exit 1
fi

echo "DMG mounted at: $MOUNT_POINT"

# 在挂载卷中查找 .app
APP_PATH=$(find "$MOUNT_POINT" -name "${APP_NAME}.app" -maxdepth 1 | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: ${APP_NAME}.app not found in DMG"
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null
    exit 1
fi

echo "Found app at: $APP_PATH"

# 等待旧 app 退出
echo "Waiting for old app to quit..."
sleep 2

# 替换旧版本
echo "Installing to ${INSTALL_DIR}..."
ditto --norsrc "$APP_PATH" "${INSTALL_DIR}/${APP_NAME}.app"

# 卸载 DMG
echo "Unmounting DMG..."
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null

# 删除临时 DMG
rm -f "$DMG_PATH"

# 启动新版本
echo "Launching new version..."
open "${INSTALL_DIR}/${APP_NAME}.app"

echo "Done!"
