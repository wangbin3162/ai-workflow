# 参考：状态、字段、命令与证据

## 1. 状态与目录

目录即状态；`ai-workflow.sh check` 会校验。

| 状态 | 目录 | 含义 | 可自动领取 |
| --- | --- | --- | --- |
| `new` | `inbox/` | 新任务 | 是 |
| `needs-discussion` | `discussion/` | 有重要歧义，等用户补方案并批准 | 否 |
| `claimed` | `doing/` | 已认领，有活跃写者 | 否 |
| `needs_review` | `review/` | 实现完成 + 验证记录已写，等人审 | 否 |
| `review_approved` | `approved/` | 人工审查通过，**尚未合并** | 否 |
| `done` | `done/` | 人工确认合并并归档 | 否 |
| `blocked` | `blocked/` | 失败/拒绝/中断，需人工 | 否 |
| `example` | `inbox/` | 示例，不领取 | 否 |

实现完成、验证通过、审核通过、人工确认已合并、done/归档是五件事，不能合并成一句「完成了」。

## 2. 任务字段

| 字段 | 谁维护 | 说明 |
| --- | --- | --- |
| `id` | 人 | 与文件名一致；分支 `ai/<id>` |
| `type` / `title` / `priority` / `created` | 人 | 仅供人与排序 |
| `status` | 脚本 | 见上表 |
| `risk` | 人 | `low` / `high`；缺失或写错按 `high` |
| `base_ref` | 人 | worktree 基准；空 = `BASE_REF`，再空 = 领取时主 checkout HEAD |
| `claimed_by` / `claimed_at` / `attempts` | 脚本 | 领取与失败重试 |
| `max_attempts` | 人 | 失败上限；空用脚本默认 |
| `worktree` / `base_commit` | 脚本 | 任务工作区与基准提交 |
| `plan_version` / `plan_sha256` | 脚本（plan-seal） | 方案版本与内容指纹 |
| `approved_version` / `approved_plan_sha256` | 脚本（approve） | 用户批准的版本与内容 |
| `approved_by` / `approved_at` / `approved_note` | 脚本（approve） | 批准人、时间、用户原话 |
| `review_commit` | 脚本（review） | 送审 commit；无代码任务为 `none` |
| `review_approved_*` | 脚本（approve-review） | 人工审查对象与结论 |
| `merge_*` | 脚本（done） | 目标分支、合并提交、方式、确认人原话 |

front-matter 只写简单 `key: value`，不要写行内注释，值里不要出现 ` #`。

## 3. 方案批准记录格式

```yaml
plan_version: 2
plan_sha256: <「## 方案」正文的 sha256>
approved_version: 2
approved_plan_sha256: <必须与 plan_sha256 相同>
approved_by: <批准人>
approved_at: <时间>
approved_note: <用户批准原话>
```

有效条件：版本相等且两个 sha 相等。方案内容或版本变化后，旧批准失效。

- `plan-seal` 计算 sha；只封存不等于批准。
- `approve` 必须带 `--version`、`--by`、`--note`。
- `resume` 会重新计算当前方案 sha，不一致就拒绝。
- 不要只改 `status` 或写一句「方案可行」来绕过批准。

## 4. 审查与合并证据

- `review`：实现完成 + 「## 验证记录」非空 + worktree 无未提交改动。
- `approve-review --commit <sha>`：审查对象必须是分支当前 HEAD，且与送审记录一致。
- `done`：
  - 只接受 `approved/`；
  - 有代码时必须 `--target <分支> --merged-commit <sha>`；
  - 合并提交必须在目标分支上；
  - `--method merge` 时被批准 commit 必须是合并提交的祖先；
  - `--method squash|rebase` 只确认合并提交在目标分支上，**无法用 sha 证明内容等价**；
  - 批准后分支 HEAD 变化 → 拒绝归档；
  - 无代码任务（risk high 只出方案）用 `done --no-code`。

## 5. 命令

```bash
# 只读
.ai-workflow/scripts/ai-workflow.sh next
.ai-workflow/scripts/ai-workflow.sh check

# 领取与讨论
.ai-workflow/scripts/ai-workflow.sh claim <id> [--by 名字] [--force]
.ai-workflow/scripts/ai-workflow.sh pause <id> --reason "原因"

# 方案批准
.ai-workflow/scripts/ai-workflow.sh plan-seal <id> --version N
.ai-workflow/scripts/ai-workflow.sh approve <id> --version N --by 名字 --note "用户原话"
.ai-workflow/scripts/ai-workflow.sh resume <id> [--force]

# 送审与归档
.ai-workflow/scripts/ai-workflow.sh review <id>
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit SHA --by 名字 --note "结论"
.ai-workflow/scripts/ai-workflow.sh done <id> --target 分支 --merged-commit SHA --by 名字 --note "确认"
.ai-workflow/scripts/ai-workflow.sh done <id> --no-code --by 名字 --note "确认"

# 拒绝/阻塞/解锁
.ai-workflow/scripts/ai-workflow.sh reject <id> --reason "原因"
.ai-workflow/scripts/ai-workflow.sh block <id> --reason "原因"
.ai-workflow/scripts/ai-workflow.sh release <id>

# 可选：单任务 claude -p
DRY_RUN=1 .ai-workflow/scripts/ai-workflow.sh run
.ai-workflow/scripts/ai-workflow.sh run
```

## 6. 配置

`.ai-workflow/config.env`：

| 变量 | 作用 |
| --- | --- |
| `BASE_REF` | 默认基准分支/提交 |
| `PROJECT_TOOLS` | agent 可运行的测试/构建命令白名单 |
| `WORKTREE_SETUP` | worktree 建好后的依赖安装命令 |
| `REVIEW_LIMIT` | `review/` + `approved/` 待处理上限 |
| `LOCK_STALE_MINUTES` | 脚本锁过期分钟数 |
| `CLAUDE_MODEL` | 可选模型名 |

写法 `: "${VAR:=值}"`，命令行环境变量优先。

## 7. 运行时路径

| 路径 | 作用 |
| --- | --- |
| `.ai-workflow/worktrees/<id>/` | 任务 worktree（已忽略） |
| `.ai-workflow/locks/<id>/` | 任务锁与 owner 信息 |
| `.ai-workflow/locks/loop.lock/` | `run` 全局锁 |
| `.ai-workflow/logs/` | `run` 的 agent 日志 |

脚本不会自动提交任务状态、不会合并、不会 push、不会删除 worktree 或分支。
