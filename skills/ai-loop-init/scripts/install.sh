#!/usr/bin/env bash
# install.sh — 把 AI 任务池工作流装进一个 git 仓库
#
#   install.sh --target <仓库根目录>            # 默认 --plan：只打印会做什么，不改任何文件
#   install.sh --target <仓库根目录> --apply    # 真正执行
#
# 原则：
#   - 不覆盖项目已有文件。已有的 AGENTS.md / CLAUDE.md / LESSONS.md / docs/code-standards.md / .claude/loop.md
#     会被「原样搬」到 docs/legacy/（已跟踪的用 git mv，保留历史），新文件再引用它们。
#   - 目标文件有未提交改动就停下，不动。
#   - .gitignore 只追加，不改已有行。
#   - 不执行 git add / commit / push。
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
A="$SKILL_DIR/assets"
TARGET=""; MODE="plan"

die()  { printf '[install][error] %s\n' "$*" >&2; exit 1; }
say()  { printf '%-9s %s\n' "$1" "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:-}"; shift 2 ;;
    --plan)   MODE="plan"; shift ;;
    --apply)  MODE="apply"; shift ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || die "用法：install.sh --target <目录> [--plan|--apply]"

cd "$TARGET"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "目标不是 git 仓库：先 git init（worktree 和任务分支都依赖 git）"
[ "$(git rev-parse --show-toplevel)" = "$(pwd -P)" ] || die "请指向仓库根目录：$(git rev-parse --show-toplevel)"
git rev-parse HEAD >/dev/null 2>&1 || die "仓库还没有任何提交：先做一次初始提交（git worktree 需要至少一个提交）"

# 已初始化：AGENTS.md 里有标记 → 什么都不做
if [ -f AGENTS.md ] && grep -q 'ai-loop-init:v1' AGENTS.md; then
  say SKIP "已初始化（AGENTS.md 含 ai-loop-init 标记）。如需升级，对照 skills 里的 assets 手工比对。"
  exit 0
fi
if [ -e .ai ] || [ -e scripts/ai-loop.sh ]; then
  die "发现 .ai/ 或 scripts/ai-loop.sh，但不是本技能生成的（AGENTS.md 无标记）。需要人决定是合并还是换目录，我不动。"
fi

# 会被写入或搬走的文件
MANAGED=(AGENTS.md CLAUDE.md LESSONS.md docs/code-standards.md docs/ai-loop-architecture.md .claude/loop.md)

# 有未提交改动（含未跟踪）的目标文件 → 停下
dirty=""
for f in "${MANAGED[@]}"; do
  if [ -e "$f" ] && [ -n "$(git status --porcelain -- "$f")" ]; then dirty="$dirty $f"; fi
done
[ -z "$dirty" ] || die "这些目标文件有未提交改动或未被 git 跟踪，先提交或处理再来：$dirty"

run() { [ "$MODE" = "apply" ] && "$@" || true; }

LEGACY_LIST=()   # 元素：新位置|原路径

legacy_dest() { # $1 原路径 -> docs/legacy/<文件名>，冲突加序号
  local base d n=1; base="$(basename "$1")"; d="docs/legacy/$base"
  while [ -e "$d" ]; do d="docs/legacy/${base%.md}.$n.md"; n=$((n+1)); done
  printf '%s\n' "$d"
}

only_imports_agents() { # CLAUDE.md 只是 @AGENTS.md 的转发
  [ -z "$(grep -v -E '^[[:space:]]*$|^#' "$1" | grep -v -x '@AGENTS.md' || true)" ]
}

extract_existing() { # $1 路径
  local f="$1" dest
  [ -s "$f" ] || { [ -e "$f" ] && { say REPLACE "$f（空文件）"; run rm -f "$f"; }; return 0; }
  if [ "$f" = "CLAUDE.md" ] && only_imports_agents "$f"; then
    say REPLACE "$f（只是 @AGENTS.md 转发，无需保留）"; run rm -f "$f"; return 0
  fi
  dest="$(legacy_dest "$f")"
  say MOVE "$f -> $dest（原样搬出，内容不改）"
  run mkdir -p docs/legacy
  if git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then run git mv "$f" "$dest"; else run mv "$f" "$dest"; fi
  LEGACY_LIST+=("$dest|$f")
}

for f in "${MANAGED[@]}"; do [ -e "$f" ] && extract_existing "$f"; done

# 其他不动的原有规则文件，只做引用
OTHER_REFS=()
while IFS= read -r p; do OTHER_REFS+=("$p"); done < <(
  find . -maxdepth 4 \( -name node_modules -o -name .git -o -name .worktrees -o -name legacy -o -name .venv \) -prune -o \
    -type f -name AGENTS.md ! -path './AGENTS.md' -print 2>/dev/null | sed 's#^\./##' | sort
)
EXTRA_DOCS=()
for p in .cursorrules .github/copilot-instructions.md GEMINI.md; do [ -f "$p" ] && EXTRA_DOCS+=("$p"); done
for p in ${OTHER_REFS[@]+"${OTHER_REFS[@]}"} ${EXTRA_DOCS[@]+"${EXTRA_DOCS[@]}"}; do
  say REFERENCE "$p（不改动，只在 AGENTS.md 里引用）"
