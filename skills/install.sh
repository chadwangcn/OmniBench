#!/bin/bash
# OmniBench Skill一键安装脚本
SKILL_DIR=~/.claude/skills/omnibench
mkdir -p $SKILL_DIR
cp -r ./* $SKILL_DIR/
chmod +x $SKILL_DIR/omnibench.sh
echo "✅ OmniBench Skill安装完成，重启Claude Code即可使用"
