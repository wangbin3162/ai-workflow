#!/usr/bin/env bash
# scripts/test-ai-workflow.sh — ai-workflow 的隔离回归测试
# 全部在 mktemp 临时仓库里跑；模型调用用假 claude；不碰真实任务池/真实分支。
# 用法：bash scripts/test-ai-workflow.sh    （全部通过退出码 0）
set -uo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
# 源码包布局：<repo>/scripts；初始化后的布局：<repo>/.ai-workflow/scripts
if [ -f "$BASE/templates/task.md" ] && [ -f "$BASE/scripts/ai-workflow.sh" ]; then
  SOURCE_REPO=0; SRC="$BASE/scripts/ai-workflow.sh"; TPL="$BASE/templates/task.md"
else
  SOURCE_REPO=1; SRC="$BASE/scripts/ai-workflow.sh"; TPL="$BASE/.ai-workflow/templates/task.md"
fi
SKILL="$BASE/skills/ai-workflow"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; N=0; R=""

ok()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  ok   %s\n' "$d"; else FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$d"; fi; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
pass() { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }

# 假 claude：STUB_MODE 决定行为；最终汇报末行带 AI_WORKFLOW_RESULT
cat > "$TMP/claude-stub" <<'EOF'
#!/usr/bin/env bash
case "${STUB_MODE:-nochange}" in
  commit)
    echo x >> stub.txt; git add stub.txt; git commit -qm "stub: change"
    res='changed\nAI_WORKFLOW_RESULT: done' ;;
  commit-discussion)
    echo x >> stub.txt; git add stub.txt; git commit -qm "stub: partial"
    echo y > partial.txt
    res='found ambiguity after partial work\nAI_WORKFLOW_RESULT: discussion' ;;
  commit-dirty)
    echo x >> stub.txt; git add stub.txt; git commit -qm "stub: change"
    echo y > dirty.txt
    res='changed with dirty file\nAI_WORKFLOW_RESULT: done' ;;
  discussion)
    res='need discussion\nAI_WORKFLOW_RESULT: discussion' ;;
  blocked)
    res='cannot proceed\nAI_WORKFLOW_RESULT: blocked' ;;
  nochange)
    res='nothing to do\nAI_WORKFLOW_RESULT: done' ;;
  fail)
    echo boom >&2; exit 1 ;;
esac
printf '{"result":"%s"}\n' "$res"
EOF
chmod +x "$TMP/claude-stub"

new_git_repo() {
  N=$((N+1)); R="$TMP/repo$N"; mkdir -p "$R"
  git -C "$R" init -q
  git -C "$R" symbolic-ref HEAD refs/heads/main
  git -C "$R" config user.name t; git -C "$R" config user.email t@t
  echo "# project" > "$R/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm init
}

new_flow_repo() {
  new_git_repo
  mkdir -p "$R/.ai-workflow"/{scripts,templates,inbox,discussion,doing,review,approved,done,blocked}
  cp "$SRC" "$R/.ai-workflow/scripts/ai-workflow.sh"
  cp "$TPL" "$R/.ai-workflow/templates/task.md"
  printf ': "${REVIEW_LIMIT:=10}"\n' > "$R/.ai-workflow/config.env"
  printf 'worktrees/\nlocks/\nlogs/\n' > "$R/.ai-workflow/.gitignore"
  echo app > "$R/app.txt"
  git -C "$R" add -A; git -C "$R" commit -qm "add workflow"
}

mk_task() { # $1 id, $2 risk
  cat > "$R/.ai-workflow/inbox/$1.md" <<EOF
---
id: $1
status: new
priority: P1
created: 2026-01-01
attempts: 0
max_attempts: 2
risk: $2
---

## 讨论

- 已确认事实：fixture 中的 app.txt 存在
- 待决问题：接口口径
- 可选方案：A 保持现状 / B 扩展
- 建议方案：A（建议，不是用户决定）
- 当前代码改动：无
- 用户下一步：请批准版本

## 方案

初版方案：按 A 实施。

## 验证记录

- 尚未运行（未实施）
EOF
}

