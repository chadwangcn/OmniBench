#!/usr/bin/env python3
# 多模态视觉模型UI/交互差异检测
import base64
import json
import requests
import os

class VisionChecker:
    def __init__(self, api_key, model="doubao-embedding-vision", base_url="https://ark.cn-beijing.volces.com/api/v3/chat/completions"):
        self.api_key = api_key
        self.model = model
        self.base_url = base_url

    def encode_image(self, image_path):
        with open(image_path, "rb") as f:
            return base64.b64encode(f.read()).decode('utf-8')

    def compare_images(self, design_path, actual_path, page_name="首页"):
        """用多模态模型对比设计稿和实际截图，输出交互/UI/功能差异"""
        design_b64 = self.encode_image(design_path)
        actual_b64 = self.encode_image(actual_path)

        prompt = f"""你是专业的UI/UX测试工程师，对比Figma设计稿（第一张图）和实际APP运行截图（第二张图），找出高保真层面的差异，包括但不限于：
1. 元素位置/对齐/大小/间距错误
2. 色值/图标/文字内容/字号字体错误
3. 交互逻辑问题：按钮位置不对、可点击区域错误、缺失功能入口
4. 布局错误、层级错误、遮挡问题
5. 明显的功能缺失
忽略抗锯齿、字体渲染微小差异、系统状态栏差异。
输出JSON格式，不要其他内容：
{{
  "page": "{page_name}",
  "score": 0-100的高保真得分,
  "issues": [
    {{
      "type": "color|font|layout|interaction|content|missing_element",
      "severity": "high|medium|low",
      "position": "位置描述（如顶部导航栏、底部Tab、中间内容区）",
      "description": "问题描述",
      "suggestion": "修改建议"
    }}
  ],
  "summary": "整体差异总结"
}}"""

        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{design_b64}"}},
                        {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{actual_b64}"}}
                    ]
                }
            ],
            "temperature": 0.1
        }
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {self.api_key}"
        }
        res = requests.post(self.base_url, headers=headers, json=payload)
        if res.status_code == 200:
            content = res.json()['choices'][0]['message']['content']
            # 提取JSON
            content = content[content.find('{'):content.rfind('}')+1]
            return json.loads(content)
        else:
            return {"error": f"API请求失败: {res.status_code} {res.text}"}

if __name__ == "__main__":
    import sys
    api_key = sys.argv[1]
    design_path = sys.argv[2]
    actual_path = sys.argv[3]
    output_dir = sys.argv[4]
    page_name = sys.argv[5] if len(sys.argv) >5 else "页面"
    checker = VisionChecker(api_key)
    result = checker.compare_images(design_path, actual_path, page_name)
    # 保存结果
    with open(os.path.join(output_dir, f"{page_name}_vision_check.json"), 'w') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    # 生成Markdown报告
    md = f"# {page_name} 多模态高保真检测报告\n"
    md += f"得分：{result.get('score', 0)}分\n\n"
    md += f"## 总结\n{result.get('summary', '')}\n\n"
    md += "## 问题列表\n"
    for idx, issue in enumerate(result.get('issues', []), 1):
        md += f"### 问题{idx} [{issue['severity']}] {issue['type']}\n"
        md += f"- 位置：{issue['position']}\n"
        md += f"- 描述：{issue['description']}\n"
        md += f"- 建议：{issue['suggestion']}\n\n"
    with open(os.path.join(output_dir, f"{page_name}_vision_report.md"), 'w') as f:
        f.write(md)
    print(f"✅ 多模态检测完成，得分：{result.get('score', 0)}，问题数：{len(result.get('issues', []))}")
