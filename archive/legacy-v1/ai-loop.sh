#!/usr/bin/env bash
# scripts/ai-loop.sh — 每次运行最多处理 1 个任务（claude -p 无人值守版）
#
# 设计原则：
#   - 每次调用只做一个任务，方便用 cron / launchd / while 循环限流
#   - mkdir 锁防并发；每个任务一个独立 git worktree + ai/<id> 分支
#   - 状态（目录 + status 字段）只由本脚本维护；agent 只在 worktree 里写代码
#   - agent 的结论来自最终汇报末行的 AI_LOOP_RESULT 标记，不靠它跨目录写文件
#   - 不自动合并、不 push；合并由人完成
#   - review 队列满、需求不清、失败达到上限，都会停下来
#
# 用法：
#   scripts/ai-loop.sh                     # 处理一个任务（等同 run）
#   DRY_RUN=1 scripts/ai-loop.sh           # 只看会选哪个任务，不改任何状态
#   scripts/ai-loop.sh done <id>           # 人审通过并合并后：review/ -> done/
#   scripts/ai-loop.sh reject <id> [原因]   # 人审拒绝：review/ -> blocked/
#   scripts/ai-loop.sh check               # 校验 status 字段与所在目录是否一致
#
# 所有可调参数都在下面，均可用同名环境变量覆盖，例如：
#   REVIEW_LIMIT=5 CLAUDE_MODEL=claude-sonnet-5-5 PROJECT_TOOLS='Bash(pytest *)' scripts/ai-loop.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# ------------------------------------------------------------------
# 可调参数（环境变量优先）
# ------------------------------------------------------------------
AI_DIR="${AI_DIR:-.ai}"                       # 任务池目录

# 项目级默认值放在 $AI_DIR/loop.env，用 `: "${VAR:=值}"` 的写法，这样命令行环境变量仍然优先。
# 例：: "${PROJECT_TOOLS:=Bash(pytest *)}"   : "${WORKTREE_SETUP:=pnpm install --frozen-lockfile}"
if [ -f "$AI_DIR/loop.env" ]; then
  # shellcheck disable=SC1090
  . "$AI_DIR/loop.env"
fi

REVIEW_LIMIT="${REVIEW_LIMIT:-3}"             # review 里待审任务达到这个数就停止领新任务
MAX_ATTEMPTS_DEFAULT="${MAX_ATTEMPTS_DEFAULT:-2}"  # 任务未写 max_attempts 时的失败上限
WORKTREE_ROOT="${WORKTREE_ROOT:-.worktrees}"  # worktree 根目录（相对仓库根，已 gitignore）
WORKTREE_SETUP="${WORKTREE_SETUP:-}"          # worktree 建好后由脚本执行的初始化命令，如 pnpm install --frozen-lockfile
LOCK_ROOT="${LOCK_ROOT:-.ai-locks}"           # 锁目录（只在主 checkout，已 gitignore）
LOG_ROOT="${LOG_ROOT:-.ai-logs}"              # 日志目录（已 gitignore）
LOCK_STALE_MINUTES="${LOCK_STALE_MINUTES:-120}"  # 超过这个分钟数的锁视为残留并清理

CLAUDE_BIN="${CLAUDE_BIN:-claude}"            # claude 可执行文件
CLAUDE_MODEL="${CLAUDE_MODEL:-}"              # 空 = 用 CLI 默认模型，如 claude-sonnet-5-5
MAX_TURNS="${MAX_TURNS:-}"                    # 空 = 不传。claude 2.1.319 的 --help 没有 --max-turns，设置前先确认
MAX_BUDGET_USD="${MAX_BUDGET_USD:-3}"         # 单任务预算上限（全局，不支持按任务覆盖；仅 API 计费有意义）

# 工具白名单 = 基础工具 + 项目工具。
# 基础工具只含文件读写和只读 / 提交类 git；不放行 npm/node/python 之类的通配，
# 因为它们能间接执行 git push、装依赖。项目的测试 / 构建命令请用 PROJECT_TOOLS 逐条写，
# 例如 PROJECT_TOOLS='Bash(pytest *),Bash(make test)'。
BASE_TOOLS="Read,Edit,Write,Glob,Grep,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git status *),Bash(git log *),Bash(git show *),Bash(git rev-parse *),Bash(ls *),Bash(mkdir *)"
PROJECT_TOOLS="${PROJECT_TOOLS:-}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-$BASE_TOOLS${PROJECT_TOOLS:+,$PROJECT_TOOLS}}"
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-Bash(git push *),Bash(git merge *),Bash(git reset --hard *),Bash(git checkout main *),Bash(git checkout master *),Bash(git worktree *),Bash(gh *),Bash(rm -rf *)}"