wf()     { ( cd "$R" && bash .ai-workflow/scripts/ai-workflow.sh "$@" ) >"$TMP/wf.log" 2>&1; }
wf_ok()  { local d="$1"; shift; if wf "$@"; then pass "$d"; else bad "$d"; sed 's/^/         /' "$TMP/wf.log" | tail -8; fi; }
wf_fail(){ local d="$1"; shift; if wf "$@"; then bad "$d"; else pass "$d"; fi; }
wlog()   { grep -q "$1" "$TMP/wf.log"; }
wt()     { printf '%s/.ai-workflow/worktrees/%s\n' "$R" "$1"; }
head_of(){ git -C "$(wt "$1")" rev-parse HEAD; }
commit_wt(){ ( cd "$(wt "$1")" && echo "change-$RANDOM" >> change.txt && git add change.txt && git commit -qm "$2" ); }
snap()   { ( cd "$1" && find . -type f ! -path './.git/*' | sort | while IFS= read -r f; do shasum -a 256 "$f"; done ); }
fm()     { grep -m1 "^$2:" "$1" | sed "s/^$2: *//; s/ *#.*//"; }
run_stub(){ local mode="$1"; ( cd "$R" && STUB_MODE="$mode" CLAUDE_BIN="$TMP/claude-stub" \
             bash .ai-workflow/scripts/ai-workflow.sh run ) >"$TMP/run.log" 2>&1; }

# ---------------------------------------------------------------- 初始化
if [ "$SOURCE_REPO" = "1" ]; then
echo "I. 初始化只写 .ai-workflow/，且幂等、冲突可检测"

new_git_repo
mkdir -p "$R/docs"
printf 'agents rules\n' > "$R/AGENTS.md"
printf 'claude rules\n' > "$R/CLAUDE.md"
printf 'arch\n' > "$R/docs/ARCHITECTURE.md"
printf 'notes\n' > "$R/docs/notes.md"
printf 'node_modules/\n' > "$R/.gitignore"
git -C "$R" add -A; git -C "$R" commit -qm "project files"
outside_before="$(snap "$R")"
bash "$SKILL/scripts/install.sh" --target "$R" --plan >"$TMP/i-plan.log" 2>&1
ok "计划模式不改文件" test ! -e "$R/.ai-workflow"
bash "$SKILL/scripts/install.sh" --target "$R" --apply >"$TMP/i-apply.log" 2>&1
ok "初始化成功" test -f "$R/.ai-workflow/.initialized"
ok "生成 README/WORKFLOW/template/scripts" test -f "$R/.ai-workflow/README.md" -a -f "$R/.ai-workflow/WORKFLOW.md" -a -f "$R/.ai-workflow/templates/task.md" -a -f "$R/.ai-workflow/scripts/ai-workflow.sh"
ok "生成四份说明文档" test -f "$R/.ai-workflow/docs/QUICKSTART.md" -a -f "$R/.ai-workflow/docs/REFERENCE.md" -a -f "$R/.ai-workflow/docs/TROUBLESHOOTING.md" -a -f "$R/.ai-workflow/docs/MIGRATION.md"
ok "README 索引说明文档" bash -c "grep -q 'docs/QUICKSTART.md' '$R/.ai-workflow/README.md' && grep -q 'docs/REFERENCE.md' '$R/.ai-workflow/README.md' && grep -q 'docs/TROUBLESHOOTING.md' '$R/.ai-workflow/README.md' && grep -q 'docs/MIGRATION.md' '$R/.ai-workflow/README.md'"
ok "生成七个任务目录" test -d "$R/.ai-workflow/discussion" -a -d "$R/.ai-workflow/approved"
ok "AGENTS.md 未被修改" test "$(shasum -a 256 "$R/AGENTS.md" | cut -d' ' -f1)" = "$(printf 'agents rules\n' | shasum -a 256 | cut -d' ' -f1)"
ok "CLAUDE.md 未被修改" grep -qx 'claude rules' "$R/CLAUDE.md"
ok "docs/ 未新增 legacy 或迁移说明" test ! -e "$R/docs/legacy" -a ! -e "$R/docs/ai-workflow.md"
ok "根 .gitignore 未被修改" grep -qx 'node_modules/' "$R/.gitignore"
ok "没有在目标根新增 .claude/" test ! -e "$R/.claude"
ok "初始化未执行 git commit" test "$(git -C "$R" rev-list --count HEAD)" = 2

