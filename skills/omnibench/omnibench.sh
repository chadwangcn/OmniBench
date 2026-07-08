#!/bin/bash
# OmniBench 全栈自动化测试工具核心脚本 v0.1.0
set -e
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 配置项支持环境变量覆盖
RESULT_DIR_DEFAULT="$HOME/Documents/HydraMind-Obsidian/02 执行项目/自有AI产品线/K1/测试结果/$(date +%Y-%m-%d)"
RESULT_DIR="${OMNIBENCH_RESULT_DIR:-$RESULT_DIR_DEFAULT}"
mkdir -p "$RESULT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="${OMNIBENCH_PACKAGE_NAME:-com.lumi.k1}"
ARCH=$(uname -m)
OS=$(uname -s)

# 自动检测并安装依赖，内置常用二进制
install_dep() {
  DEP_NAME=$1
  BIN_PATH="$SKILL_DIR/bin/$OS/$ARCH/$DEP_NAME"
  # 优先使用内置二进制，其次系统安装
  if [ -f "$BIN_PATH" ] && [ -x "$BIN_PATH" ]; then
    export PATH="$SKILL_DIR/bin/$OS/$ARCH:$PATH"
    return
  fi
  # 缺失依赖自动安装
  if ! command -v $DEP_NAME &> /dev/null; then
    echo "📦 缺失依赖 $DEP_NAME，正在自动安装..."
    if command -v brew &> /dev/null; then
      brew install $2
    elif command -v apt &> /dev/null; then
      sudo apt update && sudo apt install -y $2
    elif command -v yum &> /dev/null; then
      sudo yum install -y $2
    else
      echo "❌ 请先安装 $DEP_NAME 后再运行"
      exit 1
    fi
  fi
}

load_config() {
  # 加载配置文件
  CONFIG_PATH="$SKILL_DIR/config.json"
  if [ -f "$CONFIG_PATH" ]; then
    echo "⚙️  加载配置文件: $CONFIG_PATH"
    FIGMA_TOKEN=$(jq -r '.api_keys.figma // empty' "$CONFIG_PATH")
    CI_URL=$(jq -r '.ci.build_url // empty' "$CONFIG_PATH")
    CI_TOKEN=$(jq -r '.ci.token // empty' "$CONFIG_PATH")
    OBSIDIAN_DIR=$(jq -r '.obsidian_result_dir // empty' "$CONFIG_PATH" | sed "s|~|$HOME|g")
    PKG_NAME=$(jq -r '.default_package_name // empty' "$CONFIG_PATH")
    [ -n "$OBSIDIAN_DIR" ] && RESULT_DIR="$OBSIDIAN_DIR/$(date +%Y-%m-%d)" && mkdir -p "$RESULT_DIR"
    [ -n "$PKG_NAME" ] && PACKAGE_NAME="$PKG_NAME"
  else
    echo "⚠️  未找到配置文件，请复制config.example.json为config.json填写必要密钥（Figma/API Key等）"
  fi
}

check_env() {
  echo "🔍 OmniBench v0.1.0 环境检测中..."
  # 创建内置二进制目录
  mkdir -p "$SKILL_DIR/bin/$OS/$ARCH"
  load_config
  # 依赖检查
  install_dep curl curl
  install_dep jq jq
  install_dep adb android-platform-tools
  install_dep ffmpeg ffmpeg
  install_dep sox sox
  install_dep python3 python3
  # Python依赖检查
  python3 -c "import PIL, cv2, numpy" 2>/dev/null || pip3 install pillow opencv-python numpy -q
  echo "✅ 环境检测完成，所有依赖已就绪"
}