DRY_RUN="${DRY_RUN:-0}"                       # 1 = 只选任务并打印，不改状态
CLAIMED_BY="${CLAIMED_BY:-ai-loop-$(date +%Y%m%d-%H%M%S)}"

# ------------------------------------------------------------------
# 基础设施
# ------------------------------------------------------------------
mkdir -p "$AI_DIR"/{inbox,doing,review,done,blocked} "$LOCK_ROOT" "$LOG_ROOT" "$WORKTREE_ROOT"
WT_ABS="$(cd "$WORKTREE_ROOT" && pwd)"

CURRENT_TASK_LOCK=""
GLOBAL_LOCK_HELD=0

log()  { printf '[ai-loop] %s\n' "$*"; }
warn() { printf '[ai-loop][warn] %s\n' "$*" >&2; }
die()  { printf '[ai-loop][error] %s\n' "$*" >&2; exit 1; }

release_task_lock() {
  if [ -n "$CURRENT_TASK_LOCK" ]; then
    rmdir "$CURRENT_TASK_LOCK" 2>/dev/null || true
    CURRENT_TASK_LOCK=""
  fi
}

cleanup() {
  release_task_lock
  if [ "$GLOBAL_LOCK_HELD" = "1" ]; then
    rm -f "$LOCK_ROOT/loop.lock/pid" 2>/dev/null || true
    rmdir "$LOCK_ROOT/loop.lock" 2>/dev/null || true
    GLOBAL_LOCK_HELD=0
  fi
}
trap cleanup EXIT INT TERM

is_stale() { # $1 路径
  [ -n "$(find "$1" -maxdepth 0 -mmin +"$LOCK_STALE_MINUTES" -print -quit 2>/dev/null)" ]
}

acquire_global_lock() {
  local lock="$LOCK_ROOT/loop.lock"
  if mkdir "$lock" 2>/dev/null; then
    GLOBAL_LOCK_HELD=1
    printf '%s\n' "$$" > "$lock/pid"
    return 0
  fi
  if is_stale "$lock"; then
    warn "清理过期全局锁（>${LOCK_STALE_MINUTES} 分钟）：$lock"
    rm -f "$lock/pid" 2>/dev/null || true
    rmdir "$lock" 2>/dev/null || true
    if mkdir "$lock" 2>/dev/null; then
      GLOBAL_LOCK_HELD=1
      printf '%s\n' "$$" > "$lock/pid"
      return 0
    fi
  fi
  return 1
}

# 清理残留的任务锁（只删空目录，不动正在运行的任务）
cleanup_stale_task_locks() {
  find "$LOCK_ROOT" -mindepth 1 -maxdepth 1 -type d -mmin +"$LOCK_STALE_MINUTES" \
    ! -name 'loop.lock' -print0 2>/dev/null | xargs -0 rmdir 2>/dev/null || true
}

# ------------------------------------------------------------------
# 任务文件读写（只处理 front-matter 的简单 key: value）
# ------------------------------------------------------------------
# fm_get 会去掉行内注释（` # …`）和首尾空白；值里不要出现 " #"。
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

fm_set() { # $1 文件, $2 key, $3 value
  local file="$1" key="$2" value="$3" tmp="${1}.tmp.$$"
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

to_int() { # $1 任意值 -> 非负整数
  case "${1:-}" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$1" ;;
  esac
}

# risk 只认 low；缺失或写错一律按 high（只出方案），避免护栏被格式问题绕过
normalize_risk() {
  case "${1:-}" in
    low) echo low ;;
    *)   echo high ;;
  esac
}

