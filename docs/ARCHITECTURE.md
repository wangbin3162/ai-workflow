# 架构说明

本仓库提供 `ai-workflow`：**用户手写任务 + 独立 worktree + 人工审查合并**的最小骨架。
核心约束：AI 只产出结果；**讨论、批准、审查、合并、归档都必须有人的明确动作**。

对外只有一个技能入口：`skills/ai-workflow`（`/ai-workflow init|task|<提示词>`）。
旧入口 `ai-loop-init` / `ai-loop-task` 已取消，内容归档在 `archive/` 与
`skills/ai-workflow/references/legacy-ai-loop-task.md`，不再被技能发现。

## 1. 目标与边界

做：

- 在目标项目安全、幂等地初始化 `.ai-workflow/`；
- 让手动 Claude/T3 会话按任务池执行一个用户手写任务；
- 可选保留 `claude -p` 单任务脚本；
- 用状态机区分：实现完成、验证记录、审查通过、人工合并、归档；
- 发现歧义时先讨论，不默认实现。

不做：

- 多项目平台、多角色自动调度、复杂代理框架；
- 自动创建任务、自动恢复讨论任务、自动合并、push、删除 worktree；
- 修改目标项目 `AGENTS.md` / `CLAUDE.md` / `docs/` / 根 `.gitignore`；
- 迁移旧 `.ai/` 任务或改写用户旧状态。

## 2. 生成到目标项目的结构

初始化只写目标项目 `.ai-workflow/`：

```text
.ai-workflow/
├── README.md                     # 最短流程
├── WORKFLOW.md                   # 完整执行说明
├── config.env                    # BASE_REF / PROJECT_TOOLS / WORKTREE_SETUP / REVIEW_LIMIT
├── .gitignore                    # worktrees/ locks/ logs/ 等运行时产物
├── .initialized                  # ai-workflow:v1
├── templates/task.md             # 用户手写任务模板
├── inbox/                        # status: new / example
├── discussion/                   # needs-discussion
├── doing/                        # claimed
├── review/                       # needs_review
├── approved/                     # review_approved（尚未合并）
├── done/                         # done（有合并证据）
├── blocked/                      # blocked
└── scripts/
    ├── ai-workflow.sh
    └── test-ai-workflow.sh
```

目标项目的规则文件原样保留，工作流不读取、不改写、不搬动。

初始化行为：

- 目标必须是有至少一个提交的 git 仓库（worktree 依赖）；
- `--plan` 默认不改文件；`--apply` 只补缺失文件，内容相同则跳过；
- 同名文件内容不同 → 列冲突、退出码 1、**整次不写入**；
- 旧版 `.ai/`、`scripts/ai-loop.sh` 只警告，不读取、不迁移；
- 不执行 `git add/commit/push`。

## 3. 任务状态

目录即状态；`ai-workflow.sh check` 校验。

```mermaid
stateDiagram-v2
    [*] --> new: 用户手写 inbox/
    new --> claimed: claim（mkdir 锁）
    claimed --> needs-discussion: pause（有歧义，保留 worktree/diff）
    needs-discussion --> claimed: 用户批准方案版本 + resume
    claimed --> review: review（实现完成 + 验证记录）
    review --> approved: approve-review（人工审查通过）
    approved --> done: done（人工确认 + 合并证据）
    review --> blocked: reject
    approved --> blocked: reject
    claimed --> blocked: block / 失败达上限 / 中断
    claimed --> new: 失败未达上限
    blocked --> new: 人工处理后可重新入池
```

| 状态 | 目录 | 含义 |
| --- | --- | --- |
| `new` | `inbox/` | 可领取 |
| `needs-discussion` | `discussion/` | 有重要歧义，等用户补方案并批准；**不自动领取** |
| `claimed` | `doing/` | 已认领，有活跃写者 |
| `needs_review` | `review/` | 实现完成、验证记录已写，等人审 |
| `review_approved` | `approved/` | 人工审查通过，**尚未合并** |
| `done` | `done/` | 已确认合并并归档 |
| `blocked` | `blocked/` | 失败/拒绝/中断，需人工 |
| `example` | `inbox/` | 示例，不领取 |