snap "$R" > "$TMP/before2.snap"
bash "$SKILL/scripts/install.sh" --target "$R" --apply >"$TMP/i-again.log" 2>&1
snap "$R" > "$TMP/after2.snap"
ok "重复初始化幂等（文件内容不变）" diff -q "$TMP/before2.snap" "$TMP/after2.snap"
ok "重复初始化输出 SKIP" grep -q 'SKIP' "$TMP/i-again.log"

printf 'tampered\n' >> "$R/.ai-workflow/WORKFLOW.md"
rm -f "$R/.ai-workflow/config.env"
printf 'custom\n' > "$R/.ai-workflow/custom.txt"
snap "$R" > "$TMP/before3.snap"
bash "$SKILL/scripts/install.sh" --target "$R" --apply >"$TMP/i-conflict.log" 2>&1
rc=$?
snap "$R" > "$TMP/after3.snap"
ok "内容冲突时退出码非 0" test "$rc" -ne 0
ok "冲突被明确列出" grep -q 'CONFLICT.*WORKFLOW.md' "$TMP/i-conflict.log"
ok "冲突时停止全部写入（缺失文件也没补）" test ! -e "$R/.ai-workflow/config.env"
ok "冲突时未覆盖用户内容" grep -qx 'tampered' <(tail -n 1 "$R/.ai-workflow/WORKFLOW.md")
ok "冲突时未改其他文件" diff -q "$TMP/before3.snap" "$TMP/after3.snap"
ok "用户自定义文件保留" test -f "$R/.ai-workflow/custom.txt"

mkdir -p "$R/.ai/inbox" "$R/scripts"; printf 'old\n' > "$R/.ai/inbox/T-OLD.md"; printf '#!/bin/sh\n' > "$R/scripts/ai-loop.sh"
bash "$SKILL/scripts/install.sh" --target "$R" --apply >"$TMP/i-legacy.log" 2>&1
ok "旧版 .ai/ 只提示不迁移" grep -q '旧版 .ai/' "$TMP/i-legacy.log"
ok "旧任务文件仍在原处" test -f "$R/.ai/inbox/T-OLD.md"
ok "旧脚本仍在原处" test -f "$R/scripts/ai-loop.sh"
wf_ok "安装后的 check 通过" check
ok "安装后的 next 可运行" bash -c "cd '$R' && bash .ai-workflow/scripts/ai-workflow.sh next | grep -q '没有 status: new'"

echo "J. 单一技能入口"
ok "skills 下只有一个 SKILL.md" test "$(find "$BASE/skills" -name SKILL.md | wc -l | tr -d ' ')" = 1
ok "唯一入口是 ai-workflow" grep -q '^name: ai-workflow' "$BASE/skills/ai-workflow/SKILL.md"
ok "不再有 ai-loop-task 技能目录" test ! -d "$BASE/skills/ai-loop-task"
ok "不再生成旧版 AGENTS 模板" bash -c "! find '$BASE/skills/ai-workflow/assets' -name 'AGENTS*' | grep -q ."
ok "任务模板说明由用户手写" grep -q '用户手写任务' "$TPL"
ok "没有自动建任务的 task/new 子命令" bash -c "cd '$R' && ! bash .ai-workflow/scripts/ai-workflow.sh task T-X >/dev/null 2>&1 && ! bash .ai-workflow/scripts/ai-workflow.sh new T-X >/dev/null 2>&1"
fi

