#!/usr/bin/env python3
# UI高保真检测工具 - 输出结构化问题清单+修改建议
import cv2
import numpy as np
import pytesseract
import json
import os
pytesseract.pytesseract.tesseract_cmd = '/opt/homebrew/bin/tesseract'

class UIChecker:
    def __init__(self, design_path, actual_path, output_dir):
        self.design = cv2.imread(design_path)
        self.actual = cv2.imread(actual_path)
        self.output_dir = output_dir
        self.issues = []
        # 等比例对齐设计稿到实际截图尺寸
        self._align_images()

    def _align_images(self):
        h_d, w_d = self.design.shape[:2]
        h_a, w_a = self.actual.shape[:2]
        scale = min(w_a/w_d, h_a/h_d)
        new_w, new_h = int(w_d*scale), int(h_d*scale)
        design_scaled = cv2.resize(self.design, (new_w, new_h))
        self.aligned_design = np.zeros_like(self.actual)
        self.x_off = (w_a - new_w)//2
        self.y_off = (h_a - new_h)//2
        self.aligned_design[self.y_off:self.y_off+new_h, self.x_off:self.x_off+new_w] = design_scaled
        self.scale = scale

    def check_color(self, threshold=40):
        """检测色值差异"""
        diff = cv2.absdiff(self.actual, self.aligned_design)
        gray = cv2.cvtColor(diff, cv2.COLOR_BGR2GRAY)
        _, thresh = cv2.threshold(gray, threshold, 255, cv2.THRESH_BINARY)
        contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for c in contours:
            area = cv2.contourArea(c)
            if area > 20:
                x,y,w,h = cv2.boundingRect(c)
                # 取中心像素色值
                cx, cy = x+w//2, y+h//2
                b_d, g_d, r_d = [int(v) for v in self.aligned_design[cy, cx]]
                b_a, g_a, r_a = [int(v) for v in self.actual[cy, cx]]
                self.issues.append({
                    "type": "color",
                    "action": "update_color",
                    "element_type": "view",
                    "position": {"x": int(x/self.scale), "y": int(y/self.scale)},
                    "size": {"width": int(w/self.scale), "height": int(h/self.scale)},
                    "target": {"rgb": [r_d, g_d, b_d]},
                    "actual": {"rgb": [r_a, g_a, b_a]},
                    "delta": {"rgb": [r_d-r_a, g_d-g_a, b_d-b_a]},
                    "suggestion": f"修改位置({int(x/self.scale)},{int(y/self.scale)})区域背景色为#{r_d:02x}{g_d:02x}{b_d:02x}",
                    "code_hint": f"view.setBackgroundColor(Color.rgb({r_d}, {g_d}, {b_d}))"
                })

    def check_text(self):
        """检测文字/字号/字体问题"""
        # OCR识别实际文字
        data = pytesseract.image_to_data(self.actual, output_type=pytesseract.Output.DICT, lang='chi_sim+eng')
        for i in range(len(data['text'])):
            text = data['text'][i].strip()
            if not text or len(text) < 2:
                continue
            x,y,w,h = data['left'][i], data['top'][i], data['width'][i], data['height'][i]
            conf = int(data['conf'][i])
            # 对应设计稿区域
            dx, dy = int((x - self.x_off)/self.scale), int((y - self.y_off)/self.scale)
            dw, dh = int(w/self.scale), int(h/self.scale)
            # 字号偏差超过2px标记问题
            design_h = int(dh * self.scale)
            if abs(h - design_h) > 2*self.scale:
                target_size = int(dh)
                actual_size = int(h/self.scale)
                self.issues.append({
                    "type": "font_size",
                    "action": "update_text_size",
                    "element_type": "text",
                    "position": {"x": int(x/self.scale), "y": int(y/self.scale)},
                    "text": text,
                    "target": {"text_size_sp": target_size},
                    "actual": {"text_size_sp": actual_size},
                    "delta": {"text_size_sp": target_size - actual_size},
                    "suggestion": f"文字「{text}」字号从{actual_size}sp调整为{target_size}sp",
                    "code_hint": f"textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, {target_size}f)"
                })
            # 识别模糊标记字体问题
            if conf < 60:
                self.issues.append({
                    "type": "font_family",
                    "action": "update_font",
                    "element_type": "text",
                    "position": {"x": int(x/self.scale), "y": int(y/self.scale)},
                    "text": text,
                    "suggestion": f"文字「{text}」字体显示异常，替换为设计稿指定字体",
                    "code_hint": "textView.setTypeface(Typeface.create(\"design_font\", Typeface.NORMAL))"
                })

    def check_alignment(self, threshold=3):
        """检测元素对齐问题"""
        # 边缘检测找水平线/垂直线
        edges_actual = cv2.Canny(self.actual, 50, 150)
        edges_design = cv2.Canny(self.aligned_design, 50, 150)
        lines_a = cv2.HoughLinesP(edges_actual, 1, np.pi/180, threshold=30, minLineLength=15, maxLineGap=3)
        lines_d = cv2.HoughLinesP(edges_design, 1, np.pi/180, threshold=30, minLineLength=15, maxLineGap=3)
        if lines_a is None or lines_d is None:
            return
        # 水平线对齐检测（兼容OpenCV不同版本返回格式）
        def get_y_lines(lines, scaled=False):
            ys = []
            for l in lines:
                l = l[0] if isinstance(l[0], np.ndarray) else l
                y = l[1]
                if scaled:
                    y = int((y - self.y_off)/self.scale)
                ys.append(int(y))
            return sorted(set(ys))
        y_actual = get_y_lines(lines_a, scaled=True)
        y_design = get_y_lines(lines_d, scaled=True)
        for ya in y_actual:
            closest_yd = min(y_design, key=lambda yd: abs(ya-yd)) if y_design else ya
            if abs(ya - closest_yd) > threshold:
                self.issues.append({
                    "type": "alignment",
                    "action": "adjust_position",
                    "element_type": "horizontal_line",
                    "position": {"y": ya},
                    "target": {"y": closest_yd},
                    "delta": {"y": closest_yd - ya},
                    "suggestion": f"将Y轴{ya}px位置的水平元素向上/下移动{closest_yd-ya}px，对齐到基准线",
                    "code_hint": f"view.setY({closest_yd}px)"
                })

    def run_checks(self):
        self.check_color()
        self.check_text()
        self.check_alignment()
        # 保存标记图
        marked = self.actual.copy()
        for issue in self.issues:
            x = int(issue['position'].get('x', 0)*self.scale + self.x_off)
            y = int(issue['position'].get('y', 0)*self.scale + self.y_off)
            color = (0,0,255) if issue['type'] in ['color', 'font'] else (0,255,255)
            cv2.rectangle(marked, (x-5,y-5), (x+50,y+20), color, 2)
            cv2.putText(marked, issue['type'], (x,y-10), cv2.FONT_HERSHEY_SIMPLEX, 0.4, color, 1)
        cv2.imwrite(os.path.join(self.output_dir, "marked_issues.png"), marked)
        # 保存结构化报告
        report = {
            "summary": {
                "total_issues": len(self.issues),
                "color_issues": len([i for i in self.issues if i['type']=='color']),
                "font_issues": len([i for i in self.issues if i['type'] in ['font', 'font_size']]),
                "alignment_issues": len([i for i in self.issues if i['type']=='alignment'])
            },
            "issues": self.issues
        }
        with open(os.path.join(self.output_dir, "ui_issues.json"), 'w') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        # 生成Markdown报告
        md = f"# UI高保真检测报告\n共发现{len(self.issues)}个问题：\n- 色值问题：{report['summary']['color_issues']}个\n- 字体/字号问题：{report['summary']['font_issues']}个\n- 对齐问题：{report['summary']['alignment_issues']}个\n\n## 问题详情\n"
        for idx, issue in enumerate(self.issues, 1):
            md += f"### 问题{idx}：{issue['type']}\n"
            md += f"- 位置：{issue['position']}\n"
            if 'text' in issue:
                md += f"- 关联文字：{issue['text']}\n"
            md += f"- 修改建议：{issue['suggestion']}\n\n"
        with open(os.path.join(self.output_dir, "ui_issues_report.md"), 'w') as f:
            f.write(md)
        return report

if __name__ == "__main__":
    import sys
    design, actual, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(out_dir, exist_ok=True)
    checker = UIChecker(design, actual, out_dir)
    report = checker.run_checks()
    print(f"✅ 检测完成，共{report['summary']['total_issues']}个问题")
    print(f"报告已保存到{out_dir}/ui_issues_report.md")
