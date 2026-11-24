#!/usr/bin/env bash
# scripts/test-ai-loop.sh — ai-loop.sh 的回归测试
# 用临时 git 仓库 + 假 claude，不碰真实 .ai/、不调用真实 claude、不联网。
# 用法：bash scripts/test-ai-loop.sh      （全部通过退出码 0）
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/ai-loop.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; N=0; R=""

ok() { # $1 描述, 其余：条件命令
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  ok   %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$desc"; fi
}

# 假 claude：按 STUB_MODE 决定行为，最终汇报末行带 AI_LOOP_RESULT
cat > "$TMP/claude-stub" <<'EOF'
#!/usr/bin/env bash
case "${STUB_MODE:-nochange}" in
  commit)   echo x >> stub.txt; git add stub.txt; git commit -qm "stub: change"; res='report\nAI_LOOP_RESULT: done' ;;
  blocked)  res='need info\nAI_LOOP_RESULT: blocked' ;;
  nochange) res='nothing\nAI_LOOP_RESULT: done' ;;
esac
printf '{"result":"%s"}\n' "$res"
EOF
chmod +x "$TMP/claude-stub"

new_repo() {
  N=$((N+1)); R="$TMP/repo$N"
  mkdir -p "$R/scripts" "$R/.ai/inbox"
  cp "$SRC" "$R/scripts/ai-loop.sh"
  git -C "$R" init -q
  git -C "$R" config user.name t; git -C "$R" config user.email t@t
  printf '.ai-locks/\n.ai-logs/\n.worktrees/\n*.tmp.*\n' > "$R/.gitignore"
  echo hi > "$R/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm init
}

# $1 id, $2 risk, $3 priority, $4 max_attempts —— 故意带行内注释（模板就是这样写的）
mk_task() {
  cat > "$R/.ai/inbox/$1.md" <<EOF
---
id: $1                 # 唯一
status: new            # new → claimed
priority: ${3:-P1}
created: 2026-11-10
attempts: 0
max_attempts: ${4:-2}  # 上限
risk: $2               # low | high
---

## 验收标准
- x
EOF
}

run_loop() { # $1 STUB_MODE, 其余：传给 ai-loop.sh 的参数
  local mode="$1"; shift
  (cd "$R" && STUB_MODE="$mode" CLAUDE_BIN="$TMP/claude-stub" bash scripts/ai-loop.sh "$@") >"$TMP/out.log" 2>&1
}

fm() { grep -m1 "^$2:" "$1" | sed "s/^$2: *//; s/ *#.*//"; }

echo "A. low 任务 + 有 commit -> review/（模板式行内注释不影响解析）"
new_repo; mk_task T1 low
run_loop commit
ok "任务进入 review/"            test -f "$R/.ai/review/T1.md"
ok "status 为 needs_review"      test "$(fm "$R/.ai/review/T1.md" status)" = needs_review
ok "ai/T1 分支有 1 个 commit"     test "$(git -C "$R" rev-list --count HEAD..ai/T1)" = 1
ok "agent 汇报写进任务文件"        grep -q 'AI_LOOP_RESULT: done' "$R/.ai/review/T1.md"
ok "worktree 保留供人审"           test -d "$R/.worktrees/T1"
run_loop nochange done T1
ok "done 子命令：review/ -> done/" test -f "$R/.ai/done/T1.md"
ok "check 通过"                   run_loop nochange check

echo "B. risk: high（带行内注释）+ agent 改了代码 -> 判失败，不进 review/"
new_repo; mk_task T2 high
run_loop commit
ok "退回 inbox 重试"              test -f "$R/.ai/inbox/T2.md"
ok "attempts = 1"                test "$(fm "$R/.ai/inbox/T2.md" attempts)" = 1
ok "没有进 review/"               test ! -e "$R/.ai/review/T2.md"