# ---------------------------------------------------------------- 状态机
echo "A. 初始歧义 -> needs-discussion，业务代码零改动"
new_flow_repo; mk_task T1 low
wf_ok "claim 成功" claim T1 --by tester
ok "任务进入 doing/ 且 status=claimed" test "$(fm "$R/.ai-workflow/doing/T1.md" status)" = claimed
ok "任务锁存在且为 session" grep -qx 'kind=session' "$R/.ai-workflow/locks/T1/owner"
ok "worktree 已创建" test -d "$(wt T1)"
ok "任务分支为 ai/T1" test "$(git -C "$R" rev-parse --abbrev-ref ai/T1)" = ai/T1
ok "领取阶段没有业务代码改动" test -z "$(git -C "$(wt T1)" status --porcelain)"
ok "领取阶段没有 commit" test "$(git -C "$R" rev-list --count main..ai/T1)" = 0
wf_ok "pause 进入讨论" pause T1 --reason "接口口径不明确"
ok "任务进入 discussion/needs-discussion" test -f "$R/.ai-workflow/discussion/T1.md" -a "$(fm "$R/.ai-workflow/discussion/T1.md" status)" = needs-discussion
ok "pause 后释放锁" test ! -d "$R/.ai-workflow/locks/T1"
ok "worktree 保留" test -d "$(wt T1)"
ok "业务代码仍零改动" test -z "$(git -C "$(wt T1)" status --porcelain)"
ok "手动流程也不自动提交任务状态" test "$(git -C "$R" rev-list --count HEAD)" = 2
ok "讨论任务不出现在可领取列表" bash -c "cd '$R' && bash .ai-workflow/scripts/ai-workflow.sh next | grep -q '等待讨论'"
wf_fail "等待讨论任务不能被直接 claim" claim T1 --by tester

echo "B. 实施后发现歧义 -> 保留 commit/diff/worktree 并如实记录"
new_flow_repo; mk_task T1 low
wf_ok "claim" claim T1 --by tester
commit_wt T1 "partial work"
echo dirty > "$(wt T1)/dirty.txt"
wf_ok "pause" pause T1 --reason "实施中发现数据模型歧义"
ok "任务进入 discussion" test -f "$R/.ai-workflow/discussion/T1.md"
ok "已有 commit 保留" test "$(git -C "$R" rev-list --count main..ai/T1)" = 1
ok "未提交 diff 保留" test -f "$(wt T1)/dirty.txt"
ok "记录已提交改动数" grep -q '已提交改动：1' "$R/.ai-workflow/discussion/T1.md"
ok "记录未提交改动数" grep -q '未提交改动：1' "$R/.ai-workflow/discussion/T1.md"
ok "记录工作区路径" grep -q "$(wt T1)" "$R/.ai-workflow/discussion/T1.md"

echo "C. 等待讨论任务不会被 run 自动领取"
new_flow_repo; mk_task T1 low
wf_ok "claim 后暂停" claim T1 --by tester
wf_ok "pause" pause T1 --reason "待讨论"
mk_task T2 low
run_stub commit
ok "T1 仍在 discussion/" test -f "$R/.ai-workflow/discussion/T1.md"
ok "run 处理了另一个任务 T2" test -f "$R/.ai-workflow/review/T2.md"

echo "D. 方案批准：未批准 / 版本不符 / 内容变化后旧批准失效"
new_flow_repo; mk_task T1 low
wf_ok "claim" claim T1 --by tester
wf_ok "pause" pause T1 --reason "需要方案"
wf_fail "未批准不能 resume" resume T1
wf_ok "封存方案 v1" plan-seal T1 --version 1
wf_fail "未批准仍不能 resume" resume T1
p1="$(fm "$R/.ai-workflow/discussion/T1.md" plan_sha256)"
ok "plan_sha256 非空" test -n "$p1"
wf_fail "批准版本不符被拒绝" approve T1 --version 2 --by alice --note "批准 2"
wf_ok "用户明确批准 v1" approve T1 --version 1 --by alice --note "同意版本 1"
ok "批准记录写入 sha" test "$(fm "$R/.ai-workflow/discussion/T1.md" approved_plan_sha256)" = "$p1"
wf_ok "resume 成功" resume T1
ok "回到 doing/claimed" test "$(fm "$R/.ai-workflow/doing/T1.md" status)" = claimed
ok "worktree 复用而不是新建" test "$(git -C "$R" worktree list | grep -c 'ai/T1')" = 1
wf_ok "再次 pause" pause T1 --reason "方案要改"
perl -pi -e 's/初版方案/修改后的方案/' "$R/.ai-workflow/discussion/T1.md"
wf_fail "方案内容变化后旧批准失效，resume 被拒绝" resume T1
wf_ok "重新封存 v2" plan-seal T1 --version 2
ok "封存变更后旧批准被清空" test -z "$(fm "$R/.ai-workflow/discussion/T1.md" approved_plan_sha256)"
wf_fail "旧版本批准不能用于新版本" approve T1 --version 1 --by alice --note "批准旧版"
wf_ok "批准 v2" approve T1 --version 2 --by alice --note "同意版本 2"
wf_ok "resume v2 成功" resume T1