review_count() {
  find "$AI_DIR/review" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

# 按 priority、created、文件名排序输出候选：priority<TAB>created<TAB>path
list_candidates() {
  local f status priority created
  for f in "$AI_DIR"/inbox/*.md; do
    [ -f "$f" ] || continue
    status="$(fm_get "$f" status)"
    [ "$status" = "new" ] || continue
    priority="$(fm_get "$f" priority)"
    [ -n "$priority" ] || priority="P9"
    created="$(fm_get "$f" created)"
    [ -n "$created" ] || created="9999-99-99"
    printf '%s\t%s\t%s\n' "$priority" "$created" "$f"
  done | sort -t $'\t' -k1,1 -k2,2 -k3,3
}

task_already_exists() { # $1 id
  local d
  for d in doing review done blocked; do
    [ -e "$AI_DIR/$d/$1.md" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------------
# 状态迁移：只提交本次涉及的任务文件，不带走 inbox 里的草稿或用户已 staged 的其他改动
# ------------------------------------------------------------------
TASK_PATHS=()

move_file() { # $1 源, $2 目标；设置 TASK_PATHS
  if git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; then
    git mv "$1" "$2"
    TASK_PATHS=("$1" "$2")
  else
    mv "$1" "$2"            # 还没提交过的新任务文件（git mv 会失败）
    TASK_PATHS=("$2")
  fi
  git add -- "$2"
}

commit_task_state() { # $1 描述（使用 TASK_PATHS）
  if git diff --cached --quiet -- "${TASK_PATHS[@]}"; then
    return 0
  fi
  git commit -qm "ai: $1" -- "${TASK_PATHS[@]}" || warn "提交任务状态失败：$1"
}

move_task() { # $1 源文件, $2 目标目录, $3 新 status, $4 提交说明
  local src="$1" dest_dir="$2" id
  id="$(basename "$src" .md)"
  fm_set "$src" status "$3"
  move_file "$src" "$AI_DIR/$dest_dir/$id.md"
  commit_task_state "$4"
}

# ------------------------------------------------------------------
# 领取
# ------------------------------------------------------------------
claim_task() { # $1 任务路径, $2 id, $3 risk
  local src="$1" id="$2" risk="$3"
  local dest="$AI_DIR/doing/$id.md"

  if task_already_exists "$id"; then
    warn "任务 $id 已存在于 doing/review/done/blocked，跳过"
    return 1
  fi
  if ! mkdir "$LOCK_ROOT/$id" 2>/dev/null; then
    log "任务 $id 已被其他会话认领（锁存在），跳过"
    return 1
  fi
  CURRENT_TASK_LOCK="$LOCK_ROOT/$id"

  fm_set "$src" claimed_by "$CLAIMED_BY"
  fm_set "$src" claimed_at "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  fm_set "$src" status "claimed"
  if ! move_file "$src" "$dest"; then
    warn "移动任务 $id 到 doing 失败"
    release_task_lock
    return 1
  fi
  commit_task_state "claim $id"
  log "已认领 ${id}（risk: ${risk}）"
  return 0
}

# ------------------------------------------------------------------
# worktree
# ------------------------------------------------------------------
prepare_worktree() { # $1 id -> stdout 输出 worktree 绝对路径；失败返回 1
  local id="$1" wt="$WT_ABS/$id" branch="ai/$id"
  if [ -e "$wt" ]; then
    warn "worktree 目录已存在：$wt"
    return 1
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    # 这里必须写 stderr，函数 stdout 被调用方当作 worktree 路径捕获
    log "复用已有分支 $branch" >&2
    git worktree add "$wt" "$branch" >/dev/null 2>&1 || { warn "git worktree add 失败（分支可能被其他 worktree 占用）：$branch"; return 1; }
  else
    git worktree add "$wt" -b "$branch" >/dev/null 2>&1 || { warn "git worktree add 失败：$branch"; return 1; }
  fi
  printf '%s\n' "$wt"
}

remove_worktree() { # $1 id
  local id="$1" wt="$WT_ABS/$id"
  if [ -d "$wt" ]; then
    git worktree remove --force "$wt" >/dev/null 2>&1 \
      || warn "worktree 清理失败，请手动执行 git worktree remove --force $wt"
  fi
}

# ------------------------------------------------------------------
# 提示词（worker 模式：状态归脚本管，agent 只在 worktree 里干活）
# ------------------------------------------------------------------
build_prompt() { # $1 id, $2 risk, $3 任务文件路径
  local id="$1" risk="$2" task_path="$3"
  cat <<EOF
你是本仓库的维护 agent，在独立 worktree（分支 ai/${id}）里处理任务 ${id}，处理完停下汇报。
先读当前目录下的 AGENTS.md、LESSONS.md、docs/code-standards.md，再按下面的任务文件工作。
状态由脚本维护：不要移动或修改 .ai/ 下任何文件，不要 commit .ai/。你的最终汇报会被脚本原样写进任务记录。
硬性规矩见 AGENTS.md；验收标准、提交信息格式见 docs/code-standards.md。
验证必须真实执行；没跑的写「未运行」及原因。
EOF
  if [ "$risk" = "high" ]; then
    cat <<EOF

这是一次 risk: high（或 risk 缺失 / 写错）的任务，只产出方案，不改代码：
1. 阅读任务文件和相关代码，在最终汇报里给出拆解方案、影响面、回滚方式、需要人确认的问题。
2. 不要修改任何文件，不要 commit，不要安装依赖。
EOF
  else
    cat <<EOF

按验收标准实现：先写会失败的测试，再改代码；验收标准不得自行放宽。
在 ai/$id 分支上 commit，正文按 docs/code-standards.md 的三段式写，含「跑了什么 / 没试过」。
需求不清或做不到时不要猜：不要 commit，在汇报里写清具体问题。
EOF
  fi
  cat <<EOF

最终汇报包含：改动（分支 + commit sha，或「无代码改动」）、验证（命令与结果；没跑的写明）、风险 / 待人确认。
汇报的最后一行必须单独写成下面三者之一（脚本据此判定结果）：
AI_LOOP_RESULT: done
AI_LOOP_RESULT: blocked
AI_LOOP_RESULT: failed

===== 任务文件（${task_path}）=====
$(cat "$task_path")
===== 任务文件结束 =====
EOF
}

# ------------------------------------------------------------------
# 调用 claude
# ------------------------------------------------------------------
run_agent() { # $1 id, $2 提示词, $3 worktree -> 返回退出码
  local id="$1" prompt="$2" wt="$3"
  local json_log="$LOG_ROOT/$id.result.json" err_log="$LOG_ROOT/$id.stderr.log"
  local args=( -p "$prompt" --output-format json
               --max-budget-usd "$MAX_BUDGET_USD"
               --permission-mode acceptEdits --permission-prompts none
               --allowedTools "$ALLOWED_TOOLS" --disallowedTools "$DISALLOWED_TOOLS" )
  if [ -n "$MAX_TURNS" ]; then
    args+=( --max-turns "$MAX_TURNS" )
  fi
  if [ -n "$CLAUDE_MODEL" ]; then
    args+=( --model "$CLAUDE_MODEL" )
  fi

  log "调用 ${CLAUDE_BIN}（id=$id, 日志=${json_log}）"
  set +e
  ( cd "$wt" && "$CLAUDE_BIN" "${args[@]}" ) > "$json_log" 2> "$err_log"
  local rc=$?
  set -e
  log "agent 退出码：$rc"
  return "$rc"
}

# 从结果 JSON 取 agent 的结论标记：done / blocked / failed / 空
agent_marker() { # $1 id
  local m
  m="$(grep -o 'AI_LOOP_RESULT: *[a-z]*' "$LOG_ROOT/$1.result.json" 2>/dev/null | tail -n 1 | sed 's/.*: *//')" || true
  case "$m" in
    done|blocked|failed) printf '%s\n' "$m" ;;
    *) printf '\n' ;;
  esac
}

