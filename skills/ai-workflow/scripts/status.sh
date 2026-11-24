#!/usr/bin/env bash
# status.sh <仓库根目录> — 任务总览：统计各目录/状态的任务数量（只读）
set -uo pipefail
T="${1:-.}"; cd "$T" || { echo "目录不存在：$T" >&2; exit 1; }

# 从 front-matter 提取 status 值
fm_status() {
  awk '
    /^---$/ { n++; next }
    n==1 && /^status:/ { sub("^status:[ ]*", ""); print; exit }
  ' "$1"
}

total=0
output=""

for dir in inbox doing review done; do
  dir_path=".ai-workflow/$dir"
  count=0
  status_list=""

  if [ -d "$dir_path" ]; then
    for f in "$dir_path"/*.md; do
      [ -f "$f" ] || continue
      count=$((count+1))
      s="$(fm_status "$f")"
      [ -z "$s" ] && s="(空)"
      status_list="${status_list}${s}"$'\n'
    done
  fi

  total=$((total+count))
  output="${output}  ${dir}:$(printf '%*s' $((9 - ${#dir})) '')${count} 个任务"$'\n'

  if [ "$count" -gt 0 ]; then
    # 用 sort | uniq -c 统计各 status 出现次数，拼成一行
    detail="$(printf '%s' "$status_list" | sort | uniq -c | awk '{printf "%s: %s    ", $2, $1}' | sed 's/    $//')"
    output="${output}$(printf '%13s' '')${detail}"$'\n'
  fi
done

if [ "$total" -eq 0 ]; then
  echo "暂无任务"
  exit 0
fi

echo "ai-workflow 任务总览"
echo
printf '%s' "$output"
echo "  ─────────────────"
echo "  共 ${total} 个任务"