# 获取连接设备
get_device() {
  DEVICES=$(adb devices | grep -w "device" | awk '{print $1}')
  DEVICE_COUNT=$(echo "$DEVICES" | grep -c "" | xargs)
  if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo "❌ 未检测到USB连接的Android设备，请开启USB调试后重试"
    exit 1
  elif [ "$DEVICE_COUNT" -gt 1 ]; then
    echo "⚠️  检测到多台设备，请选择："
    echo "$DEVICES" | nl
    read -p "输入设备序号: " DEV_IDX
    DEVICE=$(echo "$DEVICES" | sed -n "${DEV_IDX}p")
  else
    DEVICE=$DEVICES
  fi
  echo "✅ 使用设备: $DEVICE"
  export ANDROID_SERIAL=$DEVICE
}

# 初始化
init() {
  check_env
  get_device
  echo "📂 测试结果保存目录: $RESULT_DIR"
}

# 1. 安装APP
install_apk() {
  APK_PATH=$1
  OVERWRITE=$2
  echo "📦 安装APK: $APK_PATH"
  if [ "$OVERWRITE" = "-r" ]; then
    adb install -r "$APK_PATH"
  else
    adb install "$APK_PATH"
  fi
  echo "✅ APK安装完成"
}

# 2. 收集日志
collect_log() {
  DURATION=${1:-60}
  PKG=$2
  FILTER=$3
  LOG_FILE="$RESULT_DIR/log_${TIMESTAMP}.txt"
  echo "📝 开始收集${DURATION}秒日志..."
  adb logcat -c # 清空历史日志
  sleep "$DURATION"
  if [ -n "$PKG" ]; then
    adb logcat -d | grep -E "$PKG|ANR|AndroidRuntime|FATAL|EXCEPTION|$FILTER" > "$LOG_FILE"
  else
    adb logcat -d | grep -E "ANR|AndroidRuntime|FATAL|EXCEPTION|$FILTER" > "$LOG_FILE"
  fi
  echo "✅ 日志已保存到: $LOG_FILE"
  # 提取崩溃信息
  CRASH_COUNT=$(grep -c "FATAL EXCEPTION\|ANR in" "$LOG_FILE" || true)
  echo "⚠️  检测到 $CRASH_COUNT 个崩溃/ANR问题"
}

# 3. 截图
screenshot() {
  NAME=${1:-"screenshot_$TIMESTAMP.png"}
  DEVICE_PATH="/sdcard/$NAME"
  LOCAL_PATH="$RESULT_DIR/$NAME"
  adb shell screencap -p "$DEVICE_PATH"
  adb pull "$DEVICE_PATH" "$LOCAL_PATH"
  adb shell rm "$DEVICE_PATH"
  echo "✅ 截图已保存: $LOCAL_PATH"
}

# 4. 录屏
record_screen() {
  DURATION=${1:-30}
  NAME=${2:-"record_$TIMESTAMP.mp4"}
  DEVICE_PATH="/sdcard/$NAME"
  LOCAL_PATH="$RESULT_DIR/$NAME"
  echo "🎥 开始录屏${DURATION}秒..."
  adb shell screenrecord --time-limit "$DURATION" "$DEVICE_PATH"
  sleep $((DURATION + 2))
  adb pull "$DEVICE_PATH" "$LOCAL_PATH"
  adb shell rm "$DEVICE_PATH"
  echo "✅ 录屏已保存: $LOCAL_PATH"
}

# 5. 模拟点击/滑动
input_tap() {
  adb shell input tap "$1" "$2"
  sleep 1
  echo "✅ 点击坐标: ($1, $2)"
}
input_swipe() {
  adb shell input swipe "$1" "$2" "$3" "$4" "$5"
  sleep 1
  echo "✅ 滑动: ($1,$2) → ($3,$4) 时长${5}ms"
}
input_keyevent() {
  adb shell input keyevent "$1"
  echo "✅ 按键事件: $1"
}
input_text() {
  adb shell input text "$1"
  echo "✅ 输入文本: $1"
}

# 6. 启动/停止APP
launch_app() {
  PKG=$1
  adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
  sleep 3
  echo "✅ 应用已启动: $PKG"
}
stop_app() {
  PKG=$1
  adb shell am force-stop "$PKG"
  echo "✅ 应用已停止: $PKG"
}

