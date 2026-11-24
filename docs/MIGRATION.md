# 从 ai-loop-starter 迁移到 ai-workflow

本仓库（源包）已把项目名改为 `ai-workflow`，生成目录改为 `.ai-workflow/`，技能入口改为 `/ai-workflow`。
迁移是**手动、可审计**的：脚本不自动迁移旧任务、不改写旧状态、不删除旧文件。
源包里的旧脚本、旧 SKILL、旧模板与示例任务已复制到 `archive/legacy-v1/`；旧文档仍在 git 历史中。

## 1. 入口变化

| 旧 | 新 | 说明 |
| --- | --- | --- |
| 技能 `ai-loop-init` | 技能 `ai-workflow` 的 `init` 模式 | `/ai-workflow init` |
| 技能 `ai-loop-task` | `ai-workflow` 的 `task` 模式 | 不再自动建任务；只帮用户起草，用户确认后才写 |
| `scripts/ai-loop.sh` | `.ai-workflow/scripts/ai-workflow.sh` | 旧脚本不再被调用 |
| `.ai/` | `.ai-workflow/` | 不自动搬迁 |
| `docs/ai-loop-architecture.md` | `.ai-workflow/WORKFLOW.md` + 本文档 | 初始化不再写项目 docs/ |

旧 `ai-loop-task` 的 SKILL 内容归档在
`skills/ai-workflow/references/legacy-ai-loop-task.md`，不会被技能发现机制扫描为独立入口。

## 2. 旧 `.ai/` 任务池怎么迁移

建议在目标项目里手动执行（先备份或提交）：

```bash
# 1. 新建目录
mkdir -p .ai-workflow/{inbox,discussion,doing,review,approved,done,blocked,templates,scripts}

# 2. 复制（不是移动）旧任务，先保留原件
cp .ai/inbox/*.md .ai-workflow/inbox/ 2>/dev/null || true
cp .ai/doing/*.md .ai-workflow/doing/ 2>/dev/null || true
cp .ai/review/*.md .ai-workflow/review/ 2>/dev/null || true
cp .ai/done/*.md .ai-workflow/done/ 2>/dev/null || true
cp .ai/blocked/*.md .ai-workflow/blocked/ 2>/dev/null || true

# 3. 用新技能初始化缺失文件（只补充，不覆盖）
#    在 Claude 会话里：/ai-workflow init
```

然后**逐个人工处理**：

- `status: new`：可保留；补 `base_ref`（如需要）、`plan_version` 等新字段（脚本会补）。
- `status: claimed`：若没有对应 worktree/锁，不要直接当活跃任务；按中断处理（人工核对改动后改回 `new` 或 `blocked`）。
- `status: needs_review`：可留在 `review/`，但 `approve-review` 要求能对上当前分支 HEAD；
  旧任务没有 `review_commit` 时先人工审查并用当前 HEAD 批准。
- `status: done`：新 `check` 对**没有合并证据的旧 done 任务只告警**，不自动改写。
  请人工复核：补 `review_approved_commit` / `merged_commit`，或保留为历史记录但不要当作新流程证据。
- `status: blocked`：可保留；重新入池前改 `new`、清零 `attempts`、移回 `inbox/`。
- `status: example`：可删。

不要批量改状态；不要为了通过 `check` 伪造合并证据。

## 3. 旧任务字段与状态兼容

新任务多出这些字段（旧任务缺失时脚本按空处理）：

- `base_ref` / `worktree` / `base_commit`
- `plan_version` / `plan_sha256` / `approved_*`
- `review_commit` / `review_approved_*`
- `merge_target` / `merged_commit` / `merge_method` / `merged_*`

状态变化：

- 新增 `needs-discussion`（`discussion/`）与 `review_approved`（`approved/`）。
- `done` 不再等同「review 移过去」；必须有审查批准和合并证据（无代码任务用 `--no-code`）。
- 旧 `scripts/ai-loop.sh done <id>` 的行为不再兼容；新命令是
  `ai-workflow.sh approve-review` → 人工合并 → `ai-workflow.sh done`。

## 4. 已有 `.ai-workflow/` 冲突

初始化是幂等的：

- 文件缺失 → 创建；
- 文件内容相同 → 跳过；
- 文件内容不同 → 列出 `CONFLICT`，整次不写入，退出码 1。

处理方式：人工比较冲突文件，决定保留哪一版；不要用 `--force`（没有这个选项）。
旧版 `.ai/` 与 `scripts/ai-loop.sh` 只会产生 `WARN`，不会被读取或修改。

## 5. 手动会话与 claude -p 的差异

| | 手动会话 | `run` |
| --- | --- | --- |
| 状态操作 | 人/agent 调用脚本 | 脚本 |
| 锁 | `claim` 后跨命令持有 | 脚本持有，结束释放 |
| 讨论 | 人补方案并批准后 `resume` | agent 报 `discussion`，脚本转入 |
| 中断恢复 | `release <id>`（确认会话结束后） | 过期且进程退出的 run 锁自动清理 |
| 适合 | 需求不清、需要讨论 | 边界清楚、验证稳定后的单任务 |

两者共用同一把任务锁，不会抢同一个任务。不要仅靠「不要同时运行」的口头约定。

## 6. 已有 T3 / Claude worktree 如何复用

如果会话已经在 `ai/<id>` 的 worktree 里：

1. 脚本核验当前仓库、当前分支与任务 id 对应；
2. 复用该 worktree，不嵌套创建；
3. 如果目录存在但不是该分支的 worktree，脚本停止并报告冲突；
4. 如果主 checkout 当前在 `ai/<id>` 分支，脚本拒绝领取。

## 7. 讨论与恢复

旧流程没有 `needs-discussion`。迁移后：

1. 有歧义 → 在任务「## 讨论」写事实/问题/方案/建议/代码改动状态；
2. `pause <id> --reason ...`；
3. 用户补「## 方案」→ `plan-seal` → 用户明确批准 → `approve` → 用户要求恢复 → `resume`。

方案版本或内容变化后旧批准失效；不能只比对一个可随手不变的状态标签。

## 8. 审查、合并与归档

```bash
# 人工审查通过（不等于合并）
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit <sha> --by 审查人 --note "结论"

# 人工合并（由人执行，脚本不做）
git merge --no-ff ai/<id>

# 有合并证据后归档
.ai-workflow/scripts/ai-workflow.sh done <id> --target main --merged-commit <sha> --by 确认人 --note "已确认合并"
```

squash/rebase 合并用 `--method squash|rebase`；脚本只能确认合并提交在目标分支上，
不能证明内容等价，证据里会明确标注。

## 9. 不要做的事

- 不要自动批量迁移/改写旧任务状态。
- 不要把旧 `done` 任务直接当新流程的归档证据。
- 不要删除旧 `.ai/`、旧脚本、旧技能归档，直到你确认不再需要。
- 不要同时让旧流程和新流程派工。