echo "E. 锁：手动会话与 run 互斥，遗留锁边界明确"
new_flow_repo; mk_task T1 low
mkdir -p "$R/.ai-workflow/locks/T1"
printf 'kind=session\nby=other-session\npid=999999\ncreated=old\n' > "$R/.ai-workflow/locks/T1/owner"
wf_fail "其他会话持锁时 claim 被拒绝" claim T1 --by tester
ok "任务没有被移走" test -f "$R/.ai-workflow/inbox/T1.md"
wf_ok "release 后可领取" release T1
wf_ok "claim 成功" claim T1 --by tester
mk_task T2 low
run_stub commit
ok "run 不抢正在 doing 的任务" test -f "$R/.ai-workflow/doing/T1.md" -a -f "$R/.ai-workflow/review/T2.md"
ok "T1 锁仍属于手动会话" grep -qx 'kind=session' "$R/.ai-workflow/locks/T1/owner"

new_flow_repo; mk_task T3 low
mkdir -p "$R/.ai-workflow/locks/T3"
printf 'kind=run\nby=dead-run\npid=999999\ncreated=old\n' > "$R/.ai-workflow/locks/T3/owner"
touch -t 202001010000 "$R/.ai-workflow/locks/T3"
wf_ok "死进程的过期 run 锁会被清理后领取" claim T3 --by tester

new_flow_repo; mk_task T4 low
mkdir -p "$R/.ai-workflow/locks/T4"
printf 'kind=session\nby=crashed-session\npid=999999\ncreated=old\n' > "$R/.ai-workflow/locks/T4/owner"
touch -t 202001010000 "$R/.ai-workflow/locks/T4"
wf_fail "过期 session 锁不会被自动抢" claim T4 --by tester
ok "提示 release 边界" grep -q 'release T4' "$TMP/wf.log"
wf_ok "显式 release 后领取" release T4
wf_ok "claim 成功" claim T4 --by tester

echo "F. worktree 识别：已有 worktree 复用，不嵌套"
new_flow_repo; mk_task T1 low
git -C "$R" worktree add "$R/.ai-workflow/worktrees/T1" -b ai/T1 >/dev/null 2>&1
wf_ok "claim 复用已有 worktree" claim T1 --by tester
ok "同一分支只有一个 worktree" test "$(git -C "$R" worktree list | grep -c 'ai/T1')" = 1
ok "没有嵌套 worktree" test ! -d "$(wt T1)/.ai-workflow/worktrees"
wf_ok "review 前状态一致" check

new_flow_repo; mk_task T5 low
git -C "$R" branch ai/T5
git -C "$R" checkout -q ai/T5
wf_fail "主 checkout 在任务分支时拒绝领取" claim T5 --by tester
git -C "$R" checkout -q main