# 7. 全页面遍历冒烟测试
traverse_pages() {
  PKG=$1
  MAX_DEPTH=${2:-5}
  TRAVERSE_LOG="$RESULT_DIR/traverse_${TIMESTAMP}.log"
  echo "🔍 开始遍历$PKG 所有页面，最大深度$MAX_DEPTH"
  echo "遍历记录保存到: $TRAVERSE_LOG"

  # 启动应用
  launch_app "$PKG"
  screenshot "traverse_home.png"
  echo "首页截图已保存" >> "$TRAVERSE_LOG"

  # 简单遍历逻辑：随机点击可点击元素，返回，循环
  DEPTH=0
  CRASH_COUNT=0
  while [ $DEPTH -lt $MAX_DEPTH ]; do
    # 尝试点击屏幕中心区域的不同位置
    for X in 200 500 800; do
      for Y in 800 1200 1600; do
        input_tap $X $Y
        sleep 2
        # 检查是否崩溃
        CURRENT_CRASH=$(adb logcat -d | grep -c "FATAL EXCEPTION" || true)
        if [ "$CURRENT_CRASH" -gt "$CRASH_COUNT" ]; then
          CRASH_COUNT=$CURRENT_CRASH
          screenshot "crash_page_${DEPTH}_${X}_${Y}.png"
          echo "❌ 检测到崩溃，页面($X,$Y)截图已保存" | tee -a "$TRAVERSE_LOG"
          stop_app "$PKG"
          launch_app "$PKG"
        fi
        # 返回上一页
        input_keyevent 4
        sleep 1
      done
    done
    # 滑动页面
    input_swipe 500 1500 500 500 500
    DEPTH=$((DEPTH + 1))
    echo "✅ 遍历深度: $DEPTH/$MAX_DEPTH"
  done
  echo "🎉 遍历完成，共发现$CRASH_COUNT个崩溃问题，结果保存在$RESULT_DIR"
}

# 8. Monkey随机测试
monkey_test() {
  PKG=$1
  DURATION_MIN=${2:-10}
  MONKEY_LOG="$RESULT_DIR/monkey_${TIMESTAMP}.log"
  EVENTS=$((DURATION_MIN * 100))
  echo "🐒 开始$DURATION_MIN分钟Monkey测试，共$EVENTS个随机事件"
  adb shell monkey -p "$PKG" --throttle 300 --pct-touch 70 --pct-motion 20 --pct-trackball 5 --pct-nav 5 --ignore-crashes --ignore-timeouts -v "$EVENTS" > "$MONKEY_LOG" 2>&1
  CRASH_COUNT=$(grep -c "CRASH\|ANR" "$MONKEY_LOG" || true)
  echo "✅ Monkey测试完成，检测到$CRASH_COUNT个崩溃/ANR，日志保存在$MONKEY_LOG"
}

