#!/usr/bin/env bash
# scripts/ai-workflow.sh — ai-workflow 任务池脚本（手动会话与 claude -p 共用）
#
# 设计原则：
#   - 任务由人手写；脚本只做“领取 / 暂停讨论 / 恢复 / 送审 / 审查批准 / 归档”
#   - 任务锁是 mkdir 原子锁：手动会话与 claude -p 不能同时写同一个任务
#   - 代码只在独立 worktree（分支 ai/<id>）里改，不自动合并、不 push、不删 worktree
#   - 脚本不自动提交任务状态；需要版本化任务文件时由人决定
#   - 重要歧义进 discussion/（needs-discussion），方案版本 + sha 批准后才可恢复
#   - review -> approved -> done 分开：审查通过不等于合并，归档必须有合并证据
#
# 用法（在仓库任意目录执行）：
#   ai-workflow.sh next
#   ai-workflow.sh claim <id> [--by 名字] [--force]
#   ai-workflow.sh pause <id> --reason "为什么需要讨论"
#   ai-workflow.sh plan-seal <id> [--version N]
#   ai-workflow.sh approve <id> --version N --by 名字 --note "用户批准原话"
#   ai-workflow.sh resume <id> [--force]
#   ai-workflow.sh review <id>
#   ai-workflow.sh approve-review <id> --commit SHA --by 名字 --note "审查结论"
#   ai-workflow.sh done <id> --target 分支 --merged-commit SHA --by 名字 --note "合并确认" [--method merge|squash|rebase]
#   ai-workflow.sh done <id> --no-code --by 名字 --note "确认无代码改动"
#   ai-workflow.sh reject <id> [--reason "原因"]
#   ai-workflow.sh block <id> --reason "原因"
#   ai-workflow.sh release <id>
#   ai-workflow.sh check
#   DRY_RUN=1 ai-workflow.sh run      # 可选：claude -p 无人值守，只处理一个任务

set -euo pipefail

AI_WORKFLOW_VERSION="1"

ORIG_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf '[ai-workflow][error] 当前目录不在 git 仓库内\n' >&2; exit 1; }
ORIG_BRANCH="$(git -C "$ORIG_TOP" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
MAIN_ROOT="$(git -C "$ORIG_TOP" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}')"
MAIN_ROOT="$(cd "$MAIN_ROOT" && pwd -P)"
AI_DIR="${AI_DIR:-.ai-workflow}"
cd "$MAIN_ROOT"
mkdir -p "$AI_DIR"

if [ -f "$AI_DIR/config.env" ]; then
  # shellcheck disable=SC1090
  . "$AI_DIR/config.env"
fi

BASE_REF="${BASE_REF:-}"
REVIEW_LIMIT="${REVIEW_LIMIT:-3}"
MAX_ATTEMPTS_DEFAULT="${MAX_ATTEMPTS_DEFAULT:-2}"
WORKTREE_ROOT="${WORKTREE_ROOT:-$AI_DIR/worktrees}"
LOCK_ROOT="${LOCK_ROOT:-$AI_DIR/locks}"
LOG_ROOT="${LOG_ROOT:-$AI_DIR/logs}"
LOCK_STALE_MINUTES="${LOCK_STALE_MINUTES:-120}"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CLAUDE_MODEL="${CLAUDE_MODEL:-}"
MAX_TURNS="${MAX_TURNS:-}"
MAX_BUDGET_USD="${MAX_BUDGET_USD:-3}"
BASE_TOOLS="Read,Edit,Write,Glob,Grep,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git status *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(ls *),Bash(mkdir *)"
PROJECT_TOOLS="${PROJECT_TOOLS:-}"
WORKTREE_SETUP="${WORKTREE_SETUP:-}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-$BASE_TOOLS${PROJECT_TOOLS:+,$PROJECT_TOOLS}}"
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-Bash(git push *),Bash(git merge *),Bash(git reset --hard *),Bash(git checkout main *),Bash(git checkout master *),Bash(git worktree *),Bash(gh *),Bash(rm -rf *)}"
DRY_RUN="${DRY_RUN:-0}"
CLAIMED_BY="${CLAIMED_BY:-ai-workflow-run-$(date +%Y%m%d-%H%M%S)}"

TASK_DIRS="inbox discussion doing review approved done blocked"
mkdir -p "$AI_DIR"/{inbox,discussion,doing,review,approved,done,blocked} "$LOCK_ROOT" "$LOG_ROOT" "$WORKTREE_ROOT"

CURRENT_TASK_LOCK=""
CURRENT_TASK_ID=""
KEEP_TASK_LOCK=0      # 手动会话 claim 成功后要跨命令持锁；脚本模式不保留
GLOBAL_LOCK_HELD=0

log()  { printf '[ai-workflow] %s\n' "$*"; }
warn() { printf '[ai-workflow][warn] %s\n' "$*" >&2; }
die()  { printf '[ai-workflow][error] %s\n' "$*" >&2; exit 1; }

now() { date '+%Y-%m-%d %H:%M:%S'; }
stamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else printf 'sha256-unavailable'; fi
}

release_current_lock() {
  if [ -n "$CURRENT_TASK_LOCK" ]; then
    rm -rf "$CURRENT_TASK_LOCK" 2>/dev/null || true
    CURRENT_TASK_LOCK=""
  fi
}

release_lock_by_id() { # 手动会话的锁跨进程存在，命令结束时按 id 释放
  [ -n "${1:-}" ] || return 0
  rm -rf "$(lock_dir "$1")" 2>/dev/null || true
}

release_global_lock() {
  if [ "$GLOBAL_LOCK_HELD" = "1" ]; then
    rm -f "$LOCK_ROOT/loop.lock/pid" 2>/dev/null || true
    rmdir "$LOCK_ROOT/loop.lock" 2>/dev/null || true
    GLOBAL_LOCK_HELD=0
  fi
}

