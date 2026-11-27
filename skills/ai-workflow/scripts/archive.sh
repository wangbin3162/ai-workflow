#!/usr/bin/env bash
# archive.sh <仓库根目录> [--plan|--apply]
# 归档清理：整理已完成任务（移动到 .ai-workflow/archive/，清理 worktree 与已合并分支）
# 默认 --plan：只打印计划，不改动任何文件。加 --apply 执行。
set -uo pipefail

TARGET="."
MODE="plan"

die()  { printf '[archive][error] %s\n' "$*" >&2; exit 1; }
say()  { printf '%-9s %s\n' "$1" "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)  MODE="plan"; shift ;;
    --apply) MODE="apply"; shift ;;
    -h|--help)
      echo "用法：archive.sh [仓库根目录] [--plan|--apply]"
      echo "  --plan   默认：只打印将归档的任务和清理项，不改动文件"
      echo "  --apply  执行归档与清理"
      exit 0
      ;;
    *)
      if [ -d "$1" ]; then
        TARGET="$1"; shift
      else
        die "未知参数或目录不存在：$1"
      fi
      ;;
  esac
done

cd "$TARGET" || die "无法进入目录：$TARGET"
[ -d .ai-workflow ] || die "未找到 .ai-workflow 目录"

# 从 front-matter 提取字段值
fm_val() {
  awk -v key="$2" '
    /^---$/ { n++; next }
    n==1 && $0 ~ "^"key":" {
      sub("^"key":[ ]*", ""); print; exit
    }
  ' "$1"
}

DONE_DIR=".ai-workflow/done"
ARCHIVE_DIR=".ai-workflow/archive"
GUIDE_FILE=".ai-workflow/inbox/GUIDE.md"

if [ ! -d "$DONE_DIR" ]; then
  echo "暂无 done/ 目录"
  exit 0
fi

# 收集待归档任务
tasks=()
for f in "$DONE_DIR"/*.md; do
  [ -f "$f" ] || continue
  id="$(basename "$f" .md)"
  status="$(fm_val "$f" status)"
  merged_commit="$(fm_val "$f" merged_commit)"
  merge_target="$(fm_val "$f" merge_target)"

  if [ "$status" = "done" ] && [ -n "$merged_commit" ]; then
    tasks+=("$id|$f|$merged_commit|$merge_target")
  fi
done

if [ ${#tasks[@]} -eq 0 ]; then
  echo "没有符合归档条件的已完成任务（要求 status: done 且有 merged_commit）"
  exit 0
fi

echo "== 待归档任务清单 (${#tasks[@]} 个) =="
for item in "${tasks[@]}"; do
  IFS='|' read -r id f commit target <<< "$item"
  wt_hint="无"
  [ -d ".ai-worktrees/$id" ] && wt_hint=".ai-worktrees/$id"
  br_hint="无"
  git show-ref --verify --quiet "refs/heads/ai/$id" 2>/dev/null && br_hint="ai/$id"

  printf '  [%s] commit: %s, 目标分支: %s\n' "$id" "${commit:0:7}" "${target:-未指定}"
  printf '        worktree: %s | 分支: %s\n' "$wt_hint" "$br_hint"
done
echo

if [ "$MODE" = "plan" ]; then
  say PLAN "以上为归档计划，尚未改动任何文件。确认后加 --apply 执行。"
  exit 0
fi

# 执行归档
mkdir -p "$ARCHIVE_DIR"
archived_count=0
wt_removed=0
br_deleted=0
archived_ids=""

for item in "${tasks[@]}"; do
  IFS='|' read -r id f commit target <<< "$item"

  # 1. 移动任务文件到按日归档目录（.ai-workflow/archive/YYYYMMDD/）
  day_dir="$(echo "$id" | sed -E -n 's/^T-([0-9]{8})-.*/\1/p')"
  [ -z "$day_dir" ] && day_dir="$(date +%Y%m%d)"
  target_archive_dir="$ARCHIVE_DIR/$day_dir"
  mkdir -p "$target_archive_dir"

  mv "$f" "$target_archive_dir/${id}.md"
  archived_count=$((archived_count+1))
  archived_ids="${archived_ids}${id},"
  say ARCHIVE "$id -> $target_archive_dir/${id}.md"

  # 同步更新 HISTORY.md 中的记录（若存在）
  history_file=".ai-workflow/HISTORY.md"
  if [ -f "$history_file" ] && grep -q "\*\*$id\*\*" "$history_file" 2>/dev/null; then
    sed -i.bak -E "s/- \\[[^\\]]+\\] \\*\\*${id}\\*\\*:(.*)/- [done] **${id}**:\1 (merged: ${commit:0:7})/" "$history_file" 2>/dev/null && rm -f "${history_file}.bak" || true
  fi

  # 2. 清理 worktree
  wt_dir=".ai-worktrees/$id"
  if [ -d "$wt_dir" ]; then
    if git worktree remove "$wt_dir" 2>/dev/null; then
      wt_removed=$((wt_removed+1))
      say REMOVE "worktree $wt_dir"
    else
      # 可能是目录已被手动删除或有修改
      git worktree prune 2>/dev/null || true
      if [ -d "$wt_dir" ]; then
        say WARN "worktree $wt_dir 移除失败，保留目录"
      else
        wt_removed=$((wt_removed+1))
        say PRUNE "worktree $wt_dir 已被清理"
      fi
    fi
  fi

  # 3. 删除已合并分支（仅当分支确实合并入 target 时才删除，绝不强删）
  branch_name="ai/$id"
  if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    target_ref="${target:-HEAD}"
    can_delete=0
    if [ -n "$target" ] && git show-ref --verify --quiet "refs/heads/$target" 2>/dev/null; then
      if git merge-base --is-ancestor "refs/heads/$branch_name" "refs/heads/$target" 2>/dev/null; then
        can_delete=1
      fi
    elif git branch --merged 2>/dev/null | grep -qw "$branch_name"; then
      can_delete=1
    fi

    if [ "$can_delete" -eq 1 ]; then
      if git branch -d "$branch_name" 2>/dev/null; then
        br_deleted=$((br_deleted+1))
        say DELETE "分支 $branch_name"
      else
        say WARN "分支 $branch_name 删除失败"
      fi
    else
      say SKIP "分支 $branch_name 尚未合并到 ${target:-当前分支}，保留不删"
    fi
  fi

  # 4. 清理残留锁
  lock_dir=".ai-workflow/.locks/$id"
  if [ -d "$lock_dir" ]; then
    rm -rf "$lock_dir"
    say UNLOCK "清理残留锁 $lock_dir"
  fi