# 8. 设计稿差异对比
# 11. 读取Figma设计稿自动生成测试用例
generate_test_cases() {
  FIGMA_URL=$1
  OUTPUT_FILE=$2
  TEST_CASE_DIR="$RESULT_DIR/test_cases_${TIMESTAMP}"
  mkdir -p "$TEST_CASE_DIR"
  OUTPUT_PATH="${OUTPUT_FILE:-$TEST_CASE_DIR/test_cases.md}"

  if [ -z "$FIGMA_TOKEN" ]; then
    echo "❌ 未配置Figma Token，请在config.json中填写"
    exit 1
  fi

  echo "🔍 解析Figma设计稿..."
  FILE_KEY=$(echo "$FIGMA_URL" | grep -o "design/[^/]*" | cut -d'/' -f2)
  NODE_ID=$(echo "$FIGMA_URL" | grep -o "node-id=[^&]*" | cut -d'=' -f2 | sed 's/-/:/')

  if [ -z "$FILE_KEY" ]; then
    echo "❌ Figma链接格式错误"
    exit 1
  fi

  # 拉取Figma节点结构
  FIGMA_DATA=$(curl -s -H "X-Figma-Token: $FIGMA_TOKEN" "https://api.figma.com/v1/files/$FILE_KEY/nodes?ids=$NODE_ID")
  PAGE_NAME=$(echo "$FIGMA_DATA" | jq -r '.nodes[].document.name')
  echo "📄 设计页面: $PAGE_NAME"

  # 自动分析生成测试用例（交给AI处理结构，这里导出结构数据）
  echo "$FIGMA_DATA" > "$TEST_CASE_DIR/figma_data.json"
  cat > "$OUTPUT_PATH" <<EOF
# $PAGE_NAME UI测试用例（自动生成）
生成时间: $(date "+%Y-%m-%d %H:%M:%S")
Figma链接: $FIGMA_URL

## 测试范围
- UI还原度校验
- 交互点击测试
- 页面跳转校验
- 边界场景测试

## 测试用例
| 用例ID | 测试步骤 | 预期结果 | 优先级 |
|--------|----------|----------|--------|
EOF

  # 提取所有可点击元素（按钮/输入框/链接）
  echo "$FIGMA_DATA" | jq -r '.. | select(.type? == "FRAME" or .type? == "COMPONENT" or .type? == "INSTANCE" or .type? == "BUTTON") | .name' | grep -i "按钮\|button\|输入\|input\|跳转\|link\|tab" | nl -ba | while read idx element; do
    echo "| TC-$idx | 点击「$element」控件 | 响应符合设计预期，无崩溃无卡顿 | P0 |" >> "$OUTPUT_PATH"
  done

  # 通用UI校验用例
  cat >> "$OUTPUT_PATH" <<EOF
| TC-001 | 页面加载后检查所有元素显示 | 所有元素位置/颜色/大小和设计稿一致，无错位/缺失 | P0 |
| TC-002 | 滑动页面查看滚动效果 | 滚动流畅无卡顿，元素位置正确 | P1 |
| TC-003 | 横竖屏切换（如果支持） | 布局自适应，无元素溢出 | P2 |
| TC-004 | 反复进出页面10次 | 无内存泄漏/崩溃/白屏 | P1 |
EOF

  echo "✅ 测试用例已生成: $OUTPUT_PATH"
  echo "🤖 可以将生成的用例交给AI执行自动化测试"
}

