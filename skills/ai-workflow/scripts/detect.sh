#!/usr/bin/env bash
# detect.sh <仓库根目录> — 只读侦察：打印初始化/填配置需要的事实，不改任何文件。
# output 里的 hint: 是线索，不是已验证的命令。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }

echo "== git =="
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "commits: $(git rev-list --count HEAD 2>/dev/null || echo 0)"
  echo "dirty-files: $(git status --porcelain | wc -l | tr -d ' ')"
else
  echo "NOT_A_GIT_REPO"
fi

echo "== ai-workflow 状态 =="
if [ -L .ai-workflow ]; then
  echo "BLOCKER: .ai-workflow 是符号链接，install.sh 会拒绝写入"
elif [ -e .ai-workflow ] && [ ! -d .ai-workflow ]; then
  echo "BLOCKER: .ai-workflow 存在但不是目录"
elif [ -d .ai-workflow ]; then
  echo "exists: .ai-workflow/"
  if [ -f .ai-workflow/.initialized ]; then
    echo "state: INITIALIZED ($(head -n 1 .ai-workflow/.initialized))"
  else
    echo "state: EXISTS_WITHOUT_MARKER（install.sh 只补充不冲突的文件）"
  fi
  for p in README.md WORKFLOW.md config.env templates/task.md scripts/ai-workflow.sh; do
    [ -e ".ai-workflow/$p" ] && echo "exists: .ai-workflow/$p"
  done
else
  echo "state: NOT_INITIALIZED"
fi

echo "== 旧版内容（只提示，不迁移）=="
[ -d .ai ] && echo "legacy: .ai/（旧任务池，本技能不读取）"
[ -e scripts/ai-loop.sh ] && echo "legacy: scripts/ai-loop.sh"
[ -d skills/ai-loop-task ] && echo "legacy: skills/ai-loop-task"
grep -q 'ai-loop-init:v1' AGENTS.md 2>/dev/null && echo "legacy: AGENTS.md 含 ai-loop-init:v1 标记（本技能不修改）"
[ -d docs/legacy ] && echo "info: docs/legacy/ 存在（属于项目原有内容，本技能不碰）"

echo "== 项目原有规则（只读，不会被修改）=="
for p in AGENTS.md CLAUDE.md LESSONS.md docs/code-standards.md .cursorrules GEMINI.md .github/copilot-instructions.md; do
  [ -e "$p" ] && echo "exists: $p"
done
find . -maxdepth 4 \( -name node_modules -o -name .git -o -name .ai-workflow -o -name .worktrees -o -name legacy -o -name .venv \) -prune -o \
  -type f -name AGENTS.md ! -path './AGENTS.md' -print 2>/dev/null | sed 's#^\./#nested: #'

echo "== 文档语言 =="
lang=unknown; basis=""
for f in AGENTS.md CLAUDE.md README.md; do
  [ -f "$f" ] || continue
  n="$(perl -CSD -0777 -ne '$c=()=/\p{Han}/g; print $c' "$f" 2>/dev/null || echo 0)"
  basis="$basis $f=${n:-0}字"
  if [ "${n:-0}" -ge 5 ]; then lang=zh; break; else lang=en; fi
done
echo "language: $lang   （依据汉字数：${basis:- 无可读文件}）"

echo "== 基准分支线索（BASE_REF）=="
echo "当前分支：$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 未知)"
for b in main master dev develop trunk; do
  git show-ref --verify --quiet "refs/heads/$b" && echo "hint: 存在分支 ${b}；如果它是开发基准，把 BASE_REF 设为它（不要假设一定是 main）"
done

echo "== 依赖安装线索（WORKTREE_SETUP）=="
[ -f pnpm-lock.yaml ]    && echo "hint: WORKTREE_SETUP='pnpm install --frozen-lockfile'"
[ -f package-lock.json ] && echo "hint: WORKTREE_SETUP='npm ci'"
[ -f yarn.lock ]         && echo "hint: WORKTREE_SETUP='yarn install --frozen-lockfile'"
[ -f uv.lock ]           && echo "hint: WORKTREE_SETUP='uv sync --frozen'"
[ -f poetry.lock ]       && echo "hint: WORKTREE_SETUP='poetry install'"
[ -f go.mod ]            && echo "hint: WORKTREE_SETUP='go mod download'"
[ -f Cargo.lock ]        && echo "hint: WORKTREE_SETUP='cargo fetch'"
[ -f requirements.txt ] && [ ! -f uv.lock ] && echo "hint: python requirements.txt：是否为 worktree 建 venv 需要问人，不要猜"

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
echo "（以上都只是线索：写进 config.env 前请真实跑一次）"
