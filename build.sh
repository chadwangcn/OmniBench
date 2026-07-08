#!/bin/bash
# OmniBench 一键打包脚本，生成可分发的ZIP包
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
OUT_DIR="./dist"
BUILD_DIR="$OUT_DIR/OmniBench-v$VERSION"
rm -rf "$BUILD_DIR" "$OUT_DIR"/OmniBench*.zip
mkdir -p "$BUILD_DIR" "$BUILD_DIR/bin/Darwin/arm64" "$BUILD_DIR/bin/Darwin/x86_64"

# 复制核心文件
cp -r skills/omnibench/* "$BUILD_DIR/"
cp README.md LICENSE CHANGELOG.md VERSION "$BUILD_DIR/" 2>/dev/null || true
# 确保只包含示例配置，不包含用户本地真实配置
if [ -f "$BUILD_DIR/config.json" ] && grep -q "figd_" "$BUILD_DIR/config.json" && ! grep -q "xxx" "$BUILD_DIR/config.json"; then
  cp skills/omnibench/config.example.json "$BUILD_DIR/config.json"
fi

# 下载预置常用二进制（Mac arm64版本）
echo "📦 下载预置二进制工具..."
cd "$BUILD_DIR/bin/Darwin/arm64"
# ADB
curl -L -o platform-tools.zip "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -q platform-tools.zip && cp platform-tools/adb . && rm -rf platform-tools platform-tools.zip
# ffmpeg (静态编译版本)
curl -L -o ffmpeg.7z "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/7z"
7z x ffmpeg.7z -y && rm ffmpeg.7z
# sox
brew download sox 2>/dev/null || echo "sox will be auto-installed on first run"
chmod +x * 2>/dev/null || true
cd ../../..

# 创建快速安装脚本
cat > "$BUILD_DIR/install.sh" << 'EOF'
#!/bin/bash
echo "🚀 正在安装 OmniBench..."
mkdir -p ~/.claude/skills/omnibench
cp -r ./* ~/.claude/skills/omnibench/
chmod +x ~/.claude/skills/omnibench/omnibench.sh
echo "✅ OmniBench 安装完成！重启Claude Code即可通过Skill调用"
echo "📝 使用示例："
echo "  '帮我安装K1测试包，跑10分钟UI遍历测试'"
EOF
chmod +x "$BUILD_DIR/install.sh"

# 创建使用说明
cat > "$BUILD_DIR/使用说明.md" << 'EOF'
# OmniBench 使用说明
## 快速开始
1. 双击运行 install.sh 完成安装
2. 重启Claude Code/支持MCP的AI客户端
3. 用自然语言描述测试需求即可自动执行
## 环境要求
- MacOS 12+ (Intel/Apple Silicon均支持)
- Homebrew（首次运行会自动安装缺失依赖）
## 能力支持
- APP安装/启动/卸载
- 日志收集/崩溃分析
- UI自动化遍历/点击/滑动
- 截图/录屏
- Figma UI还原度对比
- 稳定性/压力测试
- 语音/视频跨端测试
- 远程编译构建
## 结果保存
所有测试报告/截图/日志自动保存到Obsidian K1项目测试目录，支持语义检索。
EOF

# 打包ZIP
cd "$OUT_DIR"
zip -rq "OmniBench-v$VERSION-macOS.zip" "OmniBench-v$VERSION"
echo -e "\n🎉 打包完成！分发包路径: $OUT_DIR/OmniBench-v$VERSION-macOS.zip"
echo "其他同学下载解压后双击install.sh即可一键安装使用，无需配置环境。"