# 8. 设计稿差异对比
design_diff() {
  PKG=$1
  FIGMA_URL=$2
  PAGE_NAME=$3
  DIFF_DIR="$RESULT_DIR/design_diff_${TIMESTAMP}"
  mkdir -p "$DIFF_DIR"
  SCREENSHOT_PATH="$DIFF_DIR/actual_${PAGE_NAME}.png"
  DESIGN_PATH="$DIFF_DIR/design_${PAGE_NAME}.png"
  DIFF_PATH="$DIFF_DIR/diff_${PAGE_NAME}.png"
  REPORT_PATH="$DIFF_DIR/report.md"

  # 检查Figma Token配置
  if [ -z "$FIGMA_TOKEN" ]; then
    echo "❌ 未配置Figma Personal Access Token，请在config.json中填写figma_personal_token字段"
    echo "🔍 获取方式：Figma → 头像 → Settings → Personal access tokens → Generate new token"
    exit 1
  fi

  echo "🎨 开始设计稿差异对比: $PAGE_NAME"
  # 截图当前页面
  DEVICE_PATH="/sdcard/diff_screenshot.png"
  adb shell screencap -p "$DEVICE_PATH"
  adb pull "$DEVICE_PATH" "$SCREENSHOT_PATH"
  adb shell rm "$DEVICE_PATH"
  echo "✅ 实际页面截图已保存"

  # 自动拉取Figma设计稿
  if [ -n "$FIGMA_URL" ]; then
    echo "🔍 正在从Figma拉取设计稿: $FIGMA_URL"
    # 解析Figma链接提取file key和node id
    FILE_KEY=$(echo "$FIGMA_URL" | grep -o "design/[^/]*" | cut -d'/' -f2)
    NODE_ID=$(echo "$FIGMA_URL" | grep -o "node-id=[^&]*" | cut -d'=' -f2 | sed 's/-/:/')
    if [ -n "$FILE_KEY" ] && [ -n "$NODE_ID" ]; then
      # 调用Figma API导出节点图片
      echo "🔑 解析到File Key: $FILE_KEY, Node ID: $NODE_ID"
      IMAGE_URL=$(curl -s -H "X-Figma-Token: $FIGMA_TOKEN" \
        "https://api.figma.com/v1/images/$FILE_KEY?ids=$NODE_ID&format=png&scale=2" | jq -r '.images[]')
      if [ "$IMAGE_URL" != "null" ] && [ -n "$IMAGE_URL" ]; then
        curl -s -o "$DESIGN_PATH" "$IMAGE_URL"
        echo "✅ 设计稿已自动导出"
      else
        echo "⚠️  Figma导出失败，请检查Token权限和节点ID，手动将设计稿保存到$DESIGN_PATH"
      fi
    else
      echo "⚠️  Figma链接解析失败，请手动将设计稿保存到$DESIGN_PATH"
    fi
  else
    echo "⚠️  未提供Figma链接，请手动将设计稿保存到$DESIGN_PATH"
  fi

  # 像素对比生成差异图（需要Pillow，自动安装）
  if command -v python3 &> /dev/null && python3 -c "import PIL" &>/dev/null; then
    python3 -c "
from PIL import Image, ImageChops, ImageDraw
import os
actual = Image.open('$SCREENSHOT_PATH').convert('RGB')
design = Image.open('$DESIGN_PATH').convert('RGB').resize(actual.size)
diff = ImageChops.difference(actual, design)
# 标记差异点为红色
diff_rgba = diff.convert('RGBA')
pixels = diff_rgba.load()
width, height = diff.size
diff_count = 0
for x in range(width):
    for y in range(height):
        r, g, b, a = pixels[x, y]
        if abs(r-g) > 30 or abs(r-b) >30 or abs(g-b) >30:
            pixels[x, y] = (255, 0, 0, 255)
            diff_count +=1
        else:
            pixels[x, y] = (0,0,0,0)
# 合成差异图
result = actual.copy()
result.paste(diff_rgba, mask=diff_rgba)
result.save('$DIFF_PATH')
similarity = max(0, 100 - (diff_count/(width*height))*100*5)
open('$REPORT_PATH', 'w').write(f'''# UI还原度测试报告 - {PAGE_NAME}
测试时间: $(date "+%Y-%m-%d %H:%M:%S")
应用包名: $PKG
## 测试结果
- ✅ UI还原度得分: {similarity:.1f}分
- ❌ 差异像素点: {diff_count}个
- 实际页面截图: ![实际页面](actual_${PAGE_NAME}.png)
- 设计稿: ![设计稿](design_${PAGE_NAME}.png)
- 差异标注图（红色为差异点）: ![差异标注](diff_${PAGE_NAME}.png)
''')
print(f'✅ 对比完成，还原度得分: {similarity:.1f}分，报告已生成')
"
  else
    pip3 install pillow -q
    echo "⚠️  请重新运行命令对比生成报告"
  fi
}