done

if [ -f "$GUIDE_FILE" ] && [ -n "$archived_ids" ]; then
  if ! find .ai-workflow/inbox .ai-workflow/doing .ai-workflow/review \
       -maxdepth 1 -type f -name 'T-*.md' 2>/dev/null | grep -q .; then
    cat > "$GUIDE_FILE" << 'EOF'
<!-- ai-workflow:execution-guide-v1 — 任务池顺序指南；常驻文件，只重建，不删除、不追加历史 -->
# 任务池执行指南

执行摘要：暂无未完成任务。

## 当前顺序

<!--
格式：
1. [并行 P1] T-YYYYMMDD-001
2. [并行 P1] T-YYYYMMDD-002
3. [串行] T-YYYYMMDD-003

规则：
- 行序就是任务池执行顺序；同一并行组可以同时派发，串行任务按行序接力。
- 拆分/入库/任务完成归档时重建本文件，只保留尚未进入 done/ 的任务。
- 不重复任务 ID，不追加历史批次，不复制任务正文。
- 全部任务完成后只清空为「暂无未完成任务」，本文件永久保留。
-->
EOF
    say RESET "任务池指南已清空，文件保留：$GUIDE_FILE"
  else
    guide_tmp="${GUIDE_FILE}.tmp.$$"
    awk -v drop="$archived_ids" '
      BEGIN {
        n = split(drop, ids, ",")
        for (i = 1; i <= n; i++) if (ids[i] != "") dropped[ids[i]] = 1
        in_order = 0
        seq = 0
      }
      /^## 当前顺序/ { in_order = 1; print; next }
      in_order && /^## / { in_order = 0 }
      in_order && /^[0-9]+\. / {
        if (match($0, /T-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]/)) {
          id = substr($0, RSTART, RLENGTH)
          if (id in dropped) next
        }
        seq++
        sub(/^[0-9]+\. /, seq ". ", $0)
      }
      { print }
    ' "$GUIDE_FILE" > "$guide_tmp"

    summary="$(awk '
      /^## 当前顺序/ { f = 1; next }
      f && /^## / { exit }
      f && /^[0-9]+\. / {
        if (!match($0, /\[[^]]+\]/)) next
        tag = substr($0, RSTART, RLENGTH)
        if (!match($0, /T-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]/)) next
        id = substr($0, RSTART, RLENGTH)
        join = (tag ~ /并行/) ? "、" : " → "
        if (!(tag in seen)) { seen[tag] = 1; order[++n] = tag }
        vals[tag] = vals[tag] (vals[tag] == "" ? "" : join) id
      }
      END {
        for (i = 1; i <= n; i++) {
          tag = order[i]
          printf "%s%s: %s", (i == 1 ? "" : "；"), tag, vals[tag]
        }
        if (n > 0) printf "。"
      }
    ' "$guide_tmp")"

    if [ -n "$summary" ]; then
      awk -v summary="$summary" '
        /^执行摘要：/ { print "执行摘要：" summary; next }
        { print }
      ' "$guide_tmp" > "${guide_tmp}.2"
      mv "${guide_tmp}.2" "$guide_tmp"
    fi
    mv "$guide_tmp" "$GUIDE_FILE"
    say GUIDE "任务池指南已移除归档任务并重排：$GUIDE_FILE"
  fi
fi

echo
say DONE "归档完成：归档任务 ${archived_count} 个，移除 worktree ${wt_removed} 个，删除已合并分支 ${br_deleted} 个"