## 4. 讨论与批准模型

### 4.1 needs-discussion

领取后先只读探索；发现业务口径、接口行为、数据模型、权限、兼容性、范围等重要歧义时：

1. 在任务「## 讨论」写：已确认事实（附证据）、待决问题、可选方案与影响、建议方案（标为建议）、
   当前代码改动（有/无，已提交与未提交数）、用户下一步。
2. `pause <id> --reason ...`：记录 worktree、分支、commit 数、未提交改动、改动文件与 diffstat，
   移到 `discussion/`，释放锁，**不 reset、不删除**。
3. 实施后才发现歧义也走同一流程；已有 diff/commit/worktree 保留并如实记录。

`run` 模式下 agent 报告 `AI_WORKFLOW_RESULT: discussion` 也进入同一状态；有改动则保留。

### 4.2 方案版本与批准

- `plan-seal <id> --version N`：计算「## 方案」正文的 sha256（去行尾空白与首尾空行），
  写入 `plan_version` / `plan_sha256`。
- `approve <id> --version N --by ... --note "用户原话"`：要求版本与当前一致、
  方案 sha 与封存值一致、批准人/原话非空；写入 `approved_version` / `approved_plan_sha256` / `approved_*`。
- `resume <id>`：重新计算当前方案 sha，要求与批准 sha 一致且版本一致；否则拒绝。
- 方案内容或版本变化 → 旧批准失效。`plan-seal` 检测到内容变化时自动清空批准字段。
- 只写方案、模型自评「可行」都不算批准；脚本只认带用户原话的 `approve` 记录。

## 5. 实现、验证、审查、合并

- `review <id>`：要求 worktree 无未提交改动、验证记录非空；
  `risk: low` 至少 1 个 commit，`risk: high` 不允许 commit（只出方案）。
  记录 `review_commit`，移到 `review/`。不做验证判定——验证内容由执行方如实填写，人工审查。
- `approve-review <id> --commit SHA --by ... --note ...`：核对分支 HEAD、送审 commit 与 `--commit` 一致；
  写入 `review_approved_commit` 等，移到 `approved/`。**不等于合并**。
- `done <id> --target 分支 --merged-commit SHA --by ... --note ...`：
  - 只接受 `approved/`；
  - 有代码时必须给目标分支与合并提交；
  - 合并提交必须在目标分支上；
  - `--method merge` 时被批准 commit 必须是合并提交的祖先；
  - squash/rebase 只能确认合并提交在目标分支上，**无法用 sha 证明内容等价**，证据里明确标注；
  - 批准后分支 HEAD 变化 → 拒绝归档；
  - 无代码任务（risk high 计划）用 `--no-code`，仍需人工确认。
- `done` 不删除 worktree/分支，不 merge、不 push。

## 6. 两种运行方式与锁

| | 手动会话（Claude/T3） | `run`（claude -p） |
| --- | --- | --- |
| 入口 | `/ai-workflow <提示词>` + 脚本子命令 | `ai-workflow.sh run` |
| 状态操作 | 人/agent 调用脚本 | 脚本 |
| 锁 | `claim` 建立，跨命令持有，review/pause/block 释放 | 脚本持有，结束释放 |
| 讨论 | 人工补方案、批准、resume | agent 报 discussion，脚本转入 |

锁协议：

