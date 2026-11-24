#!/usr/bin/env bash
# verify.sh <仓库根目录> — 初始化后的结构检查（只读，不调用模型、不跑任务）
# 全部通过退出码 0；有 FAIL 退出码 1。WARN 不影响退出码。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
warn() { printf '  WARN %s\n' "$1"; }
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== 必需结构（全部在 .ai-workflow/ 内）=="
chk "存在 .ai-workflow/README.md" test -s .ai-workflow/README.md
chk "存在 .ai-workflow/TEMPLATE.md" test -s .ai-workflow/TEMPLATE.md
chk "存在 .ai-workflow/CONFIG.md" test -s .ai-workflow/CONFIG.md
chk "存在 .ai-workflow/guide.html" test -s .ai-workflow/guide.html
chk "存在 .ai-workflow/HISTORY.md" test -s .ai-workflow/HISTORY.md
chk "存在 .ai-workflow/list/buglist.md" test -s .ai-workflow/list/buglist.md
for d in inbox doing review done list; do
  chk "存在 .ai-workflow/$d/" test -d ".ai-workflow/$d"
done
chk "README 是 v3 初始化文档" bash -c "head -n 1 .ai-workflow/README.md 2>/dev/null | grep -q 'ai-workflow:v3'"
chk "CONFIG 是 config-v1 模板" bash -c "head -n 1 .ai-workflow/CONFIG.md 2>/dev/null | grep -q 'ai-workflow:config-v1'"
chk "guide 是 guide-v1 图解" grep -q 'ai-workflow:guide-v1' .ai-workflow/guide.html
chk "guide 说明批准与人工合并" bash -c "grep -q 'README.md' .ai-workflow/guide.html && grep -q '批准版本' .ai-workflow/guide.html && grep -q '人工合并' .ai-workflow/guide.html"

echo "== README 内容 =="
chk "说明状态与目录" grep -q '^## 1\. 目录与状态' .ai-workflow/README.md
chk "指向 CONFIG.md" grep -q 'CONFIG.md' .ai-workflow/README.md
chk "说明任务模板文件" grep -q 'TEMPLATE.md' .ai-workflow/README.md
chk "说明从 list/ 拆分任务" bash -c "grep -q '从 list/ 拆分任务' .ai-workflow/README.md"
chk "任务模板含 front-matter 与验证区" bash -c "grep -q '^id: T-YYYYMMDD-001' .ai-workflow/TEMPLATE.md && grep -q '^## 方案' .ai-workflow/TEMPLATE.md && grep -q '^## 验证记录' .ai-workflow/TEMPLATE.md"
chk "任务模板区分用户填写与 AI 维护" grep -q '用户填写' .ai-workflow/TEMPLATE.md
chk "说明方案批准与 sha256" bash -c "grep -q '方案版本与批准' .ai-workflow/README.md && grep -q 'shasum -a 256' .ai-workflow/README.md"
chk "说明人工审查不等于合并" grep -q '人工审查批准（不等于合并）' .ai-workflow/README.md
chk "说明 worktree 平级目录与复用" bash -c "grep -q '\.ai-worktrees' .ai-workflow/README.md && grep -q 'git worktree list --porcelain' .ai-workflow/README.md"
chk "说明不自动合并" grep -q '不自动合并' .ai-workflow/README.md
chk "说明 needs-discussion 不可领取" bash -c "grep -q 'needs-discussion' .ai-workflow/README.md && grep -q '不得.*领取' .ai-workflow/README.md"
chk "说明合并证据与 squash 边界" bash -c "grep -q 'merged_commit' .ai-workflow/README.md && grep -q '无法用 sha 证明内容等价' .ai-workflow/README.md"
chk "说明归档清理" grep -q '归档清理' .ai-workflow/README.md

echo "== 项目配置与旧结构 =="
chk "CONFIG 含基准分支" grep -q '基准分支' .ai-workflow/CONFIG.md
chk "CONFIG 含测试 / 构建命令" grep -q '测试 / 构建命令' .ai-workflow/CONFIG.md
chk "CONFIG 含 worktree 依赖安装" grep -q 'worktree 依赖安装' .ai-workflow/CONFIG.md
chk "CONFIG 已替换分支占位符" bash -c "! grep -q '{{CURRENT_BRANCH}}' .ai-workflow/CONFIG.md"
if grep -q 'TODO:' .ai-workflow/CONFIG.md 2>/dev/null; then
  warn "CONFIG.md 还有 TODO：请补全测试命令 / 依赖安装"
fi
if grep -q 'TODO:' .ai-workflow/README.md 2>/dev/null; then
  warn "README 还有 TODO：请人工检查"
fi
for p in .initialized .gitignore config.env scripts docs templates discussion approved blocked; do
  if [ -e ".ai-workflow/$p" ]; then
    warn ".ai-workflow/$p 是旧版/额外内容；当前初始化不应生成，建议人工清理"
  fi
done
if [ -d .ai ]; then warn "发现旧版 .ai/：本工作流不使用，按迁移说明人工处理"; fi

echo
echo "通过 ${PASS}，失败 $FAIL"
[ "$FAIL" -eq 0 ]