cleanup() {
  [ "$KEEP_TASK_LOCK" = "1" ] || release_current_lock
  release_global_lock
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------
# front-matter
# ------------------------------------------------------------------
fm_get() { # $1 文件, $2 key
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 {
      sub("^[^:]*:[ \t]*", "")
      sub("^#.*$", "")
      sub("[ \t]+#.*$", "")
      sub("[ \t]+$", "")
      print; exit
    }
  ' "$1"
}

fm_set() { # $1 文件, $2 key, $3 value；key 不存在就插在结束的 --- 之前
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/aiwf-fm.XXXXXX")"
  awk -v k="$key" -v v="$value" '
    BEGIN { in_fm = 0; replaced = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; print; next }
    in_fm && $0 == "---" {
      if (!replaced) { print k ": " v; replaced = 1 }
      in_fm = 0; print; next
    }
    in_fm && !replaced && index($0, k ":") == 1 { print k ": " v; replaced = 1; next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

append_record() { # $1 文件, $2 文本
  printf '\n%s\n' "$2" >> "$1"
}

to_int() {
  case "${1:-}" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$1" ;;
  esac
}

normalize_risk() {
  case "${1:-}" in
    low) echo low ;;
    *)   echo high ;;
  esac
}

# 取一个二级标题下的正文；去掉行尾空白和首尾空行，供 sha256 使用
section_body() { # $1 文件, $2 标题（例如 "## 方案"）
  awk -v h="$2" '
    $0 == h { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$1" | sed 's/[[:space:]]*$//' | awk '
    { line[NR] = $0 }
    END {
      first = 1; last = NR
      while (first <= last && line[first] == "") first++
      while (last >= first && line[last] == "") last--
      for (i = first; i <= last; i++) print line[i]
    }
  '
}

section_hash() { section_body "$1" "$2" | sha256; }

section_nonempty() {
  [ -n "$(section_body "$1" "$2" | sed '/^[[:space:]]*$/d')" ]
}

# ------------------------------------------------------------------
# 任务定位与迁移（只 mv，不 git add / commit）
# ------------------------------------------------------------------
find_task() { # $1 id -> 唯一路径；0 个或多个时返回 1
  local id="$1" d hits=()
  case "$id" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  for d in $TASK_DIRS; do
    [ -f "$AI_DIR/$d/$id.md" ] && hits+=("$AI_DIR/$d/$id.md")
  done
  [ "${#hits[@]}" -eq 1 ] || return 1
  printf '%s\n' "${hits[0]}"
}

task_dir() { basename "$(dirname "$1")"; }
task_id() { basename "$1" .md; }

move_task() { # $1 源文件, $2 目标目录, $3 新 status
  local src="$1" dest="$AI_DIR/$2/$(task_id "$1").md"
  [ -e "$dest" ] && die "目标已存在：${dest}（不覆盖）"
  fm_set "$src" status "$3"
  mv "$src" "$dest"
}

review_count() {
  find "$AI_DIR/review" "$AI_DIR/approved" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

list_new_candidates() {
  local f status priority created
  for f in "$AI_DIR"/inbox/*.md; do
    [ -f "$f" ] || continue
    status="$(fm_get "$f" status)"
    [ "$status" = "new" ] || continue
    priority="$(fm_get "$f" priority)"; [ -n "$priority" ] || priority="P9"
    created="$(fm_get "$f" created)"; [ -n "$created" ] || created="9999-99-99"
    printf '%s\t%s\t%s\n' "$priority" "$created" "$f"
  done | sort -t $'\t' -k1,1 -k2,2 -k3,3
}

task_summary() { # $1 文件
  printf '%s\t%s\t%s\t%s\n' "$(task_id "$1")" "$(fm_get "$1" priority)" \
    "$(fm_get "$1" created)" "$(fm_get "$1" title)"
}

# ------------------------------------------------------------------
# 锁
# ------------------------------------------------------------------
lock_dir() { printf '%s/%s\n' "$LOCK_ROOT" "$1"; }

write_owner() { # $1 锁目录, $2 kind, $3 by
  {
    printf 'kind=%s\n' "$2"
    printf 'by=%s\n' "$3"
    printf 'pid=%s\n' "$$"
    printf 'created=%s\n' "$(stamp)"
  } > "$1/owner"
}

owner_field() { # $1 锁目录, $2 字段
  [ -f "$1/owner" ] || return 0
  grep -m1 "^$2=" "$1/owner" 2>/dev/null | cut -d= -f2- || true
}

is_old() { # $1 路径
  [ -n "$(find "$1" -maxdepth 0 -mmin +"$LOCK_STALE_MINUTES" -print -quit 2>/dev/null)" ]
}

pid_alive() {
  case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) kill -0 "$1" 2>/dev/null ;; esac
}

# 只自动清理“脚本模式且进程已退出且超过阈值”的锁；
# 手动会话的锁（kind=session）可能是跨轮次持锁，必须由人 release。
cleanup_stale_run_lock() { # $1 锁目录
  [ -d "$1" ] || return 1
  [ "$(owner_field "$1" kind)" = "run" ] || return 1
  pid_alive "$(owner_field "$1" pid)" && return 1
  is_old "$1" || return 1
  warn "清理残留的脚本锁（进程已退出且超过 ${LOCK_STALE_MINUTES} 分钟）：$1"
  rm -rf "$1"
  return 0
}

cleanup_stale_run_locks() {
  local d
  for d in "$LOCK_ROOT"/*; do
    [ -d "$d" ] || continue
    [ "$(basename "$d")" = "loop.lock" ] && continue
    cleanup_stale_run_lock "$d" || true
  done
}

acquire_task_lock() { # $1 id, $2 kind, $3 by -> 设置 CURRENT_TASK_LOCK
  local id="$1" kind="$2" by="$3" lock
  lock="$(lock_dir "$id")"
  if mkdir "$lock" 2>/dev/null; then
    write_owner "$lock" "$kind" "$by"
    CURRENT_TASK_LOCK="$lock"; CURRENT_TASK_ID="$id"
    return 0
  fi
  if cleanup_stale_run_lock "$lock"; then
    if mkdir "$lock" 2>/dev/null; then
      write_owner "$lock" "$kind" "$by"
      CURRENT_TASK_LOCK="$lock"; CURRENT_TASK_ID="$id"
      return 0
    fi
  fi
  return 1
}

describe_lock() { # $1 锁目录
  printf 'kind=%s by=%s pid=%s created=%s' \
    "$(owner_field "$1" kind)" "$(owner_field "$1" by)" \
    "$(owner_field "$1" pid)" "$(owner_field "$1" created)"
}

acquire_global_lock() {
  local lock="$LOCK_ROOT/loop.lock"
  if mkdir "$lock" 2>/dev/null; then
    GLOBAL_LOCK_HELD=1; printf '%s\n' "$$" > "$lock/pid"; return 0
  fi
  if is_old "$lock" && ! pid_alive "$(cat "$lock/pid" 2>/dev/null || true)"; then
    warn "清理过期的全局锁（>${LOCK_STALE_MINUTES} 分钟）：$lock"
    rm -f "$lock/pid" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
    if mkdir "$lock" 2>/dev/null; then
      GLOBAL_LOCK_HELD=1; printf '%s\n' "$$" > "$lock/pid"; return 0
    fi
  fi
  return 1
}

# ------------------------------------------------------------------
# worktree
# ------------------------------------------------------------------
worktree_path() { printf '%s/%s/%s\n' "$MAIN_ROOT" "${WORKTREE_ROOT#/}" "$1"; }

registered_worktree_for_branch() { # $1 id -> 已注册 worktree 路径（可能空）
  local branch="refs/heads/ai/$1"
  git -C "$MAIN_ROOT" worktree list --porcelain | awk -v br="$branch" '
    /^worktree / { path = substr($0, 10) }
    /^branch / { if ($0 == "branch " br) print path }
  '
}

# 解析或创建任务 worktree。只读输出路径到 stdout，说明写 stderr。
ensure_worktree() { # $1 id, $2 create(1/0)
  local id="$1" create="${2:-1}" branch="ai/$id" wt existing base base_commit
  wt="$(worktree_path "$id")"

  # 会话已经在任务 worktree 里：核验后直接用，不嵌套创建
  if [ "$ORIG_BRANCH" = "$branch" ] && [ "$ORIG_TOP" != "$MAIN_ROOT" ]; then
    existing="$(cd "$ORIG_TOP" && pwd -P)"
    if [ "$(git -C "$existing" rev-parse --abbrev-ref HEAD 2>/dev/null)" != "$branch" ]; then
      die "当前 worktree 分支已变化，无法确定为任务 $id 的工作区：$existing"
    fi
    if [ "$(cd "$existing" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" \
       != "$(cd "$MAIN_ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]; then
      die "当前目录不在同一个仓库的 worktree 里，拒绝复用：$existing"
    fi
    log "已处于任务 worktree：$existing" >&2
    printf '%s\n' "$existing"; return 0
  fi
  if [ "$ORIG_BRANCH" = "$branch" ] && [ "$ORIG_TOP" = "$MAIN_ROOT" ]; then
    die "主 checkout 当前在任务分支 ${branch}。请先切回基准分支，再运行本命令；不要在主 checkout 上跑任务。"
  fi

  existing="$(registered_worktree_for_branch "$id")"
  if [ -n "$existing" ]; then
    if [ -d "$existing" ]; then
      log "复用已有 worktree：${existing}（分支 ${branch}）" >&2
      printf '%s\n' "$existing"; return 0
    fi
    warn "git 记录了 $branch 的 worktree，但目录不存在：${existing}（先 git worktree prune）" >&2
  fi

  if [ -e "$wt" ]; then
    die "worktree 目录已存在但不是 git 记录的 $branch 工作区：${wt}。请人工确认，不嵌套创建、不删除。"
  fi

  [ "$create" = "1" ] || { printf '%s\n' "$wt"; return 0; }

  base="$(fm_get "$(find_task "$id")" base_ref)"
  [ -n "$base" ] || base="$BASE_REF"
  if [ -z "$base" ]; then
    base_commit="$(git -C "$MAIN_ROOT" rev-parse HEAD)"
    log "未指定 base_ref / BASE_REF，使用主 checkout 当前 HEAD：$base_commit" >&2
  else
    base_commit="$(git -C "$MAIN_ROOT" rev-parse --verify "$base^{commit}" 2>/dev/null)" \
      || die "base 不是有效分支或提交：$base"
  fi

  if git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    log "复用已有分支 $branch" >&2
    git -C "$MAIN_ROOT" worktree add "$wt" "$branch" >/dev/null 2>&1 \
      || die "git worktree add 失败（分支可能已被其他 worktree 占用）：$branch"
  else
    git -C "$MAIN_ROOT" worktree add "$wt" -b "$branch" "$base_commit" >/dev/null 2>&1 \
      || die "git worktree add 失败：${wt}（$branch from ${base_commit}）"
  fi
  printf '%s\n' "$wt"
}

record_worktree() { # $1 任务文件, $2 id, $3 worktree 路径
  local task="$1" id="$2" wt="$3" rel ref base_commit
  rel="$wt"; case "$wt" in "$MAIN_ROOT"/*) rel="${wt#"$MAIN_ROOT"/}" ;; esac
  fm_set "$task" worktree "$rel"
  [ -n "$(fm_get "$task" base_commit)" ] && return 0
  # 复用已有分支/worktree 时不能把当前 HEAD 当基准，否则已有提交会被算成 0
  ref="$(fm_get "$task" base_ref)"; [ -n "$ref" ] || ref="$BASE_REF"
  if [ -n "$ref" ]; then
    base_commit="$(git -C "$wt" merge-base HEAD "$ref" 2>/dev/null || true)"
  else
    base_commit="$(git -C "$wt" merge-base HEAD "$(git -C "$MAIN_ROOT" rev-parse HEAD)" 2>/dev/null || true)"
  fi
  [ -n "$base_commit" ] || base_commit="$(git -C "$wt" rev-parse HEAD)"
  fm_set "$task" base_commit "$base_commit"
}

# ------------------------------------------------------------------
# 方案批准
# ------------------------------------------------------------------
approval_problem() { # $1 任务文件 -> 空 = 批准有效；否则输出原因
  local task="$1" pv av ph ah cur
  pv="$(fm_get "$task" plan_version)"; av="$(fm_get "$task" approved_version)"
  ph="$(fm_get "$task" plan_sha256)"; ah="$(fm_get "$task" approved_plan_sha256)"
  [ -n "$(section_body "$task" "## 方案" | sed '/^[[:space:]]*$/d')" ] || { echo "任务没有填写「## 方案」"; return; }
  [ -n "$ph" ] || { echo "方案尚未封存：先运行 plan-seal"; return; }
  [ -n "$av" ] || { echo "方案尚未获得用户批准：先由用户明确批准，再运行 approve"; return; }
  [ "$av" = "$pv" ] || { echo "批准版本 ${av} 与当前方案版本 ${pv} 不一致"; return; }
  cur="$(section_hash "$task" "## 方案")"
  [ "$ph" = "$cur" ] || { echo "plan_sha256 与当前方案内容不一致：方案改过但未重新 plan-seal"; return; }
  [ "$ah" = "$cur" ] || { echo "方案内容已变化，旧批准失效（批准 sha ${ah}，当前 ${cur}）"; return; }
  [ -n "$(fm_get "$task" approved_by)" ] || { echo "批准记录缺少 approved_by"; return; }
  [ -n "$(fm_get "$task" approved_note)" ] || { echo "批准记录缺少用户原话（approved_note）"; return; }
}

# ------------------------------------------------------------------
# 子命令：只读
# ------------------------------------------------------------------
cmd_next() {
  local c d
  c="$(list_new_candidates)"
  if [ -n "$c" ]; then
    log "可领取的 status: new 任务（priority / created / path）"
    printf '%s\n' "$c"
  else
    log "没有 status: new 的任务"
  fi
  for d in discussion; do
    for f in "$AI_DIR/$d"/*.md; do
      [ -f "$f" ] || continue
      printf '等待讨论（不会被自动领取）：%s\n' "$(task_summary "$f")"
    done
  done
}

cmd_check() {
  local bad=0 spec dir allowed f st id problem
  for spec in inbox:new,example discussion:needs-discussion doing:claimed \
              review:needs_review approved:review_approved done:done blocked:blocked; do
    dir="${spec%%:*}"; allowed="${spec#*:}"
    for f in "$AI_DIR/$dir"/*.md; do
      [ -f "$f" ] || continue
      st="$(fm_get "$f" status)"
      case ",$allowed," in
        *",$st,"*) ;;
        *) warn "状态与目录不一致：${f}（status=${st:-空}，$dir/ 应为 ${allowed}）"; bad=1 ;;
      esac
      id="$(task_id "$f")"
      if [ "$st" != "example" ] && [ "$(fm_get "$f" id)" != "$id" ]; then
        warn "id 与文件名不一致：${f}（id=$(fm_get "$f" id)）"; bad=1
      fi
      local dd cnt=0
      for dd in $TASK_DIRS; do [ -e "$AI_DIR/$dd/$id.md" ] && cnt=$((cnt+1)); done
      if [ "$cnt" -gt 1 ]; then
        warn "同一个 id 出现在多个目录：${id}（${cnt} 处），不覆盖，需人工处理"; bad=1
      fi
      if [ "$dir" = "discussion" ] && [ -n "$(fm_get "$f" approved_plan_sha256)" ]; then
        problem="$(approval_problem "$f")"
        [ -z "$problem" ] || { warn "讨论任务的批准已失效：${f}（${problem}）"; bad=1; }
      fi
      if [ "$dir" = "approved" ]; then
        [ -n "$(fm_get "$f" review_approved_commit)" ] \
          || { warn "approved/ 任务缺少 review_approved_commit：${f}"; bad=1; }
      fi
      if [ "$dir" = "done" ]; then
        if [ -z "$(fm_get "$f" merged_commit)" ] \
           && [ "$(fm_get "$f" review_approved_commit)" != "none" ]; then
          if [ -n "$(fm_get "$f" review_approved_commit)" ]; then
            warn "done/ 任务缺少合并证据（merged_commit），但存在审查批准记录：${f}"; bad=1
          else
            warn "done/ 旧任务没有合并证据（merged_commit）：${f}。请人工复核，脚本不自动改写。"
          fi
        fi
      fi
    done
  done
  [ "$bad" = "0" ] && log "check 通过" || exit 1
}

# ------------------------------------------------------------------
# 子命令：领取 / 暂停 / 恢复
# ------------------------------------------------------------------
cmd_claim() {
  local id="${1:-}" by="manual-session-$(date +%Y%m%d-%H%M%S)" force=0 task dir st wt problem
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --by) by="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh claim <id> [--by 名字] [--force]"
  case "$id" in *[!A-Za-z0-9._-]*) die "非法任务 id：$id" ;; esac
  [ -e "$AI_DIR/doing/$id.md" ] && die "doing/ 已存在同名任务：$AI_DIR/doing/$id.md（不覆盖）"
  task="$(find_task "$id")" || die "找不到唯一的任务文件：${id}（检查 inbox/discussion/doing/review/approved/done/blocked）"
  dir="$(task_dir "$task")"; st="$(fm_get "$task" status)"

  case "$dir:$st" in
    inbox:new) ;;
    discussion:needs-discussion)
      problem="$(approval_problem "$task")"
      [ -z "$problem" ] || die "等待讨论的任务不能直接恢复：$problem" ;;
    *) die "任务 $id 当前在 ${dir}/（status=${st}），不可领取" ;;
  esac

  if [ "$force" != "1" ] && [ "$(review_count)" -ge "$REVIEW_LIMIT" ]; then
    die "review/ + approved/ 已有 $(review_count) 个待处理任务（上限 ${REVIEW_LIMIT}）。先完成人工审查，或确认后再加 --force。"
  fi

  if ! acquire_task_lock "$id" "session" "$by"; then
    die "任务 $id 已被占用：$(describe_lock "$(lock_dir "$id")")。确认无人使用后运行：ai-workflow.sh release $id"
  fi

  mv "$task" "$AI_DIR/doing/$id.md"
  fm_set "$AI_DIR/doing/$id.md" status "claimed"
  fm_set "$AI_DIR/doing/$id.md" claimed_by "$by"
  fm_set "$AI_DIR/doing/$id.md" claimed_at "$(stamp)"

  if ! wt="$(ensure_worktree "$id" 1)"; then
    fm_set "$AI_DIR/doing/$id.md" status "$st"
    mv "$AI_DIR/doing/$id.md" "$task"
    release_current_lock
    die "worktree 准备失败，任务已退回：$task"
  fi
  record_worktree "$AI_DIR/doing/$id.md" "$id" "$wt"
  KEEP_TASK_LOCK=1
  log "已领取 ${id}（${by}）"
  log "任务文件：$AI_DIR/doing/$id.md"
  log "worktree：${wt}（分支 ai/${id}）"
  log "先做只读探索；有重要歧义就填「## 讨论」后运行 pause，不要先改业务代码。"
}

cmd_pause() {
  local id="${1:-}" reason="" task wt commits dirty files diffstat
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh pause <id> --reason \"为什么需要讨论\""
  [ -n "$reason" ] || die "必须写 --reason：让用户知道为什么停下"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "doing" ] || die "只有 doing/ 的任务可以暂停讨论（当前：$(task_dir "$task")）"
  section_nonempty "$task" "## 讨论" \
    || die "先在任务文件填写「## 讨论」：已确认事实（含文件证据）、待决问题、可选方案与影响、建议方案（标为建议）、用户下一步。"

  wt="$(fm_get "$task" worktree)"
  case "$wt" in ''|/*) ;; *) wt="$MAIN_ROOT/$wt" ;; esac
  commits=0; dirty=0; files=""; diffstat=""
  if [ -n "$wt" ] && [ -d "$wt" ]; then
    commits="$(git -C "$wt" rev-list --count "$(fm_get "$task" base_commit)..HEAD" 2>/dev/null || echo 0)"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    files="$(git -C "$wt" status --porcelain 2>/dev/null | head -30 | sed 's/^/  - /')"
    diffstat="$(git -C "$wt" diff --stat 2>/dev/null | tail -20)"
  fi

  append_record "$task" "### 暂停记录（$(now)）

- 原因：$reason
- worktree：${wt:-（尚无）}
- 分支：ai/$id
- 已提交改动：${commits} 个提交（base_commit..HEAD）
- 未提交改动：${dirty} 项
- 改动文件：
${files:-（无）}
- 已验证项：见任务「## 验证记录」；本命令不判定验证真假，也不改写已有记录。
- diffstat：
\`\`\`
${diffstat:-（无）}
\`\`\`
- 说明：本命令不 reset、不删除 worktree/提交/diff。恢复前需用户批准当前方案版本。"

  fm_set "$task" paused_at "$(stamp)"
  fm_set "$task" status "needs-discussion"
  mv "$task" "$AI_DIR/discussion/$id.md"
  release_current_lock
  release_lock_by_id "$id"
  log "任务 $id 进入 discussion/（needs-discussion），不会被自动再次领取。"
  log "已有 worktree/提交/diff 均保留：${wt:-（无）}"
  log "下一步：用户补全方案 → plan-seal → 用户明确批准 → approve → 用户要求恢复时运行 resume。"
}

cmd_plan_seal() {
  local id="${1:-}" version="" task pv old_hash new_hash
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) version="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh plan-seal <id> [--version N]"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "discussion" ] || die "plan-seal 只用于 discussion/ 中的任务"
  section_nonempty "$task" "## 方案" || die "先填写「## 方案」，再封存版本"
  pv="$(fm_get "$task" plan_version)"
  [ -n "$version" ] || version="${pv:-1}"
  case "$version" in ''|*[!0-9]*) die "方案版本必须是正整数：$version" ;; esac
  [ "$version" -ge 1 ] || die "方案版本必须 >= 1"

  new_hash="$(section_hash "$task" "## 方案")"
  old_hash="$(fm_get "$task" plan_sha256)"
  if [ -n "$old_hash" ] && [ "$old_hash" != "$new_hash" ] \
     && [ -n "$(fm_get "$task" approved_plan_sha256)" ]; then
    fm_set "$task" approved_version ""
    fm_set "$task" approved_plan_sha256 ""
    fm_set "$task" approved_by ""
    fm_set "$task" approved_at ""
    fm_set "$task" approved_note ""
    warn "方案内容变化，旧批准已自动失效（需重新由用户批准）。"
  fi
  fm_set "$task" plan_version "$version"
  fm_set "$task" plan_sha256 "$new_hash"
  log "已封存方案版本 ${version}：sha256=$new_hash"
  log "只封存不等于批准；需要用户明确说「批准版本 ${version}」后运行 approve。"
}

cmd_approve() {
  local id="${1:-}" version="" by="" note="" task cur pv
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) version="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      --note) note="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh approve <id> --version N --by 名字 --note \"用户批准原话\""
  [ -n "$version" ] && [ -n "$by" ] && [ -n "$note" ] \
    || die "approve 必须同时给 --version、--by、--note（用户明确批准的原话）"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "discussion" ] || die "approve 只用于 discussion/ 中的任务"
  pv="$(fm_get "$task" plan_version)"
  [ "$version" = "$pv" ] || die "批准版本 $version 与当前方案版本 ${pv:-未设置} 不一致"
  [ -n "$(fm_get "$task" plan_sha256)" ] || die "方案未封存，先运行 plan-seal"
  cur="$(section_hash "$task" "## 方案")"
  [ "$(fm_get "$task" plan_sha256)" = "$cur" ] \
    || die "方案内容与封存值不一致：先重新 plan-seal，再请用户批准新版本"

  fm_set "$task" approved_version "$version"
  fm_set "$task" approved_plan_sha256 "$cur"
  fm_set "$task" approved_by "$by"
  fm_set "$task" approved_at "$(stamp)"
  fm_set "$task" approved_note "$note"
  append_record "$task" "### 方案批准（$(now)）

- 批准版本：$version
- 方案 sha256：$cur
- 批准人：$by
- 用户原话：$note
- 说明：只记录用户对上述版本与内容的明确批准；方案再改动即失效。"
  log "已记录用户对方案版本 $version 的批准（sha256=${cur}）"
  log "用户明确要求恢复后，运行 resume ${id}。"
}

cmd_resume() {
  local id="${1:-}" force=0
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh resume <id> [--force]"
  if [ "$force" = "1" ]; then cmd_claim "$id" --force
  else cmd_claim "$id"; fi
}

# ------------------------------------------------------------------
# 子命令：实现完成 -> 审查 -> 批准 -> 合并归档
# ------------------------------------------------------------------
cmd_review() {
  local id="${1:-}" task wt base head commits dirty risk diffstat
  [ -n "$id" ] || die "用法：ai-workflow.sh review <id>"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "doing" ] || die "只有 doing/ 的任务可以送入 review（当前：$(task_dir "$task")）"
  wt="$(fm_get "$task" worktree)"
  case "$wt" in ''|/*) ;; *) wt="$MAIN_ROOT/$wt" ;; esac
  [ -n "$wt" ] && [ -d "$wt" ] || die "任务没有可用的 worktree 记录：$id"
  [ "$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "ai/$id" ] \
    || die "worktree 当前不在分支 ai/${id}：$wt"
  base="$(fm_get "$task" base_commit)"; [ -n "$base" ] || base="$(git -C "$wt" rev-parse HEAD)"
  head="$(git -C "$wt" rev-parse HEAD)"
  commits="$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)"
  dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  risk="$(normalize_risk "$(fm_get "$task" risk)")"
  [ "$dirty" -eq 0 ] || die "worktree 还有 $dirty 处未提交改动：先提交或明确记录，再送审"
  if [ "$risk" = "low" ]; then
    [ "$commits" -gt 0 ] || die "risk low 但没有新 commit：实现未完成，不能送审"
  else
    [ "$commits" -eq 0 ] || die "risk high 只允许出方案，但分支有 $commits 个 commit"
  fi
  section_nonempty "$task" "## 验证记录" \
    || die "先在「## 验证记录」写下真实命令、执行目录、退出码和结果（未验证的写「未验证」）"
  diffstat="$(git -C "$wt" diff --stat "$base..HEAD" 2>/dev/null | tail -20)"
  append_record "$task" "### 实现完成，等待人工审查（$(now)）

- 分支：ai/$id
- commit：$head
- 新增提交：$commits
- worktree：$wt
- 未提交改动：0
- diffstat：
\`\`\`
${diffstat:-（无）}
\`\`\`
- 说明：实现完成 + 验证记录由执行方填写；本步骤不等于验证通过，也不等于审查通过。"

  if [ "$commits" -gt 0 ]; then fm_set "$task" review_commit "$head"
  else fm_set "$task" review_commit "none"; fi
  fm_set "$task" status "needs_review"
  mv "$task" "$AI_DIR/review/$id.md"
  release_current_lock
  release_lock_by_id "$id"
  log "任务 $id -> review/（needs_review）。没有合并、没有 push。"
  log "人工审查：git diff ${base}...ai/${id}；通过后运行 approve-review。"
}

cmd_approve_review() {
  local id="${1:-}" commit="" by="" note="" task wt head base commits
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --commit) commit="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      --note) note="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh approve-review <id> --commit SHA --by 名字 --note \"审查结论\""
  [ -n "$by" ] && [ -n "$note" ] || die "approve-review 必须给 --by 和 --note"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "review" ] || die "只有 review/ 的任务可以审查批准（当前：$(task_dir "$task")）"

  if [ "$(fm_get "$task" review_commit)" = "none" ]; then
    [ "$commit" = "none" ] || die "该任务无代码改动，--commit 必须写 none"
  else
    [ -n "$commit" ] || die "必须指定审查的 commit：--commit <sha>"
    git -C "$MAIN_ROOT" cat-file -e "$commit^{commit}" 2>/dev/null || die "commit 不存在：$commit"
    wt="$(fm_get "$task" worktree)"; case "$wt" in ''|/*) ;; *) wt="$MAIN_ROOT/$wt" ;; esac
    [ -n "$wt" ] && [ -d "$wt" ] || die "worktree 不存在，无法核对审查对象：$id"
    head="$(git -C "$wt" rev-parse HEAD)"
    [ "$head" = "$commit" ] || die "分支 HEAD（${head}）与审查 commit（${commit}）不一致：审查后代码又变了，旧审查不能沿用"
    [ "$(fm_get "$task" review_commit)" = "$commit" ] || die "commit 与送审记录不一致"
    base="$(fm_get "$task" base_commit)"; commits="$(git -C "$wt" rev-list --count "$base..HEAD")"
    [ "$commits" -gt 0 ] || die "分支没有新提交"
  fi

  fm_set "$task" review_approved_commit "$commit"
  fm_set "$task" review_approved_by "$by"
  fm_set "$task" review_approved_at "$(stamp)"
  fm_set "$task" review_approved_note "$note"
  append_record "$task" "### 人工审查通过（$(now)）

- 审查对象 commit：$commit
- 审查人：$by
- 结论：$note
- 说明：审查通过 **不等于** 已合并。合并必须由人执行，之后用 done 写入合并证据。"

  fm_set "$task" status "review_approved"
  mv "$task" "$AI_DIR/approved/$id.md"
  log "审查已记录：$id -> approved/（review_approved）。尚未合并，不会自动 done。"
  log "人工合并后：ai-workflow.sh done $id --target <分支> --merged-commit <SHA> --by <名字> --note \"已合并确认\""
}

cmd_done() {
  local id="${1:-}" target="" merged="" by="" note="" method="merge" no_code=0
  local task approved branch_sha approved_ancestor target_sha merged_sha
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --target) target="${2:-}"; shift 2 ;;
      --merged-commit) merged="${2:-}"; shift 2 ;;
      --by) by="${2:-}"; shift 2 ;;
      --note) note="${2:-}"; shift 2 ;;
      --method) method="${2:-}"; shift 2 ;;
      --no-code) no_code=1; shift ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] && [ -n "$by" ] && [ -n "$note" ] \
    || die "用法：ai-workflow.sh done <id> --by 名字 --note \"人工确认\" [--target 分支 --merged-commit SHA --method merge|squash|rebase]"
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "approved" ] \
    || die "done 只接受 approved/ 的任务；先完成人工审查批准（审核通过不能直接 done）"
  approved="$(fm_get "$task" review_approved_commit)"
  [ -n "$approved" ] || die "缺少 review_approved_commit，禁止归档"

  if [ "$approved" = "none" ]; then
    [ "$no_code" = "1" ] || die "该任务无代码改动，归档需显式 --no-code"
  else
    [ "$no_code" = "0" ] || die "该任务有代码 commit，不能用 --no-code"
    [ -n "$target" ] && [ -n "$merged" ] \
      || die "有代码改动时，done 必须提供 --target 和 --merged-commit"
    case "$method" in merge|squash|rebase) ;; *) die "--method 只能是 merge / squash / rebase" ;; esac

    branch_sha="$(git -C "$MAIN_ROOT" rev-parse --verify "refs/heads/ai/$id^{commit}" 2>/dev/null || true)"
    if [ -n "$branch_sha" ]; then
      [ "$branch_sha" = "$approved" ] \
        || die "批准后分支又有变化（批准 ${approved}，当前 ${branch_sha}）：旧批准失效，需重新审查"
    fi
    git -C "$MAIN_ROOT" show-ref --verify --quiet "refs/heads/$target" \
      || die "目标分支不存在：$target"
    target_sha="$(git -C "$MAIN_ROOT" rev-parse --verify "$target^{commit}" 2>/dev/null)" \
      || die "目标分支不存在：$target"
    merged_sha="$(git -C "$MAIN_ROOT" rev-parse --verify "$merged^{commit}" 2>/dev/null)" \
      || die "合并提交不存在：$merged"
    git -C "$MAIN_ROOT" merge-base --is-ancestor "$merged_sha" "$target_sha" \
      || die "合并提交 $merged_sha 不在目标分支 $target 上"

    if [ "$method" = "merge" ]; then
      approved_ancestor=0
      git -C "$MAIN_ROOT" merge-base --is-ancestor "$approved" "$merged_sha" && approved_ancestor=1
      [ "$approved_ancestor" = "1" ] \
        || die "merge 方式要求被批准 commit 是合并提交的祖先；squash/rebase 请显式写 --method squash|rebase（校验会受限）"
    fi
    append_record "$task" "### 合并证据（$(now)，人工提供）

- 目标分支：${target}（${target_sha}）
- 合并提交：$merged_sha
- 合并方式：$method
- 被批准 commit：$approved
- 校验：\`git merge-base --is-ancestor $merged_sha $target\` = 通过
- 校验边界：$([ "$method" = merge ] && echo '已确认被批准 commit 包含在合并提交中' || echo 'squash/rebase 无法用 sha 证明内容等价，仅确认合并提交在目标分支上；仍需人工确认内容')
- 人工确认人：$by
- 确认原话：$note"

    fm_set "$task" merge_target "$target"
    fm_set "$task" merged_commit "$merged_sha"
    fm_set "$task" merge_method "$method"
    fm_set "$task" merged_by "$by"
    fm_set "$task" merged_at "$(stamp)"
    fm_set "$task" merged_note "$note"
  fi

  if [ "$approved" = "none" ]; then
    append_record "$task" "### 归档确认（$(now)，无代码改动）

- 人工确认人：$by
- 确认原话：$note
- 校验：任务无代码 commit，无需合并证据"
    fm_set "$task" merge_method "none"
    fm_set "$task" merged_by "$by"
    fm_set "$task" merged_at "$(stamp)"
    fm_set "$task" merged_note "$note"
  fi

  fm_set "$task" status "done"
  mv "$task" "$AI_DIR/done/$id.md"
  release_lock_by_id "$id"
  log "已归档 $id -> done/。worktree 和分支没有删除，按需人工清理。"
}

cmd_reject() {
  local id="${1:-}" reason="（未写原因）" task
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) reason="$1"; shift ;;
    esac
  done
  [ -n "$id" ] || die "用法：ai-workflow.sh reject <id> [--reason 原因]"
  task="$(find_task "$id")" || die "找不到任务：$id"
  case "$(task_dir "$task")" in review|approved) ;; *) die "reject 只用于 review/ 或 approved/ 的任务" ;; esac
  append_record "$task" "### 人审拒绝（$(now)）

- 原因：$reason"
  move_task "$task" "blocked" "blocked"
  release_current_lock
  release_lock_by_id "$id"
  log "已拒绝 $id -> blocked/。重试前人工补充信息、改 status: new、清零 attempts，再移回 inbox/。"
}

cmd_block() {
  local id="${1:-}" reason="" task
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-}"; shift 2 ;;
      *) die "未知参数：$1" ;;
    esac
  done
  [ -n "$id" ] && [ -n "$reason" ] || die "用法：ai-workflow.sh block <id> --reason \"原因\""
  task="$(find_task "$id")" || die "找不到任务：$id"
  [ "$(task_dir "$task")" = "doing" ] || die "block 只用于 doing/ 的任务"
  append_record "$task" "### 阻塞记录（$(now)）

- 原因：$reason
- worktree/分支/diff 均保留，不自动删除。"
  move_task "$task" "blocked" "blocked"
  release_current_lock
  release_lock_by_id "$id"
  log "任务 $id -> blocked/；已有 worktree 和 diff 保留。"
}

cmd_release() {
  local id="${1:-}" lock desc
  [ -n "$id" ] || die "用法：ai-workflow.sh release <id>"
  case "$id" in *[!A-Za-z0-9._-]*) die "非法任务 id：$id" ;; esac
  lock="$(lock_dir "$id")"
  [ -d "$lock" ] || { log "任务 $id 没有锁"; return 0; }
  desc="$(describe_lock "$lock")"
  rm -rf "$lock"
  log "已释放任务 $id 的锁（原持有者：${desc}）。释放前应确认对应会话已结束。"
}

# ------------------------------------------------------------------
# 可选：claude -p 无人值守
# ------------------------------------------------------------------
build_prompt() { # $1 id, $2 risk, $3 任务文件
  local id="$1" risk="$2" task="$3"
  cat <<EOF
你是本仓库的维护 agent，在任务 worktree（分支 ai/${id}）里处理任务 ${id}，处理完停下汇报。

第一步只读探索，不要改任何业务代码：
- 读任务文件、仓库已有规则（AGENTS.md / CLAUDE.md / docs 里现有的项目规则）。
- 核对相关代码、接口、依赖、测试和验收条件。
- 判断是否存在影响实现的重要未决事项（业务口径、接口行为、数据模型、权限、兼容性、任务范围等）。

有重要歧义时：不要默认假设开始实现。不要修改业务代码。在最终汇报里写清：
已确认事实（带文件证据）、待决问题、可选方案与影响、建议方案（明确标为建议）、用户下一步应补充和批准什么。
最后一行写：AI_WORKFLOW_RESULT: discussion

只有确认无重要歧义后才实施。状态由脚本维护：不要移动或修改 .ai-workflow/ 下任何文件，不要 commit .ai-workflow/。
在分支 ai/${id} 上 commit；验收标准不得自行放宽；验证必须真实执行，没跑写「未运行」及原因。
需求不清或做不到时不要猜，最后一行写 AI_WORKFLOW_RESULT: blocked。
EOF
  if [ "$risk" = "high" ]; then
    cat <<EOF

这是一次 risk: high（或 risk 缺失 / 写错）的任务，只产出方案，不改代码：
给出拆解方案、影响面、回滚方式、需要人确认的问题；不要修改任何文件，不要 commit，不要安装依赖。
EOF
  else
    cat <<EOF

按验收标准实现；先写会失败的检查，再改代码。
EOF
  fi
  cat <<EOF

最终汇报包含：改动（分支 + commit sha，或「无代码改动」）、验证（准确命令、执行目录、退出码、结果；未验证的写明）、风险 / 待人确认。
最后一行必须是以下之一：
AI_WORKFLOW_RESULT: done
AI_WORKFLOW_RESULT: discussion
AI_WORKFLOW_RESULT: blocked
AI_WORKFLOW_RESULT: failed

===== 任务文件（${task}）=====
$(cat "$task")
===== 任务文件结束 =====
EOF
}

run_agent() { # $1 id, $2 prompt, $3 worktree
  local id="$1" prompt="$2" wt="$3"
  local json_log="$LOG_ROOT/$id.result.json" err_log="$LOG_ROOT/$id.stderr.log"
  local args=( -p "$prompt" --output-format json
               --max-budget-usd "$MAX_BUDGET_USD"
               --permission-mode acceptEdits --permission-prompts none
               --allowedTools "$ALLOWED_TOOLS" --disallowedTools "$DISALLOWED_TOOLS" )
  [ -n "$MAX_TURNS" ] && args+=( --max-turns "$MAX_TURNS" )
  [ -n "$CLAUDE_MODEL" ] && args+=( --model "$CLAUDE_MODEL" )
  log "调用 ${CLAUDE_BIN}（id=$id, 日志=${json_log}）"
  set +e
  ( cd "$wt" && "$CLAUDE_BIN" "${args[@]}" ) > "$json_log" 2> "$err_log"
  local rc=$?
  set -e
  log "agent 退出码：$rc"
  return "$rc"
}

agent_marker() {
  local m
  m="$(grep -o 'AI_WORKFLOW_RESULT: *[a-z]*' "$LOG_ROOT/$1.result.json" 2>/dev/null | tail -n 1 | sed 's/.*: *//')" || true
  case "$m" in done|discussion|blocked|failed) printf '%s\n' "$m" ;; *) printf '\n' ;; esac
}

append_report() { # $1 任务文件, $2 id
  local text=""
  if command -v jq >/dev/null 2>&1; then
    text="$(jq -r '.result // empty' "$LOG_ROOT/$2.result.json" 2>/dev/null || true)"
  fi
  if [ -n "$text" ]; then
    append_record "$1" "### agent 汇报（$(now)）

$text"
  else
    append_record "$1" "### agent 汇报

（未能解析最终汇报，请看 $LOG_ROOT/$2.result.json）"
  fi
}

mark_failure() { # $1 id, $2 原因
  local id="$1" reason="$2" task attempts max_attempts
  task="$AI_DIR/doing/$id.md"
  [ -f "$task" ] || { warn "失败记录时找不到 $task"; return 0; }
  attempts=$(( $(to_int "$(fm_get "$task" attempts)") + 1 ))
  max_attempts="$(to_int "$(fm_get "$task" max_attempts)")"
  [ "$max_attempts" -gt 0 ] || max_attempts="$MAX_ATTEMPTS_DEFAULT"
  fm_set "$task" attempts "$attempts"
  append_record "$task" "### 失败记录（$(now)，第 $attempts 次）

- 原因：$reason
- 日志：$LOG_ROOT/$id.result.json / $LOG_ROOT/$id.stderr.log
- worktree/分支保留，未重置、未删除。"
  if [ "$attempts" -ge "$max_attempts" ]; then
    log "任务 $id 失败 $attempts 次，达到上限 ${max_attempts}，移入 blocked/"
    move_task "$task" "blocked" "blocked"
  else
    log "任务 $id 失败 $attempts/${max_attempts}，退回 inbox 等待重试"
    move_task "$task" "inbox" "new"
  fi
  release_current_lock
}

mark_blocked_agent() { # $1 id, $2 说明
  local id="$1" task
  task="$AI_DIR/doing/$id.md"
  append_record "$task" "### 阻塞记录（$(now)）

- $2
- worktree/分支/diff 保留。"
  move_task "$task" "blocked" "blocked"
  release_current_lock
}

mark_discussion() { # $1 id, $2 说明
  local id="$1" task="$AI_DIR/doing/$1.md"
  append_record "$task" "### 暂停讨论记录（$(now)）

- $2
- 已有 worktree/提交/diff 保留，不重置、不删除。"
  fm_set "$task" status "needs-discussion"
  mv "$task" "$AI_DIR/discussion/$id.md"
  release_current_lock
}

mark_review() { # $1 id, $2 说明
  local id="$1" note="$2" task="$AI_DIR/doing/$id.md" wt head commits base
  append_record "$task" "### 结果（$(now)）

$note"
  wt="$(fm_get "$task" worktree)"; case "$wt" in ''|/*) ;; *) wt="$MAIN_ROOT/$wt" ;; esac
  commits=0; head="none"; base="$(fm_get "$task" base_commit)"
  if [ -n "$wt" ] && [ -d "$wt" ]; then
    head="$(git -C "$wt" rev-parse HEAD)"
    commits="$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)"
  fi
  if [ "$commits" -gt 0 ]; then fm_set "$task" review_commit "$head"; else fm_set "$task" review_commit "none"; fi
  fm_set "$task" status "needs_review"
  mv "$task" "$AI_DIR/review/$id.md"
  release_current_lock
  release_lock_by_id "$id"
  log "任务 $id -> review/（needs_review），等待人工审查。"
}

recover_orphans() {
  local f id
  for f in "$AI_DIR"/doing/*.md; do
    [ -f "$f" ] || continue
    id="$(task_id "$f")"
    [ -d "$(lock_dir "$id")" ] && continue
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY_RUN：发现中断的任务 ${id}（doing/ 无锁），真正运行时会转入 blocked/ 并保留 worktree"
      continue
    fi
    warn "任务 $id 在 doing/ 但无锁：按中断处理，转入 blocked/（不自动删 worktree、不消耗 attempts）"
    append_record "$f" "### 中断恢复（$(now)）

- 上次运行在 doing/ 但没有持有任务锁。
- 已转入 blocked/，worktree/提交/diff 保留。
- 处理方式：人工核对改动后，补充信息并把 status/目录调整回可继续的状态。"
    fm_set "$f" status "blocked"
    mv "$f" "$AI_DIR/blocked/$id.md"
  done
}

cmd_run() {
  local candidates priority created src id risk task wt base prompt rc commits dirty marker review_now
  if ! acquire_global_lock; then
    log "另一个 ai-workflow run 正在运行（$LOCK_ROOT/loop.lock），本次退出"
    exit 0
  fi
  cleanup_stale_run_locks
  recover_orphans

  if [ -z "$PROJECT_TOOLS" ]; then
    warn "PROJECT_TOOLS 为空：agent 只有读写文件和 git 提交权限，跑不了项目测试。"
  fi
  review_now="$(review_count)"
  if [ "$review_now" -ge "$REVIEW_LIMIT" ]; then
    log "review/ + approved/ 已有 $review_now 个任务（上限 ${REVIEW_LIMIT}），等人审，本次不领新任务"
    exit 0
  fi
  candidates="$(list_new_candidates)"
  if [ -z "$candidates" ]; then
    log "没有 status: new 的任务，退出（等待讨论的任务不会被领取）"
    exit 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN：候选任务（priority / created / path）"
    printf '%s\n' "$candidates"
    exit 0
  fi

  while IFS=$'\t' read -r priority created src; do
    [ -n "$src" ] || continue
    id="$(task_id "$src")"
    risk="$(normalize_risk "$(fm_get "$src" risk)")"
    if [ -e "$AI_DIR/doing/$id.md" ]; then
      warn "doing/ 已存在同名任务 ${id}，跳过"
      continue
    fi
    if ! acquire_task_lock "$id" "run" "$CLAIMED_BY"; then
      log "任务 $id 已被其他会话认领（$(describe_lock "$(lock_dir "$id")")），跳过"
      continue
    fi
    mv "$src" "$AI_DIR/doing/$id.md"
    fm_set "$AI_DIR/doing/$id.md" status "claimed"
    fm_set "$AI_DIR/doing/$id.md" claimed_by "$CLAIMED_BY"
    fm_set "$AI_DIR/doing/$id.md" claimed_at "$(stamp)"

    if ! wt="$(ensure_worktree "$id" 1)"; then
      release_current_lock
      mark_failure "$id" "无法准备 worktree（已有不匹配目录或分支被占用），请人工确认"
      exit 0
    fi
    record_worktree "$AI_DIR/doing/$id.md" "$id" "$wt"

    if [ -n "$WORKTREE_SETUP" ]; then
      log "worktree 初始化：$WORKTREE_SETUP"
      if ! ( cd "$wt" && bash -c "$WORKTREE_SETUP" ) > "$LOG_ROOT/$id.setup.log" 2>&1; then
        mark_failure "$id" "WORKTREE_SETUP 失败，详见 $LOG_ROOT/$id.setup.log"
        exit 0
      fi
    fi

    base="$(git -C "$wt" rev-parse HEAD)"
    prompt="$(build_prompt "$id" "$risk" "$AI_DIR/doing/$id.md")"
    rc=0
    run_agent "$id" "$prompt" "$wt" || rc=$?

    commits="$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    marker="$(agent_marker "$id")"
    log "结果：exit=$rc commits=$commits dirty=$dirty marker=${marker:-无}"

    if [ "$rc" -ne 0 ]; then
      mark_failure "$id" "claude 退出码 ${rc}，详见 $LOG_ROOT/$id.stderr.log"
    else
      append_report "$AI_DIR/doing/$id.md" "$id"
      case "$marker" in
        discussion)
          if [ "$commits" -gt 0 ] || [ "$dirty" -gt 0 ]; then
            mark_discussion "$id" "agent 报告重要歧义；已产生 commit=${commits}、未提交改动=${dirty}，全部保留。用户补方案并批准后 resume。"
          else
            mark_discussion "$id" "agent 只读探索后报告重要歧义；业务代码零改动。用户补方案并批准后 resume。"
          fi
          ;;
        blocked)
          mark_blocked_agent "$id" "agent 汇报需求不清或无法完成，见上方「agent 汇报」" ;;
        failed)
          mark_failure "$id" "agent 自报失败（AI_WORKFLOW_RESULT: failed）" ;;
        *)
          if [ "$risk" = "high" ]; then
            if [ "$commits" -gt 0 ] || [ "$dirty" -gt 0 ]; then
              mark_blocked_agent "$id" "risk high 只允许出方案，但出现 commit=${commits}、未提交改动=${dirty}；改动保留，交人工处理"
            else
              mark_review "$id" "- 模式：risk high（或缺失/写错），仅产出方案，未改代码
- 方案见上方「agent 汇报」，等人决定"
            fi
          elif [ "$commits" -eq 0 ]; then
            mark_failure "$id" "agent 退出码 0，但分支没有新 commit（marker=${marker:-无}）"
          else
            mark_review "$id" "- 分支 ai/$id 新增 $commits 个 commit，worktree 未提交改动 $dirty 处
- 结论标记：${marker:-缺失（按有 commit 处理）}
- 验证记录见上方「agent 汇报」和 commit 正文；人工合并前必须复核 diff"
          fi
          ;;
      esac
    fi
    exit 0
  done <<< "$candidates"
  log "所有候选都被跳过，退出"
}

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-run}" in
  run)            cmd_run ;;
  next)           cmd_next ;;
  claim)          shift; cmd_claim "$@" ;;
  pause)          shift; cmd_pause "$@" ;;
  plan-seal)      shift; cmd_plan_seal "$@" ;;
  approve)        shift; cmd_approve "$@" ;;
  resume)         shift; cmd_resume "$@" ;;
  review)         shift; cmd_review "$@" ;;
  approve-review) shift; cmd_approve_review "$@" ;;
  done)           shift; cmd_done "$@" ;;
  reject)         shift; cmd_reject "$@" ;;
  block)          shift; cmd_block "$@" ;;
  release)        shift; cmd_release "$@" ;;
  check)          cmd_check ;;
  -h|--help|help) usage ;;
  *)              die "未知子命令：${1}（可用：run | next | claim | pause | plan-seal | approve | resume | review | approve-review | done | reject | block | release | check）" ;;
esac