done

# 被搬走的文件里用 @路径 导入的文件：原位置不动，但搬走后相对导入会失效，所以要在 AGENTS.md 里直接引用
IMPORT_REFS=()
for e in ${LEGACY_LIST[@]+"${LEGACY_LIST[@]}"}; do
  src="${e%%|*}"; [ -f "$src" ] || src="${e##*|}"      # plan 模式下文件还没搬
  while IFS= read -r imp; do
    imp="${imp#@}"
    [ "$imp" = "AGENTS.md" ] && continue
    [ -f "$imp" ] || continue
    IMPORT_REFS+=("$imp|${e##*|}")
    say REFERENCE "$imp（原 ${e##*|} 用 @ 导入；原位置不动，只在 AGENTS.md 里直接引用）"
  done < <(grep -E '^@[^[:space:]]+' "$src" 2>/dev/null | awk '{print $1}')
done

# 生成「项目原有规则」块
refs_file="$(mktemp)"; trap 'rm -f "$refs_file"' EXIT
{
  echo "## 项目原有规则"
  echo
  if [ ${#LEGACY_LIST[@]} -eq 0 ] && [ ${#OTHER_REFS[@]} -eq 0 ] && [ ${#EXTRA_DOCS[@]} -eq 0 ] && [ ${#IMPORT_REFS[@]} -eq 0 ]; then
    echo "（初始化时项目没有已有的 agent 规则文件。）"
  else
    echo "项目自己的构建、约定、架构以下面这些文件为准；**任务池流程与护栏以本文件为准**，两者冲突时先停下来问人。"
    echo
    echo "| 文件 | 来源 | 什么时候读 |"
    echo "| --- | --- | --- |"
    for e in ${LEGACY_LIST[@]+"${LEGACY_LIST[@]}"}; do
      echo "| [\`${e%%|*}\`](${e%%|*}) | 初始化时从原 \`${e##*|}\` 原样搬出 | **改代码之前先读** |"
    done
    for e in ${IMPORT_REFS[@]+"${IMPORT_REFS[@]}"}; do
      echo "| [\`${e%%|*}\`](${e%%|*}) | 原 \`${e##*|}\` 用 @ 导入的文件（原位置未动） | **改代码之前先读** |"
    done
    for p in ${OTHER_REFS[@]+"${OTHER_REFS[@]}"}; do
      echo "| [\`$p\`]($p) | 子目录原有规则（未改动） | 改 \`$(dirname "$p")/\` 之前 |"
    done
    for p in ${EXTRA_DOCS[@]+"${EXTRA_DOCS[@]}"}; do
      echo "| [\`$p\`]($p) | 其他工具的规则（未改动） | 用到对应工具时 |"
    done
  fi
} > "$refs_file"

put() { # $1 模板（assets 下）, $2 目标路径
  say CREATE "$2"
  if [ "$MODE" = "apply" ]; then mkdir -p "$(dirname "$2")"; cp "$A/$1" "$2"; fi
}

say CREATE "AGENTS.md（含上面的「项目原有规则」引用）"
if [ "$MODE" = "apply" ]; then
  awk -v f="$refs_file" '/<!-- LEGACY-REFS -->/{while((getline l < f)>0) print l; next} {print}' "$A/AGENTS.md.template" > AGENTS.md
fi
put CLAUDE.md.template CLAUDE.md
put LESSONS.md.template LESSONS.md
put code-standards.md.template docs/code-standards.md
put ai-loop-architecture.md docs/ai-loop-architecture.md
put loop.md.template .claude/loop.md
put task.md .ai/templates/task.md
put loop.env.template .ai/loop.env
put ai-loop.sh scripts/ai-loop.sh
put test-ai-loop.sh scripts/test-ai-loop.sh
run chmod +x scripts/ai-loop.sh scripts/test-ai-loop.sh

for d in inbox doing review done blocked; do
  say CREATE ".ai/$d/.gitkeep"
  if [ "$MODE" = "apply" ]; then mkdir -p ".ai/$d"; : > ".ai/$d/.gitkeep"; fi
done

if [ -f .gitignore ] && grep -q '>>> ai-loop-init' .gitignore; then
  say SKIP ".gitignore 已含 ai-loop-init 块"
else
  say APPEND ".gitignore（只追加运行时产物忽略规则）"
  if [ "$MODE" = "apply" ]; then
    [ -f .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore
    { [ -s .gitignore ] && echo; cat "$A/gitignore.block"; } >> .gitignore
  fi
fi

echo
if [ "$MODE" = "plan" ]; then
  say PLAN "以上为计划，尚未改动任何文件。确认后加 --apply 执行。"
else
  say DONE "已写入。下一步：填模板里的 {{...}} 占位符，然后运行 verify.sh。未执行任何 git add / commit。"
  grep -l '{{' AGENTS.md docs/code-standards.md 2>/dev/null | sed 's/^/待填写: /' || true
fi
