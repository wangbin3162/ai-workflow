# ai-workflow 执行说明

单一入口：技能 `ai-workflow`。在 Claude Code / T3 等会话里用 `/ai-workflow` 加提示词，
或用 `/ai-workflow init`（初始化）和 `/ai-workflow task`（按模板拆分/整理任务）。
任务由**用户手写**；本工作流不提供自动创建任务的工具。

配套文档（都随初始化写入本目录）：

- `docs/QUICKSTART.md` — 第一次使用的完整走查
- `docs/REFERENCE.md` — 状态、字段、批准格式、命令与配置速查
- `docs/TROUBLESHOOTING.md` — 锁、worktree、review/done 失败的恢复
- `docs/MIGRATION.md` — 旧 `.ai/`、`ai-loop` 迁移

## 1. 任务从哪来

1. 复制 `.ai-workflow/templates/task.md` 到 `.ai-workflow/inbox/<id>.md`，按模板填写。
2. `id` 必须与文件名一致，分支固定为 `ai/<id>`。
3. 只有 `status: new` 的任务会被领取；`example` 只是格式示例，可删除。
4. 复杂需求先沟通方案，把完整方案贴进任务末尾的「## 方案」。

`.ai-workflow/` 之外的规则文件（`AGENTS.md`、`CLAUDE.md`、`docs/`）属于项目原有内容，
本工作流不修改、不搬动；执行任务前仍要读它们。

## 2. 状态与目录

目录即状态，`ai-workflow.sh check` 会校验：

| 状态 | 目录 | 含义 | 谁能领取 |
| --- | --- | --- | --- |
| `new` | `inbox/` | 新任务，未领取 | 是 |
| `needs-discussion` | `discussion/` | 发现重要歧义，等用户补方案并批准 | **否** |
| `claimed` | `doing/` | 已认领，有活跃写者 | 否 |
| `needs_review` | `review/` | 实现完成 + 验证记录已写，等人审 | 否 |
| `review_approved` | `approved/` | 人工审查通过，**尚未合并** | 否 |
| `done` | `done/` | 已提供合并证据并人工确认归档 | 否 |
| `blocked` | `blocked/` | 失败达上限 / 被拒绝 / 中断 | 否 |
| `example` | `inbox/` | 示例，不会被领取 | 否 |

实现完成、验证通过、审核通过、人工确认已合并、done/归档是五件事，不能合并成一句「完成了」。

## 3. 手动会话流程（Claude / T3）

### 3.1 领取

```bash
.ai-workflow/scripts/ai-workflow.sh next
.ai-workflow/scripts/ai-workflow.sh claim <id> --by 你的名字
```

`claim` 会：

- 用 `mkdir` 任务锁保证同一任务只有一个活跃写者；
- 把任务移到 `doing/`，写 `claimed_by` / `claimed_at`；
- 从 `base_ref` → `BASE_REF` → 主 checkout 当前 HEAD 的优先级选择基准，创建（或复用）worktree；
- 记录 worktree 与 `base_commit`。

### 3.2 先只读探索

领取后先不改业务代码：

1. 读任务、项目原有规则、相关代码/接口/依赖/验收条件。
2. 判断是否存在影响实现的重要未决事项：业务口径、接口行为、数据模型、权限、兼容性、任务范围等。
3. 没有重要歧义才进入实施。

### 3.3 有重要歧义：进 needs-discussion

不要用默认假设开工。先在任务文件的「## 讨论」写清：

- 已确认事实（附文件路径或命令证据）；
- 待决问题；
- 可选方案及影响；
- 建议方案（明确标为建议，不是用户决定）；
- 当前是否已有业务代码改动（有/无；已提交与未提交各多少）；
- 用户下一步应补充和批准什么。

然后：

```bash
.ai-workflow/scripts/ai-workflow.sh pause <id> --reason "为什么需要讨论"
```

`pause` 把任务移到 `discussion/`（`needs-discussion`），释放锁，**保留已有 worktree、提交和 diff**。
等待讨论的任务不会被 `run` 或下一次 claim 自动领取。

用户可以把任务带到任意 Claude/T3 会话讨论，把完整方案写回「## 方案」。

### 3.4 方案版本与用户批准

```bash
.ai-workflow/scripts/ai-workflow.sh plan-seal <id> --version 1
# 用户明确说「批准版本 1」之后：
.ai-workflow/scripts/ai-workflow.sh approve <id> --version 1 --by 用户名 --note "用户批准原话"
.ai-workflow/scripts/ai-workflow.sh resume <id>
```

规则：

- `plan-seal` 记录 `plan_version` 和「## 方案」内容的 sha256；只写方案不算批准。
- `approve` 必须版本号与当前一致、内容 sha 与封存值一致，且带用户原话。
- 方案内容或版本变化后，旧批准失效；`resume` 会拒绝。
- 只有用户明确要求恢复时才运行 `resume`，不自动扫描 discussion/ 接手任务。
- 实施后才发现歧义：同样 `pause`。不要 reset、不要删 worktree；`pause` 会记录已有 commit / 未提交改动 / 改动文件。

### 3.5 实现与验证

只在 worktree（分支 `ai/<id>`）里改代码。验证记录写进任务「## 验证记录」：

- 准确命令、执行目录、退出码、结果；
- 区分已验证、未验证、被阻塞；
- 不能以「模型说完成」替代测试证据。

依赖安装按 `.ai-workflow/config.env` 的 `WORKTREE_SETUP` 或项目原有约定，不在 worktree 里自行安装。

### 3.6 送审

