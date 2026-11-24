# 快速开始（第一次用 ai-workflow）

目标：在一个**已经初始化过**的项目里，从手写任务走到人工审查与合并归档。
所有命令都在项目根目录执行；脚本也可以从任务 worktree 里用主 checkout 的绝对路径执行。

## 0. 先看配置

打开 `.ai-workflow/config.env`：

- `BASE_REF`：任务 worktree 的基准分支或提交。以 `dev` 为开发基准的项目填 `dev`；
  空 = 领取时主 checkout 当前 HEAD。不要假设都是 `main`。
- `PROJECT_TOOLS`：agent 能跑的测试/构建命令，逐条写；没验证过的不填。
- `WORKTREE_SETUP`：worktree 建好后的依赖安装命令；没有依赖就留空。
- `REVIEW_LIMIT`：`review/` + `approved/` 待处理上限。

## 1. 手写一个任务

```bash
cp .ai-workflow/templates/task.md .ai-workflow/inbox/T-20260101-001.md
```

至少改这些：

- `id`：必须是 `T-20260101-001`，与文件名一致；
- `title`、`created`、`priority`；
- `status: new`；
- `risk`：拿不准写 `high`（只出方案）；确定不碰支付、鉴权、权限、依赖、CI、数据迁移、公共接口才写 `low`；
- `base_ref`：可留空，按第 0 节的优先级；
- 背景 / 验收标准 / 不要做。

验收标准写真实命令或可观察步骤；没有测试就写人工复现步骤和修改前后可区分的现象。
复杂需求先把方案讨论清楚，把完整方案贴到任务末尾的「## 方案」。

## 2. 在 Claude/T3 会话里领取

```bash
.ai-workflow/scripts/ai-workflow.sh next
.ai-workflow/scripts/ai-workflow.sh claim T-20260101-001 --by 你的名字
```

`claim` 会拿任务锁、建（或复用）`.ai-workflow/worktrees/T-20260101-001` 与分支 `ai/T-20260101-001`。
领取后**先只读探索**：读任务、项目原有规则、相关代码/接口/依赖/验收条件。

## 3. 发现重要歧义：先讨论

不要用默认假设开工。先在任务「## 讨论」写：

- 已确认事实（附文件路径或命令证据）；
- 待决问题；
- 可选方案与影响；
- 建议方案（明确标为建议，不是用户决定）；
- 当前代码改动（有/无；已提交与未提交各多少）；
- 用户下一步应补充和批准什么。

然后：

```bash
.ai-workflow/scripts/ai-workflow.sh pause T-20260101-001 --reason "接口口径不明确"
```

任务进入 `discussion/`（`needs-discussion`），锁释放，已有 worktree/提交/diff 全部保留。
等待讨论的任务不会被 `run` 或下一次 `claim` 自动领取。

## 4. 补方案、批准、恢复

用户补全「## 方案」后：

```bash
.ai-workflow/scripts/ai-workflow.sh plan-seal T-20260101-001 --version 1
```

封存后，**用户明确说「批准版本 1」**，再执行：

```bash
.ai-workflow/scripts/ai-workflow.sh approve T-20260101-001 --version 1 --by 用户 --note "用户批准原话"
.ai-workflow/scripts/ai-workflow.sh resume T-20260101-001
```

- 只写方案不算批准；模型自评「可行」也不算。
- 方案内容或版本变化后，旧批准失效。
- 只有用户明确要求恢复时才运行 `resume`，不要自动接手等待讨论的任务。

## 5. 实施与验证

只在任务 worktree 里改代码。验证记录写进「## 验证记录」：

- 准确命令、执行目录、退出码、结果；
- 已验证 / 未验证 / 被阻塞分别写清；
- 没跑就写「未运行」及原因。

## 6. 送审

```bash
.ai-workflow/scripts/ai-workflow.sh review T-20260101-001
```

要求：worktree 无未提交改动；`risk: low` 至少 1 个 commit，`risk: high` 不允许 commit；
「## 验证记录」非空。任务进入 `review/`，**不合并、不 push、不删 worktree**。

## 7. 人工审查、合并、归档

```bash
# 看 diff 和验证记录
git diff <base_commit>...ai/T-20260101-001

# 审查通过（不等于合并）
.ai-workflow/scripts/ai-workflow.sh approve-review T-20260101-001 --commit <sha> --by 审查人 --note "审查结论"
```

人工合并（示例；按项目分支调整）：

```bash
git merge --no-ff ai/T-20260101-001
merge_sha="$(git rev-parse HEAD)"
```

归档：

```bash
.ai-workflow/scripts/ai-workflow.sh done T-20260101-001 --target main --merged-commit "$merge_sha" --by 你 --note "已确认合并"
```

squash/rebase 合并用 `--method squash|rebase`；脚本只能确认合并提交在目标分支上，
无法用 sha 证明内容等价，证据里会标注这一点。

## 8. 可选：claude -p 单任务模式

```bash
DRY_RUN=1 .ai-workflow/scripts/ai-workflow.sh run
.ai-workflow/scripts/ai-workflow.sh run
```

与手动会话共用任务锁；每次只处理一个 `status: new` 任务。真实 `claude -p` 没有在真实项目
跑通一轮前，不要当无人值守使用。

## 9. 卡住了看哪

- 状态/字段/批准格式：[REFERENCE.md](REFERENCE.md)
- 锁、worktree、讨论、归档失败：[TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- 旧 `.ai/` 任务迁移：[MIGRATION.md](MIGRATION.md)