echo "C. risk 写错 / 缺失 -> 按 high 处理"
new_repo; mk_task T3 lwo
run_loop commit
ok "risk 写错也按 high：失败退回"   test "$(fm "$R/.ai/inbox/T3.md" attempts)" = 1

echo "D. risk: high + 无改动 -> review/"
new_repo; mk_task T4 high
run_loop nochange
ok "进入 review/"                test -f "$R/.ai/review/T4.md"

echo "E. agent 自报 blocked -> blocked/，不消耗 attempts"
new_repo; mk_task T5 low
run_loop blocked
ok "进入 blocked/"               test -f "$R/.ai/blocked/T5.md"
ok "attempts 仍为 0"              test "$(fm "$R/.ai/blocked/T5.md" attempts)" = 0

echo "F. doing/ 里无锁的孤儿任务 -> 按失败处理"
new_repo; mkdir -p "$R/.ai/doing"
cat > "$R/.ai/doing/T6.md" <<'EOF'
---
id: T6
status: claimed
priority: P1
created: 2026-11-10
attempts: 0
max_attempts: 1
risk: low
---
EOF
run_loop nochange
ok "达上限进 blocked/"            test -f "$R/.ai/blocked/T6.md"
ok "attempts = 1"                test "$(fm "$R/.ai/blocked/T6.md" attempts)" = 1

echo "G. worktree 目录已存在 -> 不 die，按失败处理且不删该目录"
new_repo; mk_task T7 low; mkdir -p "$R/.worktrees/T7"
run_loop commit
ok "退回 inbox"                  test -f "$R/.ai/inbox/T7.md"
ok "attempts = 1"                test "$(fm "$R/.ai/inbox/T7.md" attempts)" = 1
ok "已存在的目录没被删"            test -d "$R/.worktrees/T7"

echo "H. 状态提交只带本任务文件，不带走其他草稿"
new_repo; mk_task T8 low P0; mk_task T9 low P1
run_loop commit
ok "T8 已处理"                   test -f "$R/.ai/review/T8.md"
ok "草稿 T9 没被提交"              test -z "$(git -C "$R" ls-files .ai | grep T9 || true)"
ok "草稿 T9 仍在 inbox/"          test -f "$R/.ai/inbox/T9.md"

echo "I. check 能发现 status 与目录不一致"
new_repo; mkdir -p "$R/.ai/done"
printf -- '---\nid: T10\nstatus: new\n---\n' > "$R/.ai/done/T10.md"
ok "check 返回非 0"               bash -c "! (cd '$R' && bash scripts/ai-loop.sh check)"

echo "J. .ai/loop.env 提供项目默认值，环境变量仍优先"
new_repo; mk_task T11 low
(cd "$R" && DRY_RUN=1 bash scripts/ai-loop.sh) >"$TMP/j1.log" 2>&1
ok "无 loop.env：提示 PROJECT_TOOLS 为空"   grep -q 'PROJECT_TOOLS 为空' "$TMP/j1.log"
printf ': "${PROJECT_TOOLS:=Bash(make test)}"\n: "${REVIEW_LIMIT:=0}"\n' > "$R/.ai/loop.env"
(cd "$R" && DRY_RUN=1 bash scripts/ai-loop.sh) >"$TMP/j2.log" 2>&1
ok "loop.env 里的 PROJECT_TOOLS 生效（不再提示）" test -z "$(grep 'PROJECT_TOOLS 为空' "$TMP/j2.log" || true)"
ok "loop.env 里的 REVIEW_LIMIT=0 生效（等人审）"   grep -q '等人审' "$TMP/j2.log"
(cd "$R" && DRY_RUN=1 REVIEW_LIMIT=5 bash scripts/ai-loop.sh) >"$TMP/j3.log" 2>&1
ok "环境变量优先于 loop.env"                       test -z "$(grep '等人审' "$TMP/j3.log" || true)"

echo
echo "通过 $PASS，失败 $FAIL"
[ "$FAIL" = 0 ]