echo "G. review -> approve-review -> 人工合并 -> done"
new_flow_repo; mk_task T1 low
wf_ok "claim" claim T1 --by tester
commit_wt T1 "implement T1"
perl -pi -e 's/尚未运行（未实施）/bash test.sh 退出码 0/' "$R/.ai-workflow/doing/T1.md"
wf_ok "review 成功" review T1
ok "进入 review/needs_review" test "$(fm "$R/.ai-workflow/review/T1.md" status)" = needs_review
sha="$(fm "$R/.ai-workflow/review/T1.md" review_commit)"
ok "记录送审 commit" test "$sha" = "$(head_of T1)"
ok "worktree 仍保留" test -d "$(wt T1)"
ok "review 后锁已释放" test ! -d "$R/.ai-workflow/locks/T1"
wf_ok "释放不存在的锁也不报错" release T1
wf_fail "不能从 review/ 直接 done" done T1 --target main --merged-commit "$(git -C "$R" rev-parse HEAD)" --by bob --note "跳步"
wf_fail "审查 commit 不符被拒绝" approve-review T1 --commit "$(git -C "$R" rev-parse HEAD)" --by bob --note "看错了"
wf_ok "审查批准正确 commit" approve-review T1 --commit "$sha" --by bob --note "diff 与验证记录通过"
ok "进入 approved/review_approved（尚未合并）" test "$(fm "$R/.ai-workflow/approved/T1.md" status)" = review_approved
wf_fail "缺少人工确认人不能归档" done T1 --target main --merged-commit "$sha" --note "还没合并"
wf_fail "缺少人工确认原话不能归档" done T1 --target main --merged-commit "$sha" --by bob
wf_fail "未合并时 done 被拒绝" done T1 --target main --merged-commit "$sha" --by bob --note "还没合并"
git -C "$R" merge --no-ff ai/T1 -m "merge T1" >/dev/null 2>&1
merge_sha="$(git -C "$R" rev-parse HEAD)"
wf_ok "有合并证据后 done 成功" done T1 --target main --merged-commit "$merge_sha" --by bob --note "已在 main 上确认合并"
ok "归档到 done/" test "$(fm "$R/.ai-workflow/done/T1.md" status)" = done
ok "记录合并提交" test "$(fm "$R/.ai-workflow/done/T1.md" merged_commit)" = "$merge_sha"
ok "worktree 未删除" test -d "$(wt T1)"
ok "分支未删除" test "$(git -C "$R" rev-parse --verify ai/T1)" = "$sha"
wf_ok "done 后 check 通过" check

echo "H. 批准后代码变化 -> 旧批准不能沿用"
new_flow_repo; mk_task T1 low
wf_ok "claim" claim T1 --by tester
commit_wt T1 "implement"
perl -pi -e 's/尚未运行（未实施）/bash test.sh 退出码 0/' "$R/.ai-workflow/doing/T1.md"
wf_ok "review" review T1
sha="$(fm "$R/.ai-workflow/review/T1.md" review_commit)"
wf_ok "approve-review" approve-review T1 --commit "$sha" --by bob --note "通过"
commit_wt T1 "after approval"
wf_fail "批准后分支有新 commit，done 被拒绝" done T1 --target main --merged-commit "$(git -C "$R" rev-parse HEAD)" --by bob --note "尝试归档"
ok "拒绝原因明确" grep -q '批准后分支又有变化' "$TMP/wf.log"

echo "I. squash 合并：可归档但标注受限校验"
new_flow_repo; mk_task T1 low
wf_ok "claim" claim T1 --by tester
commit_wt T1 "implement"
perl -pi -e 's/尚未运行（未实施）/bash test.sh 退出码 0/' "$R/.ai-workflow/doing/T1.md"
wf_ok "review" review T1
sha="$(fm "$R/.ai-workflow/review/T1.md" review_commit)"
wf_ok "approve-review" approve-review T1 --commit "$sha" --by bob --note "通过"
git -C "$R" merge --squash ai/T1 >/dev/null 2>&1
git -C "$R" commit -qm "squash T1"
squash_sha="$(git -C "$R" rev-parse HEAD)"
wf_fail "squash 合并不能按 merge 方式归档" done T1 --target main --merged-commit "$squash_sha" --by bob --note "squash"
wf_ok "显式 --method squash 可归档" done T1 --target main --merged-commit "$squash_sha" --method squash --by bob --note "squash 合并确认"
ok "证据写明受限校验" grep -q '无法用 sha 证明内容等价' "$R/.ai-workflow/done/T1.md"

echo "J. risk high 无代码：审查后可归档，但必须显式 --no-code"
new_flow_repo; mk_task T1 high
wf_ok "claim" claim T1 --by tester
wf_ok "review（计划）" review T1
ok "review_commit=none" test "$(fm "$R/.ai-workflow/review/T1.md" review_commit)" = none
wf_ok "approve-review none" approve-review T1 --commit none --by bob --note "方案通过"
wf_fail "无代码但有普通 done 参数被拒绝" done T1 --target main --merged-commit "$(git -C "$R" rev-parse HEAD)" --by bob --note "x"
wf_ok "显式 --no-code 归档" done T1 --no-code --by bob --note "确认无代码"
ok "done 且 check 通过" bash -c "cd '$R' && bash .ai-workflow/scripts/ai-workflow.sh check"

