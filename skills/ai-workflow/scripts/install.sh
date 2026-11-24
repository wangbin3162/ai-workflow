#!/usr/bin/env bash
# install.sh — 在目标项目里初始化 ai-workflow
#
#   install.sh --target <仓库根目录>            # 默认 --plan：只打印计划，不改任何文件
#   install.sh --target <仓库根目录> --apply    # 执行：只写 <目标>/.ai-workflow/
#
# 原则：
#   - 所有新增内容都在 .ai-workflow/ 内；不碰 AGENTS.md、CLAUDE.md、docs/、根 .gitignore
#   - 幂等：已存在且内容相同的文件跳过；内容不同则列为冲突并停止，不覆盖
#   - 不执行 git add / commit / push；不迁移旧版 .ai/ 任务
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$SKILL_DIR/assets"
TARGET=""; MODE="plan"; VERSION_MARK="ai-workflow:v1"

die()  { printf '[install][error] %s\n' "$*" >&2; exit 1; }
say()  { printf '%-9s %s\n' "$1" "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --plan)   MODE="plan"; shift ;;
    --apply)  MODE="apply"; shift ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || die "用法：install.sh --target <目录> [--plan|--apply]"

cd "$TARGET"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "目标不是 git 仓库：先 git init（worktree 与任务分支依赖 git）"
[ "$(git rev-parse --show-toplevel)" = "$(pwd -P)" ] || die "请指向仓库根目录：$(git rev-parse --show-toplevel)"
git rev-parse HEAD >/dev/null 2>&1 || die "仓库还没有任何提交：先做一次初始提交（git worktree 需要至少一个提交）"

[ -L .ai-workflow ] && die ".ai-workflow 是符号链接，拒绝写入：$(readlink .ai-workflow)"
[ -e .ai-workflow ] && [ ! -d .ai-workflow ] && die ".ai-workflow 已存在且不是目录，拒绝写入"

# 旧版内容只提示，不读取、不修改、不迁移
[ -d .ai ] && say WARN "发现旧版 .ai/：本技能不读取、不修改、不自动迁移。迁移见源包 docs/MIGRATION.md"
[ -e scripts/ai-loop.sh ] && say WARN "发现旧版 scripts/ai-loop.sh：不会被调用。确认不再使用后由你处理"
if [ -f AGENTS.md ] && grep -q 'ai-loop-init:v1' AGENTS.md; then
  say WARN "AGENTS.md 含旧版 ai-loop-init 标记：本技能不改它；旧流程与新流程不要同时派工"
fi

# 资产 | 目标（相对 .ai-workflow/） | 是否可执行
MANIFEST=(
  "README.md|README.md|"
  "WORKFLOW.md|WORKFLOW.md|"
  "docs/QUICKSTART.md|docs/QUICKSTART.md|"
  "docs/REFERENCE.md|docs/REFERENCE.md|"
  "docs/TROUBLESHOOTING.md|docs/TROUBLESHOOTING.md|"
  "docs/MIGRATION.md|docs/MIGRATION.md|"
  "config.env|config.env|"
  "gitignore|.gitignore|"
  "task.md|templates/task.md|"
  "example-task.md|inbox/EXAMPLE-T-20260101-001.md|"
  "ai-workflow.sh|scripts/ai-workflow.sh|x"
  "test-ai-workflow.sh|scripts/test-ai-workflow.sh|x"
)
DIRS=(inbox discussion doing review approved done blocked templates scripts docs)
MARKER=".ai-workflow/.initialized"

conflict=0
if [ -f "$MARKER" ] && [ "$(head -n 1 "$MARKER")" != "$VERSION_MARK" ]; then
  say CONFLICT "${MARKER}（版本 $(head -n 1 "$MARKER" 2>/dev/null || echo 空)，期望 ${VERSION_MARK}；不自动升级）"
  conflict=1
fi

for item in "${MANIFEST[@]}"; do
  IFS='|' read -r src dst exec_bit <<< "$item"
  [ -f "$A/$src" ] || die "技能资产缺失：$A/$src"
  dest=".ai-workflow/$dst"
  if [ -e "$dest" ]; then
    if cmp -s "$A/$src" "$dest"; then
      say SKIP "${dest}（内容相同）"
    else
      say CONFLICT "${dest}（已存在且内容不同；不覆盖，不自动合并）"
      conflict=1
    fi
  else
    say CREATE "$dest"
  fi
done

for d in "${DIRS[@]}"; do
  [ -d ".ai-workflow/$d" ] || say CREATE ".ai-workflow/$d/"
done
[ -f "$MARKER" ] || say CREATE "$MARKER"

if [ "$conflict" = "1" ]; then
  echo
  say STOP "发现冲突：本次不写入任何文件。请人工比较上面列出的文件，决定保留哪一版后再执行。"
  exit 1
fi

echo
if [ "$MODE" = "plan" ]; then
  say PLAN "以上为计划，尚未改动任何文件。确认后加 --apply 执行。"
  exit 0
fi

for d in "${DIRS[@]}"; do mkdir -p ".ai-workflow/$d"; done
for item in "${MANIFEST[@]}"; do
  IFS='|' read -r src dst exec_bit <<< "$item"
  dest=".ai-workflow/$dst"
  if [ ! -e "$dest" ]; then
    mkdir -p "$(dirname "$dest")"
    cp "$A/$src" "$dest"
    [ "$exec_bit" = "x" ] && chmod +x "$dest"
  fi
done
[ -f "$MARKER" ] || printf '%s\n' "$VERSION_MARK" > "$MARKER"

# 空目录也要能进版本库（是否提交由用户决定）
for d in inbox discussion doing review approved done blocked; do
  [ -e ".ai-workflow/$d/.gitkeep" ] || : > ".ai-workflow/$d/.gitkeep"
done

say DONE "初始化完成：所有内容都在 .ai-workflow/。未执行任何 git add / commit。"
say NEXT "1) 先读使用说明：.ai-workflow/docs/QUICKSTART.md（索引：.ai-workflow/README.md）"
say NEXT "2) 按项目填 .ai-workflow/config.env（BASE_REF / PROJECT_TOOLS / WORKTREE_SETUP）"
say NEXT "3) 复制 .ai-workflow/templates/task.md 到 .ai-workflow/inbox/ 手写任务"
say NEXT "4) 运行 .ai-workflow/scripts/ai-workflow.sh check"