# 9. 稳定性测试
stability_test() {
  PKG=$1
  DURATION_MIN=$2
  TEST_DIR="$RESULT_DIR/stability_${TIMESTAMP}"
  mkdir -p "$TEST_DIR"
  REPORT_PATH="$TEST_DIR/report.md"
  LOG_PATH="$TEST_DIR/stability.log"
  echo "🛡️ 开始$DURATION_MIN分钟稳定性测试: $PKG"
  echo "测试数据保存到: $TEST_DIR"

  # 清空日志
  adb logcat -c
  # 启动应用
  launch_app "$PKG"
  START_CRASH=$(adb logcat -d | grep -c "FATAL EXCEPTION\|ANR in" || echo 0)
  # 采集初始性能数据
  START_MEM=$(adb shell dumpsys meminfo "$PKG" | grep "TOTAL PSS" | awk '{print $3}')
  echo "初始内存占用: ${START_MEM}KB"

  # 后台采集性能数据
  (
    for i in $(seq 1 $((DURATION_MIN*6))); do
      adb shell dumpsys meminfo "$PKG" | grep "TOTAL PSS" | awk '{print strftime("%H:%M:%S"), $3"KB"}' >> "$TEST_DIR/mem.log"
      adb shell dumpsys cpuinfo | grep "$PKG" | awk '{print strftime("%H:%M:%S"), $1"%"}' >> "$TEST_DIR/cpu.log"
      adb shell dumpsys gfxinfo "$PKG" | grep "Janky frames" | awk '{print strftime("%H:%M:%S"), $3"卡顿帧"}' >> "$TEST_DIR/fps.log"
      sleep 10
    done
  ) &
  PERF_PID=$!

  # 混合测试：遍历+随机事件
  END=$((SECONDS + DURATION_MIN*60))
  while [ $SECONDS -lt $END ]; do
    # 随机点击
    input_tap $((RANDOM % 900 + 100)) $((RANDOM % 1400 + 400))
    sleep 1
    # 随机滑动
    if [ $((RANDOM % 3)) -eq 0 ]; then
      input_swipe 500 $((RANDOM % 1000 + 500)) 500 $((RANDOM % 1000 + 500)) 300
      sleep 1
    fi
    # 随机返回
    if [ $((RANDOM % 10)) -eq 0 ]; then
      input_keyevent 4
      sleep 1
      launch_app "$PKG"
    fi
  done

  # 停止性能采集
  kill $PERF_PID 2>/dev/null
  # 统计结果
  END_CRASH=$(adb logcat -d | grep -c "FATAL EXCEPTION\|ANR in" || echo 0)
  CRASH_COUNT=$((END_CRASH - START_CRASH))
  END_MEM=$(adb shell dumpsys meminfo "$PKG" | grep "TOTAL PSS" | awk '{print $3}')
  MEM_GROWTH=$((END_MEM - START_MEM))
  AVG_CPU=$(awk '{sum += $2; n++} END {if(n>0) print sum/n "%"; else print "0%"}' "$TEST_DIR/cpu.log" | tr -d '%')
  JANK_COUNT=$(awk '{sum += $3} END {print sum+0}' "$TEST_DIR/fps.log")
  adb logcat -d | grep -E "FATAL EXCEPTION|ANR" > "$TEST_DIR/crash.log"

  # 生成报告
  cat > "$REPORT_PATH" <<EOF
# 稳定性测试报告 - $PKG
测试时间: $(date "+%Y-%m-%d %H:%M:%S")
测试时长: $DURATION_MIN 分钟
## 测试结果
| 指标 | 数值 | 状态 |
|------|------|------|
| 崩溃/ANR次数 | $CRASH_COUNT | $([ $CRASH_COUNT -eq 0 ] && echo "✅ 通过" || echo "❌ 存在异常") |
| 内存增量 | $((MEM_GROWTH/1024))MB | $([ $MEM_GROWTH -lt 102400 ] && echo "✅ 正常" || echo "⚠️ 存在内存泄漏") |
| 平均CPU占用 | ${AVG_CPU}% | $([ $(echo "$AVG_CPU < 50" | bc) -eq 1 ] && echo "✅ 正常" || echo "⚠️ CPU占用过高") |
| 卡顿帧数 | $JANK_COUNT | $([ $JANK_COUNT -lt 10 ] && echo "✅ 流畅" || echo "⚠️ 存在卡顿") |
## 附件
- 崩溃日志: [crash.log](crash.log)
- 内存数据: [mem.log](mem.log)
- CPU数据: [cpu.log](cpu.log)
- 帧率数据: [fps.log](fps.log)
EOF
  echo "🎉 稳定性测试完成，报告已保存: $REPORT_PATH"
  cat "$REPORT_PATH"
}

