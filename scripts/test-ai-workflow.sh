#!/usr/bin/env bash
# scripts/test-ai-workflow.sh — ai-workflow 初始化/结构回归测试
# 全部在 mktemp 临时仓库里跑；不调用模型、不碰真实任务池。
# 用法：bash scripts/test-ai-workflow.sh    （全部通过退出码 0）
set -uo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$BASE/skills/ai-workflow"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; N=0; R=""

ok()   { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  ok   %s\n' "$d"; else FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$d"; fi; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

new_repo() {
  N=$((N+1)); R="$TMP/repo$N"; mkdir -p "$R/docs"
  git -C "$R" init -q
  git -C "$R" symbolic-ref HEAD refs/heads/main
  git -C "$R" config user.name t; git -C "$R" config user.email t@t
  printf 'agents rules\n' > "$R/AGENTS.md"
  printf 'claude rules\n' > "$R/CLAUDE.md"
  printf 'arch\n' > "$R/docs/ARCHITECTURE.md"
  printf 'node_modules/\n.ai-workflow\n' > "$R/.gitignore"
  echo hi > "$R/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm init
}

install_plan()  { bash "$SKILL/scripts/install.sh" --target "$R" >"$TMP/plan.log" 2>&1; }
install_apply() { bash "$SKILL/scripts/install.sh" --target "$R" --apply >"$TMP/apply.log" 2>&1; }
verify()        { bash "$SKILL/scripts/verify.sh" "$R" >"$TMP/verify.log" 2>&1; }
hash()          { shasum -a 256 "$1" | awk '{print $1}'; }
snap_out()      { ( cd "$1" && find . -type f ! -path './.git/*' ! -path './.ai-workflow/*' | sort | while IFS= read -r f; do shasum -a 256 "$f"; done ); }

echo "A. 新项目初始化：只生成 README/TEMPLATE/CONFIG + 五个目录"
new_repo
outside_before="$(snap_out "$R")"
install_plan
ok "计划模式不创建 .ai-workflow" test ! -e "$R/.ai-workflow"
install_apply
ok "初始化成功" test -f "$R/.ai-workflow/README.md"
ok "生成 TEMPLATE.md" test -f "$R/.ai-workflow/TEMPLATE.md"
ok "生成 CONFIG.md" test -f "$R/.ai-workflow/CONFIG.md"
ok "生成 inbox/doing/review/done/list" test -d "$R/.ai-workflow/inbox" -a -d "$R/.ai-workflow/doing" -a -d "$R/.ai-workflow/review" -a -d "$R/.ai-workflow/done" -a -d "$R/.ai-workflow/list"
ok "没有 scripts/" test ! -e "$R/.ai-workflow/scripts"
ok "没有 docs/ 或 WORKFLOW.md" test ! -e "$R/.ai-workflow/docs" -a ! -e "$R/.ai-workflow/WORKFLOW.md"
ok "没有 templates/ 或 config.env" test ! -e "$R/.ai-workflow/templates" -a ! -e "$R/.ai-workflow/config.env"
ok "没有 .gitignore / .initialized / 示例任务" test ! -e "$R/.ai-workflow/.gitignore" -a ! -e "$R/.ai-workflow/.initialized" -a ! -e "$R/.ai-workflow/inbox/EXAMPLE-T-20260101-001.md"
ok "根目录只有 README/TEMPLATE/CONFIG 和五个目录" test "$(find "$R/.ai-workflow" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 8
ok "AGENTS/CLAUDE/docs/根 .gitignore 未被修改" test "$(snap_out "$R")" = "$outside_before"
ok "没有创建 .claude/ 或 docs/legacy" test ! -e "$R/.claude" -a ! -e "$R/docs/legacy"
ok "初始化没有 git commit" test "$(git -C "$R" rev-list --count HEAD)" = 1
ok "README 有 v3 标记" bash -c "head -n 1 '$R/.ai-workflow/README.md' | grep -q ai-workflow:v3"
ok "README 含状态与目录说明" grep -q '^## 1\. 目录与状态' "$R/.ai-workflow/README.md"
ok "README 指向 TEMPLATE.md" grep -q 'TEMPLATE.md' "$R/.ai-workflow/README.md"
ok "README 指向 CONFIG.md" grep -q 'CONFIG.md' "$R/.ai-workflow/README.md"
ok "CONFIG 预填当前分支 main" grep -q '基准分支.*main' "$R/.ai-workflow/CONFIG.md"
ok "CONFIG 保留测试命令 TODO" grep -q 'TODO:' "$R/.ai-workflow/CONFIG.md"
ok "README 说明 list 拆分" grep -q '从 list/ 拆分任务' "$R/.ai-workflow/README.md"
ok "TEMPLATE 含任务 front-matter 与验证区" bash -c "grep -q '^id: T-YYYYMMDD-001' '$R/.ai-workflow/TEMPLATE.md' && grep -q '^## 验证记录' '$R/.ai-workflow/TEMPLATE.md'"
ok "README 含方案 sha256 命令" grep -q 'shasum -a 256' "$R/.ai-workflow/README.md"
ok "README 含审查不等于合并" grep -q '人工审查批准（不等于合并）' "$R/.ai-workflow/README.md"
ok "README 含 worktree 复用检查" grep -q 'git worktree list --porcelain' "$R/.ai-workflow/README.md"
ok "README 含不自动合并" grep -q '不自动合并' "$R/.ai-workflow/README.md"
ok "TEMPLATE 含批准与合并字段" bash -c "grep -q 'review_approved_commit' '$R/.ai-workflow/TEMPLATE.md' && grep -q 'merged_commit' '$R/.ai-workflow/TEMPLATE.md'"
verify
ok "verify 通过" test $? -eq 0
ok "verify 提示 CONFIG TODO" grep -q 'WARN.*TODO' "$TMP/verify.log"

echo "B. 幂等：重复初始化保留 README/TEMPLATE/CONFIG 与用户修改"
before="$(hash "$R/.ai-workflow/README.md")"
config_before="$(hash "$R/.ai-workflow/CONFIG.md")"
install_apply
ok "重复 apply 退出码 0" test $? -eq 0
ok "README 内容未变" test "$(hash "$R/.ai-workflow/README.md")" = "$before"
ok "CONFIG 内容未变" test "$(hash "$R/.ai-workflow/CONFIG.md")" = "$config_before"
ok "重复 apply 输出 SKIP" grep -q 'SKIP' "$TMP/apply.log"
printf '\n<!-- 用户补充说明 -->\n' >> "$R/.ai-workflow/README.md"
install_apply
ok "用户修改 README 后重复 apply 不覆盖" test $? -eq 0
ok "用户修改保留" grep -q '用户补充说明' "$R/.ai-workflow/README.md"

echo "C. 未标记的 README 冲突时不写任何文件"
new_repo; mkdir -p "$R/.ai-workflow"; printf '# 用户自己的说明\n' > "$R/.ai-workflow/README.md"
install_apply
ok "冲突退出码非 0" test $? -ne 0
ok "冲突原因明确" grep -q '未标记' "$TMP/apply.log"
ok "冲突时没有创建任务目录" test ! -e "$R/.ai-workflow/inbox"
ok "冲突时没有创建 CONFIG.md" test ! -e "$R/.ai-workflow/CONFIG.md"
ok "用户 README 未被覆盖" grep -qx '# 用户自己的说明' "$R/.ai-workflow/README.md"

echo "D. 旧版结构不自动升级"
new_repo; mkdir -p "$R/.ai-workflow"; printf 'ai-workflow:v1\n' > "$R/.ai-workflow/.initialized"
install_apply
ok "旧版结构退出码非 0" test $? -ne 0
ok "提示手动迁移" grep -q '不自动升级' "$TMP/apply.log"
ok "旧结构文件保留" test -f "$R/.ai-workflow/.initialized"

echo "E. 旧 .ai/ 只提示，不迁移"
new_repo; mkdir -p "$R/.ai/inbox"; printf 'old\n' > "$R/.ai/inbox/T-OLD.md"
install_apply
ok "旧 .ai/ 场景仍可完成初始化" test -f "$R/.ai-workflow/README.md"
ok "旧 .ai/ 有 WARN" grep -q '旧版 .ai/' "$TMP/apply.log"
ok "旧任务仍在原处" test -f "$R/.ai/inbox/T-OLD.md"

echo "F. verify 能发现结构缺失"
new_repo; install_apply >/dev/null 2>&1
rm "$R/.ai-workflow/README.md"
verify
ok "缺 README 时 verify 失败" test $? -ne 0
new_repo; install_apply >/dev/null 2>&1
rm "$R/.ai-workflow/CONFIG.md"
verify
ok "缺 CONFIG 时 verify 失败" test $? -ne 0
new_repo; install_apply >/dev/null 2>&1
rmdir "$R/.ai-workflow/review"
verify
ok "缺 review/ 时 verify 失败" test $? -ne 0

echo "G. 单一技能入口与最小资产"
ok "skills 下只有一个 SKILL.md" test "$(find "$BASE/skills" -name SKILL.md | wc -l | tr -d ' ')" = 1
ok "入口名为 ai-workflow" grep -q '^name: ai-workflow' "$SKILL/SKILL.md"
ok "没有 ai-loop-task/ai-loop-init 技能目录" test ! -d "$BASE/skills/ai-loop-task" -a ! -d "$BASE/skills/ai-loop-init"
ok "assets 是 README/TEMPLATE/CONFIG" test "$(find "$SKILL/assets" -type f | wc -l | tr -d ' ')" = 3
ok "assets/README.md、TEMPLATE.md、CONFIG.md 存在" test -f "$SKILL/assets/README.md" -a -f "$SKILL/assets/TEMPLATE.md" -a -f "$SKILL/assets/CONFIG.md"
ok "不再保留 archive/ 历史目录" test ! -e "$BASE/archive"

echo
echo "通过 ${PASS}，失败 ${FAIL}"
[ "$FAIL" = 0 ]