# 把 agent 的最终汇报写进任务文件（需要 jq；没有就指向日志）
append_report() { # $1 任务文件, $2 id
  local text=""
  if command -v jq >/dev/null 2>&1; then
    text="$(jq -r '.result // empty' "$LOG_ROOT/$2.result.json" 2>/dev/null || true)"
  fi
  if [ -n "$text" ]; then
    append_record "$1" "### agent 汇报（$(date '+%Y-%m-%d %H:%M:%S')）

$text"
  else
    append_record "$1" "### agent 汇报

（未能解析最终汇报，请看 $LOG_ROOT/$2.result.json）"
  fi
}

# ------------------------------------------------------------------
# 结果处理
# ------------------------------------------------------------------
mark_failure() { # $1 id, $2 原因, $3 可选：keep = 不删除 worktree
  local id="$1" reason="$2" keep="${3:-}"
  local task="$AI_DIR/doing/$id.md"
  local attempts max_attempts
  attempts=$(( $(to_int "$(fm_get "$task" attempts)") + 1 ))
  max_attempts="$(to_int "$(fm_get "$task" max_attempts)")"
  [ "$max_attempts" -gt 0 ] || max_attempts="$MAX_ATTEMPTS_DEFAULT"

  fm_set "$task" attempts "$attempts"
  append_record "$task" "### 失败记录（$(date '+%Y-%m-%d %H:%M:%S')，第 $attempts 次）

- 原因：$reason
- 日志：$LOG_ROOT/$id.result.json / $LOG_ROOT/$id.stderr.log
"

  if [ "$attempts" -ge "$max_attempts" ]; then
    log "任务 $id 失败 $attempts 次，达到上限 ${max_attempts}，移入 blocked/"
    move_task "$task" "blocked" "blocked" "block $id (attempt $attempts)"
  else
    log "任务 $id 失败 $attempts/${max_attempts}，退回 inbox 等待重试"
    move_task "$task" "inbox" "new" "retry $id (attempt $attempts)"
  fi
  [ "$keep" = "keep" ] || remove_worktree "$id"
}

