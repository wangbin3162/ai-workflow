#!/usr/bin/env bash
# verify.sh <仓库根目录> — 初始化后的机械检查（只读 + 在临时 fixture 跑脚本回归测试）
# 全部通过退出码 0；有 FAIL 退出码 1。WARN 不影响退出码。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
warn() { printf '  WARN %s\n' "$1"; }
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== 必需文件（全部在 .ai-workflow/ 内）=="
for f in .ai-workflow/README.md .ai-workflow/WORKFLOW.md .ai-workflow/config.env \
         .ai-workflow/docs/QUICKSTART.md .ai-workflow/docs/REFERENCE.md \
         .ai-workflow/docs/TROUBLESHOOTING.md .ai-workflow/docs/MIGRATION.md \
         .ai-workflow/templates/task.md .ai-workflow/scripts/ai-workflow.sh \
         .ai-workflow/scripts/test-ai-workflow.sh .ai-workflow/.initialized; do
  chk "存在 $f" test -s "$f"
done
for d in inbox discussion doing review approved done blocked docs; do
  chk "存在 .ai-workflow/$d/" test -d ".ai-workflow/$d"
done
broken=""
for doc in .ai-workflow/README.md .ai-workflow/WORKFLOW.md .ai-workflow/docs/*.md; do
  [ -f "$doc" ] || continue
  base="$(dirname "$doc")"
  while IFS= read -r link; do
    p="${link%%#*}"; [ -z "$p" ] && continue
    case "$p" in http*|mailto:*) continue ;; esac
    [ -e "$base/$p" ] || broken="$broken $doc->$p"
  done < <(grep -o ']([^)]*)' "$doc" | sed 's/^](//; s/)$//')
done
if [ -z "$broken" ]; then ok "说明文档内部链接都能找到"; else bad "说明文档有失效链接：$broken"; fi
chk "初始化标记为 ai-workflow:v1" grep -qx 'ai-workflow:v1' .ai-workflow/.initialized
chk "运行时目录在 .ai-workflow/.gitignore 中" grep -q '^worktrees/' .ai-workflow/.gitignore
chk "任务模板说明 needs-discussion" grep -q 'needs-discussion' .ai-workflow/templates/task.md
chk "WORKFLOW 说明审查通过不等于合并" grep -q '审查通过.*不等于.*合并' .ai-workflow/WORKFLOW.md

echo "== 脚本 =="
chk "bash -n ai-workflow.sh" bash -n .ai-workflow/scripts/ai-workflow.sh
chk "bash -n test-ai-workflow.sh" bash -n .ai-workflow/scripts/test-ai-workflow.sh
chk "ai-workflow.sh 可执行" test -x .ai-workflow/scripts/ai-workflow.sh
t_out="$(bash .ai-workflow/scripts/test-ai-workflow.sh 2>&1)"; t_rc=$?
if [ "$t_rc" -eq 0 ]; then
  ok "回归测试通过（$(printf '%s' "$t_out" | tail -1)）"
else
  bad "回归测试失败：$(printf '%s' "$t_out" | grep FAIL | head -3 | tr '\n' ';')"
fi
chk "ai-workflow.sh check 通过" bash .ai-workflow/scripts/ai-workflow.sh check

echo "== 配置与未验证项 =="
if grep -q '^: "${BASE_REF:=}"' .ai-workflow/config.env; then
  warn "BASE_REF 为空：领取时使用主 checkout 当前 HEAD。以 dev 为基准的项目请显式填写。"
fi
if grep -q '^: "${PROJECT_TOOLS:=}"' .ai-workflow/config.env; then
  warn "PROJECT_TOOLS 为空：run 模式下 agent 跑不了项目测试。"
fi
if grep -q '^: "${WORKTREE_SETUP:=}"' .ai-workflow/config.env; then
  warn "WORKTREE_SETUP 为空：如果项目有第三方依赖，worktree 里可能跑不了检查。"
fi

echo
echo "通过 ${PASS}，失败 $FAIL"
[ "$FAIL" -eq 0 ]
