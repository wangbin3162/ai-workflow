# 极简上手流程

适用于第一次在真实工程里使用：**先手写任务、手动跑；稳定后再考虑自动化。**
机制见 [ARCHITECTURE.md](ARCHITECTURE.md)；目标项目内生成的是 `.ai-workflow/WORKFLOW.md`。

## 1. 初始化（一次性）

在目标工程根目录开 Claude Code，说：

> /ai-workflow init

- 技能先只读侦察，再给 `--plan`；只写 `.ai-workflow/`。
- 初始化会同时生成 `.ai-workflow/docs/`（QUICKSTART / REFERENCE / TROUBLESHOOTING / MIGRATION），
  先把 `.ai-workflow/docs/QUICKSTART.md` 给用户看。
- 如果输出 `CONFLICT`，先人工比较冲突文件，决定保留哪一版；不会覆盖。
- 旧 `.ai/`、`scripts/ai-loop.sh` 只提示，不迁移。
- 填 `.ai-workflow/config.env`：
  - `BASE_REF`：明确的开发基准分支/提交（如 `dev`），不要默认都是 main；
  - `PROJECT_TOOLS`：真实跑通的测试/构建命令；
  - `WORKTREE_SETUP`：依赖安装命令（没有依赖就留空）。
- 运行 `.ai-workflow/scripts/ai-workflow.sh check`，再自己看 `git status`。
  初始化不会 `git add/commit`；是否提交由你决定。

## 2. 手写一个任务

```bash
cp .ai-workflow/templates/task.md .ai-workflow/inbox/T-20260101-001.md
```

填：

- `id` 与文件名一致；`status: new`；`risk` 拿不准写 `high`；
- `base_ref` 可选；不写就用 `BASE_REF`，再空就用领取时主 checkout 当前 HEAD；
- 背景、验收标准（真实命令或可观察步骤）、不要做；
- 复杂需求：先讨论方案，把完整方案贴到「## 方案」；
- 没有自动建任务的工具；可以叫 `/ai-workflow task` 帮你整理草稿，但文件由你确认。

## 3. 在手动会话里执行

新开 Claude/T3 会话：

> /ai-workflow 领取并处理 T-20260101-001

它会：

1. `claim`（拿锁、建/复用 worktree、分支 `ai/<id>`）；
2. 只读探索；
3. 有重要歧义 → 填「## 讨论」→ `pause`，任务进 `discussion/`，业务代码零改动；
4. 恢复流程见第 4 节；
5. 实施、验证、`review`，进入 `review/` 等你审查。

需求不清时它应停下讨论，而不是猜。

## 4. 讨论、方案批准、恢复

1. 用户补全「## 方案」，必要时修改版本号。
2. `.ai-workflow/scripts/ai-workflow.sh plan-seal <id> --version 1`
3. 用户明确说「批准版本 1」后：
   `.ai-workflow/scripts/ai-workflow.sh approve <id> --version 1 --by 你 --note "用户批准原话"`
4. 用户明确要求恢复后：
   `.ai-workflow/scripts/ai-workflow.sh resume <id>`

方案内容或版本变了，旧批准自动失效；只写方案不代表批准。

## 5. 审查与合并

```bash
git diff <base_commit>...ai/<id>
cat .ai-workflow/review/<id>.md

# 审查通过（不等于合并）
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit <sha> --by 你 --note "审查结论"

# 人工合并（示例；按项目实际分支调整）
git merge --no-ff ai/<id>
merge_sha="$(git rev-parse HEAD)"

# 归档：写入合并证据
.ai-workflow/scripts/ai-workflow.sh done <id> --target main --merged-commit "$merge_sha" --by 你 --note "已确认合并"
```

拒绝：`.ai-workflow/scripts/ai-workflow.sh reject <id> --reason "原因"`。

squash/rebase 用 `--method squash|rebase`；脚本会标注无法用 sha 证明内容等价。

## 6. 什么时候用脚本模式

连续几个任务都满足：验证记录真实、无越界改动、无返工。然后：

```bash
DRY_RUN=1 .ai-workflow/scripts/ai-workflow.sh run
.ai-workflow/scripts/ai-workflow.sh run
```

它是可选的单任务模式，与手动会话共用任务锁。真实 `claude -p` 在真实项目里没有跑通记录前，
不要当无人值守使用。

## 7. 出问题

- 锁残留：确认会话结束后 `.ai-workflow/scripts/ai-workflow.sh release <id>`。
- `doing/` 无锁：下次 `run` 会转入 `blocked/` 并保留 worktree；人工核对后再决定。
- worktree 冲突：脚本会停止并报告；不会删除或嵌套创建。
- 旧任务迁移：见 [MIGRATION.md](MIGRATION.md)。
