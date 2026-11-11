#!/usr/bin/env bash
# detect.sh <仓库根目录> — 只读侦察：打印填模板需要的事实和建议，不改任何文件。
# 输出里的 hint: 行是「线索」，不是已验证的命令——写进文档前要自己跑一次。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }

echo "== git =="
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "commits: $(git rev-list --count HEAD 2>/dev/null || echo 0)"
  echo "dirty-files: $(git status --porcelain | wc -l | tr -d ' ')"
  blockers=""
  for f in AGENTS.md CLAUDE.md LESSONS.md docs/code-standards.md docs/ai-loop-architecture.md .claude/loop.md; do
    [ -e "$f" ] && [ -n "$(git status --porcelain -- "$f")" ] && blockers="$blockers $f"
  done
  [ -n "$blockers" ] && echo "BLOCKER: 这些文件有未提交改动或未被跟踪，install.sh 会拒绝继续：$blockers"
else
  echo "NOT_A_GIT_REPO"
fi

echo "== 已有 agent 规则文件 =="
for p in AGENTS.md CLAUDE.md LESSONS.md GEMINI.md .cursorrules .github/copilot-instructions.md docs/code-standards.md docs/ai-loop-architecture.md .claude/loop.md .ai scripts/ai-loop.sh; do
  [ -e "$p" ] && echo "exists: $p ($( [ -f "$p" ] && wc -l < "$p" | tr -d ' ' || echo dir ) 行)"
done
find . -maxdepth 4 \( -name node_modules -o -name .git -o -name .worktrees -o -name legacy -o -name .venv \) -prune -o \
  -type f -name AGENTS.md ! -path './AGENTS.md' -print 2>/dev/null | sed 's#^\./#nested: #'
grep -q 'ai-loop-init:v1' AGENTS.md 2>/dev/null && echo "state: ALREADY_INITIALIZED"

echo "== 文档语言 =="
lang=unknown; basis=""
# 依据：已有的 agent 规则文件优先，其次 README；任何一份含 5 个以上汉字就判中文（短文件字少，阈值要低）
for f in AGENTS.md CLAUDE.md LESSONS.md README.md; do
  [ -f "$f" ] || continue
  n="$(perl -CSD -0777 -ne '$c=()=/\p{Han}/g; print $c' "$f" 2>/dev/null || echo 0)"
  basis="$basis $f=${n:-0}字"
  if [ "${n:-0}" -ge 5 ]; then lang=zh; break; else lang=en; fi
done
echo "language: $lang   （依据汉字数：${basis:- 无可读文件}；zh = 模板原样用中文；en = 把模板整体翻成英文；依据很弱时问用户）"

echo "== 依赖安装线索（WORKTREE_SETUP）=="
[ -f pnpm-lock.yaml ]    && echo "hint: WORKTREE_SETUP='pnpm install --frozen-lockfile'"
[ -f package-lock.json ] && echo "hint: WORKTREE_SETUP='npm ci'"
[ -f yarn.lock ]         && echo "hint: WORKTREE_SETUP='yarn install --frozen-lockfile'"
[ -f uv.lock ]           && echo "hint: WORKTREE_SETUP='uv sync --frozen'"
[ -f poetry.lock ]       && echo "hint: WORKTREE_SETUP='poetry install'"
[ -f go.mod ]            && echo "hint: WORKTREE_SETUP='go mod download'"
[ -f Cargo.lock ]        && echo "hint: WORKTREE_SETUP='cargo fetch'"
[ -f requirements.txt ] && [ ! -f uv.lock ] && echo "hint: python 项目用 requirements.txt：是否要为 worktree 建 venv 需要问人，不要猜"

echo "== 测试 / 构建线索（PROJECT_TOOLS）=="
if [ -f Makefile ]; then
  for t in test check lint build; do grep -qE "^$t:" Makefile && echo "hint: Makefile 有目标 $t → Bash(make $t)"; done
fi
if [ -f package.json ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -r '.scripts // {} | keys[]' package.json 2>/dev/null | grep -E '^(test|lint|build|check|typecheck)' | sed 's/^/hint: package.json scripts: /'
  else
    grep -E '"(test|lint|build|check|typecheck)[^"]*"[[:space:]]*:' package.json | sed 's/^/hint: package.json: /'
  fi
  [ -f pnpm-lock.yaml ] && echo "hint: 包管理器是 pnpm → 命令形如 Bash(pnpm test)"
fi
{ [ -f pytest.ini ] || [ -f tox.ini ] || grep -qs 'pytest' pyproject.toml; } && echo "hint: 有 pytest 配置 → Bash(pytest *)"
[ -f go.mod ]     && echo "hint: Go → Bash(go test *)"
[ -f Cargo.toml ] && echo "hint: Rust → Bash(cargo test *)"
ls .github/workflows/*.yml >/dev/null 2>&1 && echo "hint: CI 工作流里的命令是最可信的线索：.github/workflows/"
echo "（以上都只是线索：写进文档前请真实跑一次；跑不了的写 TODO: 并说明缺什么）"