```bash
.ai-workflow/scripts/ai-workflow.sh review <id>
```

要求：

- worktree 没有未提交改动；
- `risk: low` 至少有 1 个新 commit；`risk: high` 不允许有 commit（只出方案）；
- 「## 验证记录」非空。

`review` 只把任务移到 `review/`，**不合并、不 push、不删 worktree**。

### 3.7 人工审查批准（不等于合并）

审查通过不等于合并；审核通过不等于已合并；合并必须由人执行。

```bash
# 先看 diff 与验证记录
git diff <base_commit>...ai/<id>
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit <sha> --by 审查人 --note "审查结论"
```

`approve-review` 会核对：分支 HEAD 与审查 commit 一致、commit 与送审记录一致。
审查后代码再变化，旧批准不能沿用。无代码改动（risk high 只出方案）用 `--commit none`。

### 3.8 人工合并与归档

合并必须由人执行。合并后：

```bash
.ai-workflow/scripts/ai-workflow.sh done <id> --target main --merged-commit <sha> --by 确认人 --note "已确认合并"
```

校验：

- 任务必须在 `approved/`（不能从 `review/` 直接 done）；
- 有 `review_approved_commit`；
- 批准后分支 HEAD 没有变化；
- 合并提交在目标分支上；
- `--method merge` 时，被批准 commit 必须是合并提交的祖先。

squash / rebase 合并用 `--method squash|rebase`；脚本只能确认合并提交在目标分支上，
无法用 sha 证明内容等价，会如实写进证据，仍需人工确认。
没有人工确认或有效合并证据时，不归档。

脚本不自动 merge、push、删除 worktree 或分支。

## 4. 可选：claude -p 无人值守

```bash
DRY_RUN=1 .ai-workflow/scripts/ai-workflow.sh run
.ai-workflow/scripts/ai-workflow.sh run
```

区别：

- 手动会话：人看着探索、讨论、实现；
- `run`：脚本选一个 `status: new` 任务、建 worktree、调用 `claude -p`，每次只处理一个。

共同点：

- 共用同一个任务锁，不能抢同一个任务；
- 都不合并不 push；
- 都没有自动任务创建。

`run` 的结果：

- 汇报 `AI_WORKFLOW_RESULT: discussion` → 进 `discussion/`，已有改动保留；
- `blocked` → 进 `blocked/`，不消耗 attempts；
- 失败 → `attempts + 1`，未达上限退回 `inbox/`，达到上限进 `blocked/`；
- `risk high` 产生改动 → 进 `blocked/` 交人工（不重试）。

真实 `claude -p` 未在本项目验证前，不要把 `run` 当无人值守使用。

## 5. 锁、中断与恢复

- 任务锁：`.ai-workflow/locks/<id>/`，`owner` 文件记录 `kind`（run/session）、`by`、`pid`、`created`。
- 正常释放：`review`、`pause`、`block`、`reject`、`done` 完成后自动释放。
- 手动会话异常退出：锁可能残留。确认对应会话已结束后执行
  `.ai-workflow/scripts/ai-workflow.sh release <id>`。
- 脚本模式（kind=run）的锁：只有进程已退出且超过 `LOCK_STALE_MINUTES` 才会被下次 `run` 自动清理。
- 手动会话的锁不会自动清理，避免误抢正在跨轮次讨论的任务。
- `doing/` 里没有锁的任务视为上次中断：下次 `run` 会转入 `blocked/`，**保留** worktree 和改动，不消耗 attempts。

## 6. worktree

- 默认位置：`.ai-workflow/worktrees/<id>/`（`.ai-workflow/.gitignore` 已忽略）。
- 分支：`ai/<id>`。
- 基准优先级：任务 `base_ref` → `.ai-workflow/config.env` 的 `BASE_REF` → 领取时主 checkout 当前 HEAD。
  `eco-system` 这类以 `dev` 为开发基准的项目，请把 `BASE_REF` 设为 `dev`；本工作流不修改别的项目。
- 会话已经在任务 worktree 里时，脚本核验仓库与分支后直接复用，不嵌套创建。
- 已有同一分支 worktree 时复用；目录存在但不是该分支的 worktree 时停止并报告冲突，不删除。
- 主 checkout 当前在 `ai/<id>` 分支时拒绝领取，避免污染主工作区。
- 在任务 worktree 里执行脚本时，用主 checkout 的绝对路径；worktree 可能没有未提交的 `.ai-workflow/`。
  脚本会自行定位主 checkout 并共享同一任务池与锁。

## 7. 任务状态提交

脚本**不会**自动 `git add/commit`，也不会为了保存状态在业务分支提交。
任务文件是否纳入版本控制、何时提交，由用户决定。审查通过后的合并证据只写入任务文件。

## 8. 配置

`.ai-workflow/config.env`（写法 `: "${VAR:=值}"`，命令行环境变量优先）：

- `BASE_REF`：默认基准分支/提交；
- `PROJECT_TOOLS`：agent 可运行的测试/构建命令白名单，逐条写；
- `WORKTREE_SETUP`：worktree 建好后的依赖安装命令；
- `REVIEW_LIMIT`：`review/` + `approved/` 待处理上限，达到后停止领新任务；
- `LOCK_STALE_MINUTES`：脚本锁过期分钟数。

## 9. 旧版迁移

旧版 `ai-loop-starter` 的 `.ai/`、`scripts/ai-loop.sh`、`ai-loop-task` 技能不会被本工作流调用。
迁移方式见源包 `docs/MIGRATION.md`。脚本不自动迁移任务、不改写旧状态。
