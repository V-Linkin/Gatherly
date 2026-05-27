#!/bin/bash
set -e

echo "=== Archiver 项目设置 ==="
echo ""

cd "$(dirname "$0")/Archiver"

# 检查是否安装了 xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "正在安装 XcodeGen..."
    brew install xcodegen
fi

# 生成 Xcode 项目
echo "正在生成 Xcode 项目..."
xcodegen generate

echo ""
echo "✅ 项目已生成！"
echo ""
echo "请用 Xcode 打开: open Archiver.xcodeproj"
echo ""
echo "首次打开后，Xcode 会自动下载 GRDB 依赖。"
echo "等待依赖下载完成后，按 Cmd+R 运行。"
