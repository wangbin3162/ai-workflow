#!/usr/bin/env bash
# check.sh <仓库根目录> — 运行时一致性校验（只读，不改任何文件）
# 检查所有任务文件的 status/目录、id/文件名、锁、必填字段、方案批准、worktree。
# 全部通过退出码 0；有 FAIL 退出码 1。WARN 不影响退出码。
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
warn() { printf '  WARN %s\n' "$1"; }

# 从 front-matter 提取字段值：fm_val <文件> <字段名>
fm_val() {
  awk -v key="$2" '
    /^---$/ { n++; next }
    n==1 && $0 ~ "^"key":" {
      sub("^"key":[ ]*", ""); print; exit
    }
  ' "$1"
}

# 收集任务文件
found=0
for dir in inbox doing review done; do
  dir_path=".ai-workflow/$dir"
  [ -d "$dir_path" ] || continue
  for f in "$dir_path"/T-*.md; do
    [ -f "$f" ] || continue
    found=1
    fname="$(basename "$f" .md)"
    id="$(fm_val "$f" id)"
    status="$(fm_val "$f" status)"

    # ── 1. status-目录一致性 ──
    case "$dir" in
      inbox)  expected_re='^(new|needs-discussion|blocked)$' ;;
      doing)  expected_re='^claimed$' ;;
      review) expected_re='^(needs_review|review_approved)$' ;;
      done)   expected_re='^done$' ;;
    esac
    if printf '%s' "$status" | grep -qE "$expected_re"; then
      ok "status-目录一致性：${fname}（${dir}/，${status}）"
    else
      bad "status-目录一致性：${fname}（${dir}/，${status} — 应在其他目录）"
    fi

    # ── 2. id-文件名一致性 ──
    if [ "$id" = "$fname" ]; then
      ok "id-文件名一致性：${fname}"
    else
      bad "id-文件名一致性：${fname}（front-matter id=${id}，文件名=${fname}）"
    fi

    # ── 3. 锁状态 ──
    lock_dir=".ai-workflow/.locks/${id}"
    if [ "$dir" = "doing" ]; then
      if [ -d "$lock_dir" ]; then
        ok "锁状态：${fname}（doing/ 有锁）"
      else
        bad "锁状态：${fname}（doing/ 缺少锁 ${lock_dir}）"
      fi
    else
      if [ -d "$lock_dir" ]; then
        warn "锁残留：${fname}（${lock_dir}/ 存在但任务在 ${dir}/）"
      fi
    fi

    # ── 4. 送审必填字段 ──
    if [ "$dir" = "review" ]; then
      review_commit="$(fm_val "$f" review_commit)"
      if [ -n "$review_commit" ]; then
        ok "送审必填字段：${fname}（review_commit=${review_commit}）"
      else
        bad "送审必填字段：${fname}（review/ 缺少 review_commit）"
      fi
    fi

    # ── 5. 归档必填字段 ──
    if [ "$dir" = "done" ]; then
      merge_target="$(fm_val "$f" merge_target)"
      merged_commit="$(fm_val "$f" merged_commit)"
      merged_by="$(fm_val "$f" merged_by)"
      missing=""
      [ -z "$merge_target" ]  && missing="${missing} merge_target"
      [ -z "$merged_commit" ] && missing="${missing} merged_commit"
      [ -z "$merged_by" ]     && missing="${missing} merged_by"
      if [ -z "$missing" ]; then
        ok "归档必填字段：${fname}"
      else
        bad "归档必填字段：${fname}（缺少${missing}）"
      fi
    fi

    # ── 6. 方案批准校验 ──
    approved_version="$(fm_val "$f" approved_version)"
    if [ -n "$approved_version" ]; then
      approved_sha="$(fm_val "$f" approved_plan_sha256)"
      current_sha="$(awk '/^## 方案/{f=1;next} /^## /{f=0} f' "$f" | shasum -a 256 | awk '{print $1}')"
      if [ "$approved_sha" = "$current_sha" ]; then
        ok "方案批准校验：${fname}（sha256 匹配）"
      else
        bad "方案批准校验：${fname}（approved_plan_sha256 与方案正文不一致）"
      fi
    fi

    # ── 7. worktree 存在性 ──
    wt="$(fm_val "$f" worktree)"
    if [ -n "$wt" ]; then
      if [ -d "$wt" ]; then
        ok "worktree 存在性：${fname}（${wt}）"
      else
        bad "worktree 存在性：${fname}（${wt} 不存在）"
      fi
    fi
  done
done

# ── 8. 任务池顺序指南 ──
guide_file=".ai-workflow/inbox/GUIDE.md"
if [ -f "$guide_file" ]; then
  guide_ids="$(awk '/^## 当前顺序/{f=1;next} /^## /{f=0} f' "$guide_file" | grep -oE 'T-[0-9]{8}-[0-9]{3}' | sort -u)"
  dup_ids="$(awk '/^## 当前顺序/{f=1;next} /^## /{f=0} f' "$guide_file" | grep -oE 'T-[0-9]{8}-[0-9]{3}' | sort | uniq -d)"
  if [ -n "$dup_ids" ]; then
    bad "任务池指南：存在重复任务 ID（$(printf '%s' "$dup_ids" | tr '\n' ' ')）"
  else
    ok "任务池指南：任务 ID 不重复"
  fi

  stale=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! find .ai-workflow/inbox .ai-workflow/doing .ai-workflow/review \
      -maxdepth 1 -type f -name "$id.md" 2>/dev/null | grep -q .; then
      bad "任务池指南：${id} 已不在未完成任务目录"
      stale=1
    fi
  done <<< "$guide_ids"
  [ "$stale" -eq 0 ] && ok "任务池指南：未引用已完成或已归档任务"

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .md)"
    if ! printf '%s\n' "$guide_ids" | grep -qx "$id"; then
      warn "任务池指南：未列入 ${id}"
    fi
  done <<< "$(find .ai-workflow/inbox .ai-workflow/doing .ai-workflow/review -maxdepth 1 -type f -name 'T-*.md' 2>/dev/null)"
else
  warn "缺少 .ai-workflow/inbox/GUIDE.md：无法核对任务池顺序"
fi

if [ "$found" -eq 0 ]; then
  echo "没有找到任务文件"
  exit 0
fi

echo
echo "通过 ${PASS}，失败 $FAIL"
[ "$FAIL" -eq 0 ]
