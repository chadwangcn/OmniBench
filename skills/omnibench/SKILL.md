---
name: omnibench
description: OmniBench 通用测试原子工具集，为AI Agent提供设备控制、音视频采集、UI对比、环境部署等基础操作能力，无内置模型/推理逻辑，所有测试决策、用例设计、结果分析由Agent完成
metadata:
  type: test-toolkits
  core-philosophy: atomic, stateless, agent-driven
---
# OmniBench 测试工具集
## 定位
纯原子操作工具集，作为Agent执行测试的"手脚"：
- 不内置任何推理、判断、用例生成逻辑
- 所有测试方案设计、结果分析、决策完全由调用的Agent完成
- 只负责执行具体操作，返回原始结果给Agent处理
- 无厂商/设备/语言绑定，可扩展支持任意硬件/软件测试场景
---
## 提供的原子操作能力（Agent可直接调用）
### 环境工具
- `env:check`：自动检测并安装所有依赖（adb/ffmpeg/sox/opencv等）
- `build:remote`：对接CI服务，触发远程编译，下载构建产物（APK/固件）
- `device:list`：列出已连接的Android设备，返回设备状态（电量/温度/存储/序列号）
### 应用控制（Android）
- `app:install <apk路径>`：安装/覆盖安装APK到指定设备
- `app:launch <包名>` / `app:stop <包名>` / `app:clear <包名>`：启动/停止应用/清空数据
- `input:tap <x> <y>` / `input:swipe <x1> <y1> <x2> <y2> <ms>` / `input:key <keycode>` / `input:text <文本>`：模拟UI操作
- `ui:traverse`：遍历所有可点击元素，返回元素坐标列表
- `log:collect [--duration 秒] [--filter 关键词]`：抓取logcat日志，过滤错误/ANR
- `perf:collect <包名> [--duration 秒]`：采集CPU/内存/帧率/功耗数据
### 采集工具
- `screen:capture [保存路径]`：设备截图导出到本地
- `screen:record [--duration 秒] [保存路径]`：设备录屏导出到本地
- `audio:play <音频路径>`：Mac端播放音频（模拟人声/测试音）
- `audio:record [--duration 秒] [保存路径]`：Mac麦克风录制音频
- `video:play <视频路径>`：Mac端播放视频
- `camera:capture [保存路径]`：Mac摄像头拍摄画面
### 素材工具
- `figma:export <figma链接> [保存路径]`：导出Figma指定节点PNG/原始结构JSON
- `image:diff <图片1> <图片2>`：对比两张图片像素差异，返回相似度、差异图路径、差异坐标
### 归档工具
- `result:save <文件路径> [归档目录]`：保存测试产物到Obsidian测试目录
---
## 使用方式
Agent根据测试目标自行组合调用原子能力即可，不需要遵循固定流程，例如语音唤醒测试：
1. 调用`audio:play 唤醒词.mp3`播放唤醒词
2. 调用`sleep 2`等待响应
3. 调用`audio:record --duration 5 response.wav`录制设备响应
4. 调用`screen:capture 唤醒后界面.png`截图
5. 调用`log:collect --duration 3`抓取日志
6. 调用`result:save *`归档所有结果
所有操作执行结果（原始数据/文件路径/错误信息）直接返回给Agent，由Agent做正确性判断、报告生成。
