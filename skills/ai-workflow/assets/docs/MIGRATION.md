# 从旧版 ai-loop / .ai 迁移

新工作流**不会**自动迁移旧任务、不会改写旧状态、不会删除旧文件。
旧 `.ai/`、`scripts/ai-loop.sh`、旧 `ai-loop-init` / `ai-loop-task` 技能都不再被调用。

## 1. 迁移任务文件（手动）

先备份或提交当前工作区，然后复制（不是移动）：

```bash
mkdir -p .ai-workflow/{inbox,doing,review,approved,done,blocked}
cp .ai/inbox/*.md   .ai-workflow/inbox/   2>/dev/null || true
cp .ai/doing/*.md   .ai-workflow/doing/   2>/dev/null || true
cp .ai/review/*.md  .ai-workflow/review/  2>/dev/null || true
cp .ai/done/*.md    .ai-workflow/done/    2>/dev/null || true
cp .ai/blocked/*.md .ai-workflow/blocked/ 2>/dev/null || true
```

逐个人工处理：

- `status: new`：可保留；缺少的新字段由脚本按需补充。
- `claimed`：没有对应 worktree/锁时不要当活跃任务；核对改动后改回 `new` 或 `blocked`。
- `needs_review`：可以留在 `review/`；`approve-review` 必须对应当前分支 HEAD，
  旧任务没有 `review_commit` 时先人工审查。
- `done`：旧任务没有合并证据的，`check` 只告警、不自动改写；请人工复核。
- `blocked`：重新入池前改 `new`、清零 `attempts`、移回 `inbox/`。
- `example`：可删除。

不要为了通过 `check` 伪造合并证据。

## 2. 状态变化

新增：

- `needs-discussion`（`discussion/`）：有歧义先讨论，不自动领取。
- `review_approved`（`approved/`）：审查通过但尚未合并。

`done` 不再等于「从 review 移过去」：

1. `approve-review` 人工审查批准；
2. 人工执行合并；
3. `done` 提供目标分支与合并提交证据。

无代码任务用 `done --no-code`。

## 3. 命令变化

| 旧 | 新 |
| --- | --- |
| `scripts/ai-loop.sh` | `.ai-workflow/scripts/ai-workflow.sh` |
| `ai-loop.sh done <id>` | `approve-review` → 人工合并 → `done` |
| `ai-loop-task` 技能 | 用户手写任务；`/ai-workflow task` 只出草稿 |
| 旧 `/loop` 提示词 | 手动会话按 `/ai-workflow` 与 `WORKFLOW.md` |

## 4. 已有 `.ai-workflow/` 冲突

初始化是幂等的：

- 缺失 → 创建；
- 内容相同 → 跳过；
- 内容不同 → 列出 `CONFLICT`，整次不写入，退出码非 0。

人工比较后决定保留哪一版；不要覆盖或批量合并。

## 5. 锁与 worktree

- 旧 `.ai-locks/`、`.ai-logs/`、`.worktrees/` 不再使用；新路径在 `.ai-workflow/` 下。
- 手动会话的锁跨命令存在，正常由 `pause/review/block/reject/done` 释放；
  异常时用 `release <id>`。
- 已有 `ai/<id>` worktree 会被识别并复用；不嵌套创建、不删除。
- 主 checkout 在任务分支时拒绝领取。

## 6. 不要做的事

- 不要自动批量迁移或改写旧任务状态。
- 不要同时让旧流程和新流程派工。
- 不要删除旧 `.ai/`、旧脚本，直到确认不再需要。
