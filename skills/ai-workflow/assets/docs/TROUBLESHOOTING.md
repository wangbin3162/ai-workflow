# 常见问题与恢复

## 任务锁残留

现象：`claim` / `resume` 报「任务已被占用」。

```bash
cat .ai-workflow/locks/<id>/owner
```

- `kind=run`：脚本模式的锁。进程已退出且超过 `LOCK_STALE_MINUTES` 时，下次 `run` 会自动清理。
- `kind=session`：手动会话的锁，可能跨轮次存在，**不会自动清理**。
  确认对应会话已结束后：

```bash
.ai-workflow/scripts/ai-workflow.sh release <id>
```

不要在会话仍在使用任务时释放锁。

## doing/ 里有无锁任务

下次 `run` 会把「`doing/` 但没有锁」的任务转入 `blocked/`，保留 worktree 和已有改动，
不消耗 attempts。人工核对 diff 后，补充信息、改回 `status: new` 并移回 `inbox/` 再继续。

## worktree 冲突

- 目录已存在但不是该分支的 git worktree → 脚本停止并报告；**不删除、不嵌套创建**。
- 同一分支已有 worktree → 复用，不再新建。
- 主 checkout 当前在 `ai/<id>` 分支 → 拒绝领取；先切回基准分支。
- 会话已经在任务 worktree → 先核验仓库与分支，复用当前目录。

需要清理已合并的 worktree 时由人执行：

```bash
git worktree list
git worktree remove .ai-workflow/worktrees/<id>
git branch -d ai/<id>
```

脚本不会替你删除。

## 等待讨论的任务不能被领取

这是预期行为。`discussion/` 任务必须满足：

1. 「## 方案」非空；
2. `plan-seal` 记录版本与 sha；
3. 用户明确批准当前版本，`approve` 记录 `approved_*`；
4. 用户明确要求恢复后运行 `resume`。

重新封存方案会使旧批准失效；`check` 也会报告失效的批准。

## review 被拒绝

| 报错 | 处理 |
| --- | --- |
| worktree 有未提交改动 | 提交或明确记录后再送审 |
| risk low 没有新 commit | 实现未完成 |
| risk high 有 commit | high 只允许出方案；撤销代码或改任务风险等级 |
| 验证记录为空 | 在「## 验证记录」写真实命令、目录、退出码、结果 |

## done 被拒绝

| 报错 | 处理 |
| --- | --- |
| 只接受 approved/ | 先人工审查并 `approve-review` |
| 缺少 review_approved_commit | 重新审查批准 |
| 批准后分支又有变化 | 代码变了，旧批准失效；重新审查 |
| 合并提交不在目标分支 | 确认目标分支与合并提交 |
| merge 方式找不到祖先关系 | squash/rebase 请显式写 `--method squash|rebase` |

squash/rebase 的内容等价无法用 sha 证明，脚本会写进证据；仍要人工确认。

## 无代码任务怎么归档

`risk: high` 只出方案的任务：

```bash
.ai-workflow/scripts/ai-workflow.sh review <id>
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit none --by 审查人 --note "方案通过"
.ai-workflow/scripts/ai-workflow.sh done <id> --no-code --by 确认人 --note "确认无代码改动"
```

## 任务状态不在 git 里

脚本不自动 `git add/commit`，避免污染业务分支。需要跨机器/多人同步时，
由你决定何时提交 `.ai-workflow/`。`git status` 里看到任务文件变化是正常的。

## 旧版 .ai/ 与 ai-loop

新脚本不会读取 `.ai/`、`scripts/ai-loop.sh`，也不会自动迁移。
手动迁移步骤见 [MIGRATION.md](MIGRATION.md)。

## 检查整体一致性

```bash
.ai-workflow/scripts/ai-workflow.sh check
```

它会检查状态与目录、id 与文件名、重复 id、讨论任务的批准是否失效、
approved/ 是否有审查 commit、done/ 是否缺少合并证据。
