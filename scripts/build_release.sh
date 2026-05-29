#!/bin/bash
set -e

# ============================================================
# 拾屿 Archiver — 一键打包 + 上传 DMG 到 GitHub Release
# 用法: ./scripts/build_release.sh [version]
# 示例: ./scripts/build_release.sh 1.0.4
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# ---------- 版本号 ----------
VERSION="${1:-$(grep -A1 'CFBundleShortVersionString' Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>.*/\1/')}"
ENGLISH_NAME="Archiver"
DMG_NAME="${ENGLISH_NAME}_v${VERSION}.dmg"
APP_DISPLAY_NAME="拾屿"

echo "======================================"
echo "  拾屿 Archiver — Release Builder"
echo "  版本: v${VERSION}"
echo "  DMG: ${DMG_NAME}"
echo "======================================"

# ---------- 1. 确保 XcodeGen 生成项目 ----------
echo ""
echo "[1/6] 生成 Xcode 项目..."
if command -v xcodegen &> /dev/null; then
    xcodegen generate --spec "$PROJECT_DIR/project.yml"
else
    echo "  xcodegen 未安装，跳过（确保 .xcodeproj 已存在）"
fi

# ---------- 2. 构建 Release ----------
echo ""
echo "[2/6] 构建 Release..."
BUILD_DIR="$PROJECT_DIR/build"
rm -rf "$BUILD_DIR"

xcodebuild build \
    -project "$PROJECT_DIR/Archiver.xcodeproj" \
    -scheme Archiver \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -3

APP_PATH="$BUILD_DIR/Build/Products/Release/Archiver.app"
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 构建失败，找不到 App: $APP_PATH"
    exit 1
fi
echo "  ✅ 构建成功: $APP_PATH"

# ---------- 3. 创建 DMG 临时目录 ----------
echo ""
echo "[3/6] 打包 DMG..."
DMG_TEMP="$PROJECT_DIR/build/dmg_temp"
DMG_OUTPUT="$PROJECT_DIR/build/${DMG_NAME}"
rm -rf "$DMG_TEMP" "$DMG_OUTPUT"
mkdir -p "$DMG_TEMP"

# 复制 App
cp -R "$APP_PATH" "$DMG_TEMP/"

# 创建 Applications 快捷方式
ln -s /Applications "$DMG_TEMP/Applications"

# ---------- 4. 生成 DMG ----------
echo ""
echo "[4/6] 生成 DMG 镜像..."
hdiutil create \
    -volname "$APP_DISPLAY_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"

echo "  ✅ DMG 已生成: $DMG_OUTPUT"
ls -lh "$DMG_OUTPUT"

# ---------- 5. 上传到 GitHub Release ----------
echo ""
echo "[5/6] 上传到 GitHub Release v${VERSION}..."

# 检查 tag 是否存在
if ! git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "  创建 tag v${VERSION}..."
    git tag "v${VERSION}"
    git push origin "v${VERSION}"
fi

# 检查 release 是否存在
if gh release view "v${VERSION}" >/dev/null 2>&1; then
    echo "  Release v${VERSION} 已存在，删除旧 DMG asset..."
    EXISTING_ASSETS=$(gh release view "v${VERSION}" --json assets --jq '.assets[].name' 2>/dev/null || true)
    for asset in $EXISTING_ASSETS; do
        if [[ "$asset" == *.dmg ]]; then
            echo "    删除: $asset"
            gh release delete-asset "v${VERSION}" "$asset" --yes
        fi
    done
else
    echo "  创建 Release v${VERSION}..."
    gh release create "v${VERSION}" \
        --title "拾屿 Archiver v${VERSION}" \
        --notes "拾屿 Archiver v${VERSION}" \
        --generate-notes
fi

# 上传 DMG
echo "  上传 ${DMG_NAME}..."
gh release upload "v${VERSION}" "$DMG_OUTPUT" --clobber
echo "  ✅ 上传成功!"

# ---------- 6. 清理 ----------
echo ""
echo "[6/6] 清理临时文件..."
rm -rf "$DMG_TEMP" "$BUILD_DIR"
echo "  ✅ 清理完成"

echo ""
echo "======================================"
echo "  🎉 发布完成!"
echo "  下载: https://github.com/V-Linkin/Archiver/releases/download/v${VERSION}/${DMG_NAME}"
echo "======================================"
