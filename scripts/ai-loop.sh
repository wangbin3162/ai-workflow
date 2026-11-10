#!/usr/bin/env bash
# scripts/ai-loop.sh — 每次运行最多处理 1 个任务（claude -p 无人值守版）
#
# 设计原则：
#   - 每次调用只做一个任务，方便用 cron / launchd / while 循环限流
#   - mkdir 锁防并发；每个任务一个独立 git worktree + ai/<id> 分支
#   - 不自动合并、不 push；合并由人完成
#   - review 队列满、需求不清、失败达到上限，都会停下来
#
# 用法：
#   scripts/ai-loop.sh            # 处理一个任务
#   DRY_RUN=1 scripts/ai-loop.sh  # 只看会选哪个任务，不改任何状态
#
# 所有可调参数都在下面，均可用同名环境变量覆盖，例如：
#   REVIEW_LIMIT=5 MAX_TURNS=80 CLAUDE_MODEL=claude-sonnet-5-5 scripts/ai-loop.sh

set -euo pipefail

# ------------------------------------------------------------------
# 可调参数（环境变量优先）
# ------------------------------------------------------------------
AI_DIR="${AI_DIR:-.ai}"                       # 任务池目录
REVIEW_LIMIT="${REVIEW_LIMIT:-3}"             # review 里待审任务达到这个数就停止领新任务
MAX_ATTEMPTS_DEFAULT="${MAX_ATTEMPTS_DEFAULT:-2}"  # 任务未写 max_attempts 时的失败上限
WORKTREE_ROOT="${WORKTREE_ROOT:-../wt}"       # worktree 根目录（相对仓库根）
LOCK_ROOT="${LOCK_ROOT:-.ai-locks}"           # 锁目录（只在主 checkout，已 gitignore）
LOG_ROOT="${LOG_ROOT:-.ai-logs}"              # 日志目录（已 gitignore）
LOCK_STALE_MINUTES="${LOCK_STALE_MINUTES:-120}"  # 超过这个分钟数的锁视为残留并清理

CLAUDE_BIN="${CLAUDE_BIN:-claude}"            # claude 可执行文件
CLAUDE_MODEL="${CLAUDE_MODEL:-}"              # 空 = 用 CLI 默认模型，如 claude-sonnet-5-5
MAX_TURNS="${MAX_TURNS:-60}"                  # 单任务最大轮数
MAX_BUDGET_USD="${MAX_BUDGET_USD:-3}"         # 单任务预算上限（仅 API 计费有意义）
LOOP_GUIDE="${LOOP_GUIDE:-.claude/loop.md}"   # 规则文件路径（写进提示词）

# 允许 / 禁止的工具，按项目技术栈增删
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Read,Edit,Write,Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git status *),Bash(git log *),Bash(git rev-parse *),Bash(mkdir *),Bash(ls *),Bash(cat *),Bash(grep *),Bash(find *),Bash(npm *),Bash(pnpm *),Bash(yarn *),Bash(node *),Bash(npx *),Bash(python *),Bash(pytest *),Bash(go *),Bash(cargo *),Bash(make *)}"
DISALLOWED_TOOLS="${DISALLOWED_TOOLS:-Bash(git push *),Bash(git merge *),Bash(git reset --hard *),Bash(git checkout main *),Bash(git checkout master *),Bash(git worktree *),Bash(gh *),Bash(rm -rf *)}"

DRY_RUN="${DRY_RUN:-0}"                       # 1 = 只选任务并打印，不改状态
CLAIMED_BY="${CLAIMED_BY:-ai-loop-$(date +%Y%m%d-%H%M%S)}"

