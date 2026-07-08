#!/bin/bash
# 版本号自动更新脚本
set -e
if [ -z "$1" ]; then
  echo "用法: ./bump-version.sh [major|minor|patch|版本号]"
  echo "示例: ./bump-version.sh patch → 从0.2.0升级到0.2.1"
  exit 1
fi
cd "$(dirname "$0")/.."
CURRENT=$(cat VERSION)
echo "当前版本: $CURRENT"
# 拆分版本号
MAJOR=$(echo $CURRENT | cut -d. -f1)
MINOR=$(echo $CURRENT | cut -d. -f2)
PATCH=$(echo $CURRENT | cut -d. -f3)
case $1 in
  major)
    MAJOR=$((MAJOR+1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR+1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH+1))
    ;;
  *)
    # 自定义版本号
    NEW_VER=$1
    ;;
esac
NEW_VER=${NEW_VER:-"$MAJOR.$MINOR.$PATCH"}
echo "新版本: $NEW_VER"
# 更新VERSION文件
echo $NEW_VER > VERSION
# 更新脚本里的版本号
sed -i '' "s/VERSION=\".*\"/VERSION=\"$NEW_VER\"/g" skills/omnibench/omnibench.sh
# 添加更新日志条目
echo -e "\n## v$NEW_VER ($(date +%Y-%m-%d))" >> CHANGELOG.md
git log --oneline -10 | grep -v "version bump" | sed 's/^/- /' >> CHANGELOG.md
echo "" >> CHANGELOG.md
# 同步到本地Skill
cp skills/omnibench/omnibench.sh ~/.claude/skills/omnibench/
cp VERSION ~/.claude/skills/omnibench/
echo "✅ 版本已更新到v$NEW_VER，CHANGELOG已生成，已同步到本地Skill"
echo "提交并推送到GitHub后用户即可通过omnibench upgrade升级"