# agent 自报「需求不清 / 做不到」：不算失败，不消耗 attempts，直接交给人
mark_blocked() { # $1 id, $2 说明
  local id="$1" task="$AI_DIR/doing/$1.md"
  append_record "$task" "### 阻塞记录（$(date '+%Y-%m-%d %H:%M:%S')）

- $2"
  log "任务 $id 被 agent 标记为 blocked，移入 blocked/（不消耗 attempts）"
  move_task "$task" "blocked" "blocked" "block $id (agent)"
  remove_worktree "$id"
}

mark_success() { # $1 id, $2 说明
  local id="$1" note="$2"
  local task="$AI_DIR/doing/$id.md"
  append_record "$task" "### 结果（$(date '+%Y-%m-%d %H:%M:%S')）

$note
"
  move_task "$task" "review" "needs_review" "review $id"
  log "任务 $id 已移入 review/，worktree 保留：$WT_ABS/$id"
}

# doing/ 里没有对应锁的任务 = 上次运行中断（脚本持有全局锁，不会有别的脚本实例在跑）
recover_orphans() {
  local f id
  for f in "$AI_DIR"/doing/*.md; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .md)"
    [ -d "$LOCK_ROOT/$id" ] && continue
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY_RUN：发现中断的任务 ${id}（doing/ 无锁），真正运行时会按失败处理并退回 inbox"
      continue
    fi
    warn "任务 $id 在 doing/ 但无锁，按失败处理（上次运行中断）"
    mark_failure "$id" "上次运行中断（doing/ 中无对应锁）"
  done
}

# ------------------------------------------------------------------
# 子命令
# ------------------------------------------------------------------
cmd_done() { # $1 id
  local id="${1:-}" src
  [ -n "$id" ] || die "用法：ai-loop.sh done <id>"
  src="$AI_DIR/review/$id.md"
  [ -f "$src" ] || die "review/ 里没有 $id.md"
  acquire_global_lock || die "另一个 ai-loop 正在运行，稍后再试"
  move_task "$src" "done" "done" "done $id"
  log "已归档 $id -> done/。合并 ai/${id}、清理 worktree 和分支由你自己做。"
}

cmd_reject() { # $1 id, $2 原因
  local id="${1:-}" reason="${2:-（未写原因）}" src
  [ -n "$id" ] || die "用法：ai-loop.sh reject <id> [原因]"
  src="$AI_DIR/review/$id.md"
  [ -f "$src" ] || die "review/ 里没有 $id.md"
  acquire_global_lock || die "另一个 ai-loop 正在运行，稍后再试"
  append_record "$src" "### 人审拒绝（$(date '+%Y-%m-%d %H:%M:%S')）

- 原因：$reason"
  move_task "$src" "blocked" "blocked" "reject $id"
  log "已拒绝 $id -> blocked/。要重试：补充信息、status 改 new、attempts 清零、移回 inbox/。"
}

cmd_check() {
  local bad=0 spec dir allowed f st
  for spec in inbox:new,example doing:claimed review:needs_review done:done blocked:blocked; do
    dir="${spec%%:*}"; allowed="${spec#*:}"
    for f in "$AI_DIR/$dir"/*.md; do
      [ -f "$f" ] || continue
      st="$(fm_get "$f" status)"
      case ",$allowed," in
        *",$st,"*) ;;
        *) warn "状态与目录不一致：${f}（status=${st:-空}，$dir/ 应为 ${allowed}）"; bad=1 ;;
      esac
      if [ "$st" != "example" ] && [ "$(fm_get "$f" id)" != "$(basename "$f" .md)" ]; then
        warn "id 与文件名不一致：${f}（id=$(fm_get "$f" id)）"; bad=1
      fi
    done
  done
  [ "$bad" = "0" ] && log "check 通过" || exit 1
}

# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------
main() {
  if ! acquire_global_lock; then
    log "另一个 ai-loop 正在运行（$LOCK_ROOT/loop.lock），本次退出"
    exit 0
  fi
  cleanup_stale_task_locks
  recover_orphans

  if [ -z "$PROJECT_TOOLS" ]; then
    warn "PROJECT_TOOLS 为空：agent 只有读写文件和 git 提交权限，跑不了测试。请按项目填测试命令。"
  fi

  local review_now
  review_now="$(review_count)"
  if [ "$review_now" -ge "$REVIEW_LIMIT" ]; then
    log "review 队列已有 $review_now 个任务（上限 ${REVIEW_LIMIT}），等人审，本次不领新任务"
    exit 0
  fi

  local candidates
  candidates="$(list_candidates)"
  if [ -z "$candidates" ]; then
    log "没有 status: new 的任务，退出"
    exit 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN：候选任务（priority / created / path）"
    printf '%s\n' "$candidates"
    exit 0
  fi

  local priority created src id risk task_path prompt rc wt base commits dirty marker
  while IFS=$'\t' read -r priority created src; do
    [ -n "$src" ] || continue
    id="$(basename "$src" .md)"
    risk="$(normalize_risk "$(fm_get "$src" risk)")"

    if ! claim_task "$src" "$id" "$risk"; then
      continue
    fi
    task_path="$AI_DIR/doing/$id.md"

    if ! wt="$(prepare_worktree "$id")"; then
      mark_failure "$id" "无法创建 worktree $WT_ABS/${id}（目录已存在或分支被占用），请人工确认后清理" keep
      exit 0
    fi
    if [ -n "$WORKTREE_SETUP" ]; then
      log "worktree 初始化：$WORKTREE_SETUP"
      if ! ( cd "$wt" && bash -c "$WORKTREE_SETUP" ) > "$LOG_ROOT/$id.setup.log" 2>&1; then
        mark_failure "$id" "WORKTREE_SETUP 失败，详见 $LOG_ROOT/$id.setup.log"
        exit 0
      fi
    fi

    base="$(git -C "$wt" rev-parse HEAD)"
    prompt="$(build_prompt "$id" "$risk" "$task_path")"

    rc=0
    run_agent "$id" "$prompt" "$wt" || rc=$?

    commits="$(git -C "$wt" rev-list --count "$base"..HEAD 2>/dev/null || echo 0)"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    marker="$(agent_marker "$id")"
    log "结果：exit=$rc commits=$commits dirty=$dirty marker=${marker:-无}"

    if [ "$rc" -ne 0 ]; then
      mark_failure "$id" "claude 退出码 ${rc}，详见 $LOG_ROOT/$id.stderr.log"
    else
      append_report "$task_path" "$id"
      if [ "$marker" = "blocked" ]; then
        mark_blocked "$id" "agent 汇报需求不清或无法完成，问题见上方「agent 汇报」"
      elif [ "$marker" = "failed" ]; then
        mark_failure "$id" "agent 自报失败（AI_LOOP_RESULT: failed），见上方「agent 汇报」"
      elif [ "$risk" = "high" ]; then
        if [ "$commits" -gt 0 ] || [ "$dirty" -gt 0 ]; then
          mark_failure "$id" "risk high 任务只能出方案，但 worktree 里有改动（commits=$commits dirty=${dirty}）"
        else
          mark_success "$id" "- 模式：risk high（或 risk 缺失 / 写错），仅产出方案，未改代码
- 方案见上方「agent 汇报」，等人决定是否批准"
        fi
      elif [ "$commits" -eq 0 ]; then
        mark_failure "$id" "agent 退出码为 0，但分支上没有新 commit（marker=${marker:-无}）"
      else
        mark_success "$id" "- 模式：risk low，分支 ai/$id 新增 $commits 个 commit，worktree 未提交改动 $dirty 处
- 结论标记：${marker:-缺失（agent 没写 AI_LOOP_RESULT，按有 commit 处理）}
- 验证记录见上方「agent 汇报」和 commit 正文；人工合并前请复核 diff"
      fi
    fi

    exit 0   # 每轮只处理一个任务
  done <<< "$candidates"

  log "所有候选任务都被跳过，退出"
}

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-run}" in
  run)           main ;;
  done)          cmd_done "${2:-}" ;;
  reject)        cmd_reject "${2:-}" "${3:-}" ;;
  check)         cmd_check ;;
  -h|--help|help) usage ;;
  *)             die "未知子命令：${1}（可用：run | done | reject | check）" ;;
esac