echo "K. claude -p 回归：成功/失败/阻断/歧义/中断"
new_flow_repo; mk_task T1 low
before_commits="$(git -C "$R" rev-list --count HEAD)"
run_stub commit
ok "low + commit -> review/" test -f "$R/.ai-workflow/review/T1.md"
ok "状态 needs_review" test "$(fm "$R/.ai-workflow/review/T1.md" status)" = needs_review
ok "脚本不提交任务状态（主分支提交数不变）" test "$(git -C "$R" rev-list --count HEAD)" = "$before_commits"

new_flow_repo; mk_task T1 low
run_stub nochange
ok "low 无 commit -> 退回 inbox" test -f "$R/.ai-workflow/inbox/T1.md"
ok "attempts=1" test "$(fm "$R/.ai-workflow/inbox/T1.md" attempts)" = 1

new_flow_repo; mk_task T1 low
run_stub fail
ok "退出码非 0 -> 退回 inbox" test -f "$R/.ai-workflow/inbox/T1.md"
ok "退出码非 0 时 attempts=1" test "$(fm "$R/.ai-workflow/inbox/T1.md" attempts)" = 1

new_flow_repo; mk_task T1 low
run_stub blocked
ok "agent blocked -> blocked/，不消耗 attempts" test -f "$R/.ai-workflow/blocked/T1.md" -a "$(fm "$R/.ai-workflow/blocked/T1.md" attempts)" = 0

new_flow_repo; mk_task T1 high
run_stub commit
ok "risk high 产生改动 -> blocked 交人工" test -f "$R/.ai-workflow/blocked/T1.md"
ok "改动 worktree 保留" test -d "$(wt T1)"
ok "risk high 未进 review" test ! -e "$R/.ai-workflow/review/T1.md"

new_flow_repo; mk_task T1 high
run_stub nochange
ok "risk high 无改动 -> review/" test -f "$R/.ai-workflow/review/T1.md"

new_flow_repo; mk_task T1 low
run_stub discussion
ok "agent 报歧义 -> discussion/" test -f "$R/.ai-workflow/discussion/T1.md"
ok "歧义时业务代码零改动" test -z "$(git -C "$(wt T1)" status --porcelain)"
ok "歧义不消耗 attempts" test "$(fm "$R/.ai-workflow/discussion/T1.md" attempts)" = 0

new_flow_repo; mk_task T1 low
run_stub commit-discussion
ok "实施后才报歧义 -> discussion/" test -f "$R/.ai-workflow/discussion/T1.md"
ok "已提交改动保留" test "$(git -C "$R" rev-list --count main..ai/T1)" = 1
ok "未提交改动保留" test -f "$(wt T1)/partial.txt"

new_flow_repo; mkdir -p "$R/.ai-workflow/doing"
printf -- '---\nid: T9\nstatus: claimed\nrisk: low\nattempts: 0\nmax_attempts: 2\n---\n' > "$R/.ai-workflow/doing/T9.md"
run_stub nochange
ok "doing/ 无锁孤儿任务 -> blocked/" test -f "$R/.ai-workflow/blocked/T9.md"
ok "孤儿任务不消耗 attempts" test "$(fm "$R/.ai-workflow/blocked/T9.md" attempts)" = 0

echo "L. check 能发现伪造归档与失效批准"
new_flow_repo; mkdir -p "$R/.ai-workflow/done"
cat > "$R/.ai-workflow/done/T8.md" <<'EOF'
---
id: T8
status: done
risk: low
review_approved_commit: abc123
---
EOF
ok "有批准记录但无合并证据 -> check 失败" bash -c "! (cd '$R' && bash .ai-workflow/scripts/ai-workflow.sh check)"
new_flow_repo; mkdir -p "$R/.ai-workflow/discussion"
cat > "$R/.ai-workflow/discussion/T7.md" <<'EOF'
---
id: T7
status: needs-discussion
risk: low
plan_version: 1
plan_sha256: deadbeef
approved_version: 1
approved_plan_sha256: deadbeef
approved_by: alice
approved_note: ok
---

## 方案
内容
EOF
ok "讨论任务批准 sha 失效 -> check 失败" bash -c "! (cd '$R' && bash .ai-workflow/scripts/ai-workflow.sh check)"

echo
echo "通过 ${PASS}，失败 $FAIL"
[ "$FAIL" = 0 ]