- 锁目录 `.ai-workflow/locks/<id>/`，`mkdir` 原子获取；`owner` 记录 `kind`、`by`、`pid`、`created`。
- 正常释放：`pause`、`review`、`block`、`reject`、`done`、`release`；`run` 在结果处理时释放。
- 脚本模式（`kind=run`）：进程已退出且超过 `LOCK_STALE_MINUTES`，下次 `run` 才自动清理。
- 手动会话（`kind=session`）可能跨轮次持锁，**不会自动清理**；确认会话结束后显式 `release <id>`。
- 两个方式都通过同一把任务锁，不能抢同一个任务。

## 7. worktree

- 位置：`.ai-workflow/worktrees/<id>/`；分支 `ai/<id>`。
- 基准优先级：任务 `base_ref` → `config.env` 的 `BASE_REF` → 领取时主 checkout 当前 HEAD。
  不假设项目都用 main；`eco-system` 这类项目把 `BASE_REF` 设为 `dev`（不在本仓库修改它）。
- 已注册同分支 worktree → 复用；会话已在任务 worktree → 核验后复用，不嵌套。
- 目录存在但不是该分支 worktree → 停止并报告；不删除、不覆盖。
- 主 checkout 当前在 `ai/<id>` 分支 → 拒绝领取。
- `base_commit` 在首次领取时记录；复用已有分支时用 merge-base，避免把已有提交算成 0。

## 8. 任务状态与证据的保存

脚本**不自动 git add/commit**，也不为了保存调度状态在业务分支提交。
任务文件、批准记录、合并证据都写在 `.ai-workflow/` 内的任务文件中，是否纳入版本控制、何时提交由用户决定。
这样不会污染目标项目的 dev 分支；代价是任务状态默认只存在于工作区（或由用户自行提交）。

## 9. 命令与参数

```text
next
claim <id> [--by 名字] [--force]
pause <id> --reason 文本
plan-seal <id> [--version N]
approve <id> --version N --by 名字 --note 用户原话
resume <id> [--force]
review <id>
approve-review <id> --commit SHA --by 名字 --note 文本
done <id> --target 分支 --merged-commit SHA --by 名字 --note 文本 [--method merge|squash|rebase]
done <id> --no-code --by 名字 --note 文本
reject <id> [--reason 文本]
block <id> --reason 文本
release <id>
check
run
```

配置（`.ai-workflow/config.env`，环境变量优先）：`BASE_REF`、`PROJECT_TOOLS`、`WORKTREE_SETUP`、
`REVIEW_LIMIT`（review+approved 上限）、`LOCK_STALE_MINUTES`、`CLAUDE_MODEL` 等。

## 10. 验证状态与风险

**已验证**（隔离测试，`bash scripts/test-ai-workflow.sh`，153 项；临时 fixture + 假 claude）：
初始化只写 `.ai-workflow/`、幂等与冲突停止；不修改 AGENTS/CLAUDE/docs/根 .gitignore；
单一技能入口；手写任务；needs-discussion 零代码改动；实施后暂停保留 diff/worktree；
讨论任务不被自动领取；未批准/版本不符/方案变化阻止恢复；批准后可恢复；
手动与脚本锁互斥及遗留锁边界；worktree 复用不嵌套；review→approve→merge→done 门槛；
squash 受限校验；risk high 无代码归档；`run` 的成功/失败/阻断/歧义/中断；`check` 发现伪造归档。

**未验证 / 已知限制**：

1. 真实 `claude -p` 在真实项目中的完整一轮（提示词是否被遵守）。
2. 真实 T3 的命令/API：本技能不假设、不伪造适配；由用户在会话里按 WORKFLOW 执行。
3. squash/rebase 合并无法用 sha 证明内容等价，只能确认合并提交在目标分支；仍需人工确认。
4. 锁只覆盖任务级互斥；`claim` 后进程异常退出会留下 `kind=session` 锁，需显式 `release`。
5. 没有 `.claude/settings.json` 的 permissions/hook 层护栏；护栏在提示词、脚本校验与工具黑白名单。
6. 任务状态默认不提交，跨机器/多人协作时需自行版本化 `.ai-workflow/`。