# 命令分发
case $1 in
  install)
    init
    install_apk "$2" "$3"
    ;;
  log)
    init
    shift
    DURATION=60
    PKG=""
    FILTER=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --duration) DURATION=$2; shift 2;;
        --package) PKG=$2; shift 2;;
        --filter) FILTER=$2; shift 2;;
        *) shift;;
      esac
    done
    collect_log "$DURATION" "$PKG" "$FILTER"
    ;;
  screenshot)
    init
    screenshot "$2"
    ;;
  record)
    init
    shift
    DURATION=30
    NAME=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --duration) DURATION=$2; shift 2;;
        *) NAME=$1; shift;;
      esac
    done
    record_screen "$DURATION" "$NAME"
    ;;
  tap)
    init
    input_tap "$2" "$3"
    ;;
  swipe)
    init
    input_swipe "$2" "$3" "$4" "$5" "$6"
    ;;
  keyevent)
    init
    input_keyevent "$2"
    ;;
  text)
    init
    input_text "$2"
    ;;
  launch)
    init
    launch_app "$2"
    ;;
  stop)
    init
    stop_app "$2"
    ;;
  traverse)
    init
    shift
    PKG=$PACKAGE_NAME
    DEPTH=5
    while [[ $# -gt 0 ]]; do
      case $1 in
        --package) PKG=$2; shift 2;;
        --max-depth) DEPTH=$2; shift 2;;
        *) shift;;
      esac
    done
    traverse_pages "$PKG" "$DEPTH"
    ;;
  monkey)
    init
    shift
    PKG=$PACKAGE_NAME
    DURATION=10
    while [[ $# -gt 0 ]]; do
      case $1 in
        --package) PKG=$2; shift 2;;
        --duration) DURATION=$2; shift 2;;
        *) shift;;
      esac
    done
    monkey_test "$PKG" "$DURATION"
    ;;
  design-diff)
    init
    shift
    PKG=$PACKAGE_NAME
    FIGMA_URL=""
    PAGE_NAME="page_$TIMESTAMP"
    while [[ $# -gt 0 ]]; do
      case $1 in
        --package) PKG=$2; shift 2;;
        --figma) FIGMA_URL=$2; shift 2;;
        --name) PAGE_NAME=$2; shift 2;;
        *) shift;;
      esac
    done
    design_diff "$PKG" "$FIGMA_URL" "$PAGE_NAME"
    ;;
  gen-testcases)
    init
    shift
    FIGMA_URL=""
    OUTPUT=""
    while [[ $# -gt 0 ]]; do
      case $1 in
        --figma) FIGMA_URL=$2; shift 2;;
        --output) OUTPUT=$2; shift 2;;
        *) shift;;
      esac
    done
    if [ -z "$FIGMA_URL" ]; then
      echo "❌ 请提供Figma链接，示例：omnibench gen-testcases --figma <Figma链接>"
      exit 1
    fi
    generate_test_cases "$FIGMA_URL" "$OUTPUT"
    ;;
  stability)
    init
    shift
    PKG=$PACKAGE_NAME
    DURATION=30
    while [[ $# -gt 0 ]]; do
      case $1 in
        --package) PKG=$2; shift 2;;
        --duration) DURATION=$2; shift 2;;
        *) shift;;
      esac
    done
    stability_test "$PKG" "$DURATION"
    ;;
  shell)
    init
    shift
    adb shell "$@"
    ;;
  *)
    echo "ADB自动化测试工具（含UI还原/稳定性测试）"
    echo "可用命令: install|log|screenshot|record|tap|swipe|keyevent|text|launch|stop|traverse|monkey|design-diff|stability|shell"
    echo "示例："
    echo "  adb-mobile-test design-diff --name 首页 --figma https://www.figma.com/xxx → 对比首页和设计稿差异"
    echo "  adb-mobile-test stability --duration 60 → 60分钟稳定性测试"
    ;;
esac