# ------------------------------------------------------------------
# 基础设施
# ------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

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
fm_get() { # $1 文件, $2 key
  awk -v k="$2" '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    NR > 1 && index($0, k ":") == 1 { sub("^[^:]*:[ \t]*", ""); print; exit }
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

commit_task_state() { # $1 描述
  # 只提交任务池路径，避免把用户已 staged 的无关改动带进提交
  git add "$AI_DIR" >/dev/null 2>&1 || true
  if git diff --cached --quiet -- "$AI_DIR"; then
    return 0
  fi
  git commit -qm "ai: $1" -- "$AI_DIR" || warn "提交任务状态失败：$1"
}

move_task() { # $1 源文件, $2 目标目录, $3 新 status, $4 提交说明
  local src="$1" dest_dir="$2" id
  id="$(basename "$src" .md)"
  fm_set "$src" status "$3"
  git mv "$src" "$AI_DIR/$dest_dir/$id.md"
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
  if ! git mv "$src" "$dest"; then
    warn "移动任务 $id 到 doing 失败"
    release_task_lock
    return 1
  fi
  commit_task_state "claim $id"
  log "已认领 $id（risk: $risk）"
  return 0
}

# ------------------------------------------------------------------
# worktree
# ------------------------------------------------------------------
prepare_worktree() { # $1 id -> 输出 worktree 绝对路径
  local id="$1" wt="$WT_ABS/$id" branch="ai/$id"
  if [ -d "$wt" ]; then
    die "worktree 已存在：$wt（可能是上一次任务未清理，人工确认后删除）"
  fi
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    # 注意：这里必须写 stderr，函数 stdout 被调用方当作 worktree 路径捕获
    log "复用已有分支 $branch" >&2
    git worktree add "$wt" "$branch" >/dev/null
  else
    git worktree add "$wt" -b "$branch" >/dev/null
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
# 提示词
# ------------------------------------------------------------------
build_prompt() { # $1 id, $2 risk, $3 主 checkout 任务文件绝对路径
  local id="$1" risk="$2" task_path="$3" common
  common="你是本仓库的维护 agent，本轮只处理任务 $id，然后停下汇报。
规则文件：$REPO_ROOT/$LOOP_GUIDE（先读它，以及 $REPO_ROOT/AGENTS.md、$REPO_ROOT/LESSONS.md）。
主 checkout：$REPO_ROOT。任务文件：$task_path（你可以读取，并把记录追加到它的「AI 记录区」；不要改人写的部分）。
你的工作目录是独立 worktree，分支 ai/$id；所有代码改动只能发生在这里，禁止改主 checkout 的代码。
不要把 .ai/ 目录下的任何文件 commit 到 ai/$id 分支（任务状态由脚本在主 checkout 维护）。
禁止：git push、git merge、改 .github/、升级/新增依赖、改公共接口（除非任务明确允许）。
验证必须真实执行：在「验证记录」里写命令、commit sha、输出摘要；没跑写「未运行」及原因。"

  if [ "$risk" = "high" ]; then
    cat <<EOF
$common

这是一次 risk: high 的任务，只产出计划，不改代码：
1. 阅读任务文件和相关代码，把拆解方案、影响面、回滚方式、需要人确认的问题写进「AI 记录区 / 拆解」。
2. 不要修改任何源码，不要 commit，不要安装依赖。
3. 汇报里给出「建议方案」和「需要人工批准的点」。
EOF
  else
    cat <<EOF
$common

按 $LOOP_GUIDE 第 7–9 步执行：
1. 按「验收标准」实现；先写会失败的测试，再修。
2. 校验标准不得自行放宽；做不到或需求不清，就把原因写进记录并汇报 blocked。
3. 在 worktree 的 ai/$id 分支上 commit，正文写验证记录摘要。
EOF
  fi
}

# ------------------------------------------------------------------
# 调用 claude
# ------------------------------------------------------------------
run_agent() { # $1 id, $2 提示词, $3 worktree -> 返回退出码
  local id="$1" prompt="$2" wt="$3"
  local json_log="$LOG_ROOT/$id.result.json" err_log="$LOG_ROOT/$id.stderr.log"
  local args=( -p "$prompt" --output-format json
               --max-turns "$MAX_TURNS" --max-budget-usd "$MAX_BUDGET_USD"
               --permission-mode acceptEdits --permission-prompts none
               --allowedTools "$ALLOWED_TOOLS" --disallowedTools "$DISALLOWED_TOOLS" )
  if [ -n "$CLAUDE_MODEL" ]; then
    args+=( --model "$CLAUDE_MODEL" )
  fi

  log "调用 $CLAUDE_BIN（id=$id, 日志=$json_log）"
  set +e
  ( cd "$wt" && "$CLAUDE_BIN" "${args[@]}" ) > "$json_log" 2> "$err_log"
  local rc=$?
  set -e
  log "agent 退出码：$rc"
  return "$rc"
}

# ------------------------------------------------------------------
# 结果处理
# ------------------------------------------------------------------
mark_failure() { # $1 id, $2 原因
  local id="$1" reason="$2"
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
    log "任务 $id 失败 $attempts 次，达到上限 $max_attempts，移入 blocked/"
    move_task "$task" "blocked" "blocked" "block $id (attempt $attempts)"
    remove_worktree "$id"
  else
    log "任务 $id 失败 $attempts/$max_attempts，退回 inbox 等待重试"
    move_task "$task" "inbox" "new" "retry $id (attempt $attempts)"
    remove_worktree "$id"
  fi
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

# ------------------------------------------------------------------
# 主流程
# ------------------------------------------------------------------
main() {
  if ! acquire_global_lock; then
    log "另一个 ai-loop 正在运行（$LOCK_ROOT/loop.lock），本次退出"
    exit 0
  fi
  cleanup_stale_task_locks

  local review_now
  review_now="$(review_count)"
  if [ "$review_now" -ge "$REVIEW_LIMIT" ]; then
    log "review 队列已有 $review_now 个任务（上限 $REVIEW_LIMIT），等人审，本次不领新任务"
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

  local priority created src id risk task_path prompt rc wt base commits dirty max_attempts attempts
  while IFS=$'\t' read -r priority created src; do
    [ -n "$src" ] || continue
    id="$(basename "$src" .md)"
    risk="$(fm_get "$src" risk)"
    [ -n "$risk" ] || risk="low"

    if ! claim_task "$src" "$id" "$risk"; then
      continue
    fi

    task_path="$REPO_ROOT/$AI_DIR/doing/$id.md"
    wt="$(prepare_worktree "$id")"
    base="$(git -C "$wt" rev-parse HEAD)"
    prompt="$(build_prompt "$id" "$risk" "$task_path")"

    rc=0
    run_agent "$id" "$prompt" "$wt" || rc=$?

    commits="$(git -C "$wt" rev-list --count "$base"..HEAD 2>/dev/null || echo 0)"
    dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    log "结果：exit=$rc commits=$commits dirty=$dirty"

    if [ "$rc" -ne 0 ]; then
      mark_failure "$id" "claude 退出码 $rc，详见 $LOG_ROOT/$id.stderr.log"
    elif [ "$risk" = "high" ]; then
      mark_success "$id" "- 模式：risk high，仅产出计划，未改代码
- 等待人工阅读任务文件中的拆解并决定是否批准"
    elif [ "$commits" -eq 0 ]; then
      mark_failure "$id" "agent 退出码为 0，但分支上没有新 commit（可能未完成或未提交）"
    else
      mark_success "$id" "- 模式：risk low，分支 ai/$id 新增 $commits 个 commit
- 验证记录见任务文件；未验证项以任务文件中记录为准
- 人工合并前请复核 diff"
    fi

    exit 0   # 每轮只处理一个任务
  done <<< "$candidates"

  log "所有候选任务都被跳过，退出"
}

main "$@"
