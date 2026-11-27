#!/usr/bin/env bash
# install.sh — 在目标项目里初始化 ai-workflow
#
#   install.sh --target <仓库根目录>            # 默认 --plan：只打印计划，不改任何文件
#   install.sh --target <仓库根目录> --apply    # 执行：只写 <目标>/.ai-workflow/
#
# 初始化结果：
#   .ai-workflow/README.md
#   .ai-workflow/TEMPLATE.md
#   .ai-workflow/CONFIG.md       # 基准分支预填当前分支
#   .ai-workflow/guide.html      # 流转图解；已存在则保留
#   .ai-workflow/inbox/GUIDE.md  # 任务池顺序指南；常驻，只重建不删除
#   .ai-workflow/{inbox,doing,review,done,list}/
#
# 原则：
#   - 只写 .ai-workflow/，不碰 AGENTS.md、CLAUDE.md、docs/、根 .gitignore
#   - 不生成 .gitignore / config.env / scripts / docs / templates
#   - README 已存在且带 v3 标记时视为用户文件；TEMPLATE / CONFIG / guide.html 已存在时也保留
#   - 旧版结构（.initialized / v1 / v2）不自动升级，停止并提示人工迁移
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$SKILL_DIR/assets"
TARGET=""; MODE="plan"
MARKER='ai-workflow:v3'

die()  { printf '[install][error] %s\n' "$*" >&2; exit 1; }
say()  { printf '%-9s %s\n' "$1" "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --plan)   MODE="plan"; shift ;;
    --apply)  MODE="apply"; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || die "用法：install.sh --target <目录> [--plan|--apply]"

cd "$TARGET"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "目标不是 git 仓库：先 git init（worktree 依赖 git）"
[ "$(git rev-parse --show-toplevel)" = "$(pwd -P)" ] || die "请指向仓库根目录：$(git rev-parse --show-toplevel)"
git rev-parse HEAD >/dev/null 2>&1 || die "仓库还没有任何提交：先做一次初始提交（git worktree 需要至少一个提交）"

[ -L .ai-workflow ] && die ".ai-workflow 是符号链接，拒绝写入：$(readlink .ai-workflow)"
[ -e .ai-workflow ] && [ ! -d .ai-workflow ] && die ".ai-workflow 已存在且不是目录，拒绝写入"

README=".ai-workflow/README.md"
TEMPLATE=".ai-workflow/TEMPLATE.md"
CONFIG=".ai-workflow/CONFIG.md"
GUIDE=".ai-workflow/guide.html"
INBOX_GUIDE=".ai-workflow/inbox/GUIDE.md"
BUGLIST=".ai-workflow/list/buglist.md"
HISTORY=".ai-workflow/HISTORY.md"
DIRS=(inbox doing review done list)

# 旧版结构：不自动升级
if [ -f .ai-workflow/.initialized ]; then
  die "发现旧版 .ai-workflow 结构（.initialized）。本次不自动升级；请按迁移说明手动整理后重试。"
fi
if [ -f "$README" ] && ! head -n 1 "$README" | grep -q "$MARKER"; then
  if grep -qE 'ai-workflow:v1|ai-workflow:v2' "$README" 2>/dev/null; then
    die "发现旧版 README（v1/v2）。本次不自动升级；请按迁移说明手动整理后重试。"
  fi
  die "已有未标记的 .ai-workflow/README.md，不覆盖。请人工比较后再初始化。"
fi

if [ -d .ai ]; then say WARN "发现旧版 .ai/：本技能不读取、不修改、不自动迁移"; fi
if [ -e scripts/ai-loop.sh ]; then say WARN "发现旧版 scripts/ai-loop.sh：不会被调用"; fi

if [ -f "$README" ]; then
  say SKIP "${README}（已存在 v3 标记，保留用户内容）"
else
  say CREATE "$README"
fi
if [ -f "$TEMPLATE" ]; then
  say SKIP "${TEMPLATE}（已存在，保留用户内容）"
else
  say CREATE "$TEMPLATE"
fi
if [ -f "$CONFIG" ]; then
  say SKIP "${CONFIG}（已存在，保留用户内容）"
else
  say CREATE "${CONFIG}（预填当前分支，测试命令留 TODO）"
fi
if [ -f "$GUIDE" ]; then
  say SKIP "${GUIDE}（已存在，保留用户内容）"
else
  say CREATE "$GUIDE"
fi
if [ -f "$INBOX_GUIDE" ]; then
  say SKIP "${INBOX_GUIDE}（已存在，保留当前任务池顺序）"
else
  say CREATE "$INBOX_GUIDE"
fi
if [ -f "$BUGLIST" ]; then
  say SKIP "${BUGLIST}（已存在，保留用户内容）"
else
  say CREATE "$BUGLIST"
fi
if [ -f "$HISTORY" ]; then
  say SKIP "${HISTORY}（已存在，保留用户内容）"
else
  say CREATE "$HISTORY"
fi
for d in "${DIRS[@]}"; do
  [ -d ".ai-workflow/$d" ] && say SKIP ".ai-workflow/$d/" || say CREATE ".ai-workflow/$d/"
done

# 旧版但非致命的残留，只提示
for p in discussion approved blocked scripts docs templates config.env .gitignore; do
  if [ -e ".ai-workflow/$p" ]; then say WARN ".ai-workflow/$p 是旧版/额外内容；本技能不删除，可人工清理"; fi
done

echo
if [ "$MODE" = "plan" ]; then
  say PLAN "以上为计划，尚未改动任何文件。确认后加 --apply 执行。"
  exit 0
fi

mkdir -p .ai-workflow
for d in "${DIRS[@]}"; do mkdir -p ".ai-workflow/$d"; done
if [ ! -f "$README" ]; then
  cp "$A/README.md" "$README"
fi
if [ ! -f "$TEMPLATE" ]; then
  cp "$A/TEMPLATE.md" "$TEMPLATE"
fi
if [ ! -f "$CONFIG" ]; then
  current_branch="$(git symbolic-ref --short -q HEAD || true)"
  [ -n "$current_branch" ] || current_branch='（detached HEAD，请填基准分支）'
  escaped_branch="$(printf '%s' "$current_branch" | sed 's/[&|\\]/\\&/g')"
  sed "s|{{CURRENT_BRANCH}}|$escaped_branch|g" "$A/CONFIG.md" > "$CONFIG"
fi
if [ ! -f "$GUIDE" ]; then
  cp "$A/guide.html" "$GUIDE"
fi
if [ ! -f "$INBOX_GUIDE" ]; then
  cp "$A/GUIDE.md" "$INBOX_GUIDE"
fi
if [ ! -f "$BUGLIST" ]; then
  cp "$A/buglist.md" "$BUGLIST"
fi
if [ ! -f "$HISTORY" ]; then
  cp "$A/HISTORY.md" "$HISTORY"
fi

say DONE "初始化完成：只写 .ai-workflow/。未执行任何 git add / commit。"
say NEXT "用浏览器打开 .ai-workflow/guide.html 看流转；执行规则以 README.md 为准"
say NEXT "1) 打开 .ai-workflow/CONFIG.md，补测试 / 构建命令与依赖安装"
say NEXT "2) 复制 .ai-workflow/TEMPLATE.md 到 inbox/ 手写任务；列表/方案可放 list/；顺序写入 inbox/GUIDE.md"
say NEXT "3) 在 Claude/T3 会话里用 /ai-workflow 加提示词领取或拆分任务"
