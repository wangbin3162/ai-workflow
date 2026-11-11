#!/usr/bin/env bash
# verify.sh <仓库根目录> — 初始化后的机械检查（只读 + 在临时目录跑脚本回归测试）
# 全部通过退出码 0；有 FAIL 退出码 1。WARN 不影响退出码。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
warn() { printf '  WARN %s\n' "$1"; }
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== 必需文件 =="
for f in AGENTS.md CLAUDE.md LESSONS.md docs/code-standards.md docs/ai-loop-architecture.md .claude/loop.md \
         .ai/templates/task.md .ai/loop.env scripts/ai-loop.sh scripts/test-ai-loop.sh; do
  chk "存在 $f" test -s "$f"
done
for d in inbox doing review done blocked; do chk "存在 .ai/$d/" test -d ".ai/$d"; done
chk "AGENTS.md 含 ai-loop-init 标记" grep -q 'ai-loop-init:v1' AGENTS.md
chk "CLAUDE.md 只转发 @AGENTS.md" test "$(grep -v -E '^[[:space:]]*$|^#' CLAUDE.md)" = "@AGENTS.md"
chk ".gitignore 含运行时产物规则" grep -q '>>> ai-loop-init' .gitignore

echo "== 占位符与引用 =="
left="$(grep -l '{{' AGENTS.md docs/code-standards.md 2>/dev/null | tr '\n' ' ')"
if [ -z "$left" ]; then ok "没有未填的 {{...}} 占位符"; else bad "仍有未填占位符：$left"; fi
if grep -q 'TODO:' AGENTS.md docs/code-standards.md 2>/dev/null; then
  warn "存在 TODO:（合法，但要在汇报里逐条列出）："
  grep -n 'TODO:' AGENTS.md docs/code-standards.md | cut -c1-140 | sed 's/^/         /'
fi
# AGENTS.md 里的相对链接必须能找到目标
broken=""
while IFS= read -r link; do
  p="${link%%#*}"; [ -z "$p" ] && continue
  case "$p" in http*|mailto:*) continue ;; esac
  [ -e "$p" ] || broken="$broken $p"
done < <(grep -o ']([^)]*)' AGENTS.md | sed 's/^](//; s/)$//')
if [ -z "$broken" ]; then ok "AGENTS.md 里的链接都能找到目标"; else bad "AGENTS.md 有失效链接：$broken"; fi
if [ -d docs/legacy ]; then
  for f in docs/legacy/*; do [ -e "$f" ] || continue; grep -q "$f" AGENTS.md && ok "AGENTS.md 引用了 $f" || bad "AGENTS.md 没引用 $f"; done
fi

echo "== 脚本 =="
chk "bash -n ai-loop.sh" bash -n scripts/ai-loop.sh
chk "bash -n test-ai-loop.sh" bash -n scripts/test-ai-loop.sh
chk "ai-loop.sh 可执行" test -x scripts/ai-loop.sh
t_out="$(bash scripts/test-ai-loop.sh 2>&1)"; t_rc=$?
if [ "$t_rc" -eq 0 ]; then ok "回归测试通过（$(printf '%s' "$t_out" | tail -1)）"; else bad "回归测试失败：$(printf '%s' "$t_out" | grep FAIL | head -3 | tr '\n' ';')"; fi
chk "ai-loop.sh check 通过" bash scripts/ai-loop.sh check

echo
echo "通过 $PASS，失败 $FAIL"
[ "$FAIL" -eq 0 ]
