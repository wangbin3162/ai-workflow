# ai-workflow（目标项目内）

本目录由技能 `ai-workflow` 初始化。所有工作流内容都在 `.ai-workflow/` 内；
本技能没有修改项目的 `AGENTS.md`、`CLAUDE.md`、`docs/` 或根 `.gitignore`。

## 最短流程

```bash
# 1) 看有哪些可领取任务（只读）
.ai-workflow/scripts/ai-workflow.sh next

# 2) 在 Claude/T3 会话里领取一个用户手写任务
.ai-workflow/scripts/ai-workflow.sh claim T-20260101-001 --by 你的名字

# 3) 只读探索后若发现重要歧义：先填任务里的「## 讨论」，然后
.ai-workflow/scripts/ai-workflow.sh pause T-20260101-001 --reason "接口口径不明确"

# 4) 用户补全「## 方案」后先封存版本；用户明确批准该版本后记录批准并恢复
.ai-workflow/scripts/ai-workflow.sh plan-seal T-20260101-001 --version 1
.ai-workflow/scripts/ai-workflow.sh approve T-20260101-001 --version 1 --by 你的名字 --note "用户原话"
.ai-workflow/scripts/ai-workflow.sh resume T-20260101-001

# 5) 实现并验证后送审
.ai-workflow/scripts/ai-workflow.sh review T-20260101-001

# 6) 人工审查通过（不等于合并）
.ai-workflow/scripts/ai-workflow.sh approve-review T-20260101-001 --commit <sha> --by 你的名字 --note "审查结论"

# 7) 人工合并后归档（必须提供合并证据）
.ai-workflow/scripts/ai-workflow.sh done T-20260101-001 --target main --merged-commit <sha> --by 你的名字 --note "已确认合并"
```

任务由用户手写：复制 `.ai-workflow/templates/task.md` 到 `.ai-workflow/inbox/<id>.md`。
没有自动建任务的命令。

在任务 worktree 里操作时，用主 checkout 的脚本绝对路径执行；脚本会定位主 checkout、共用任务池与锁。

完整规则、状态含义、锁与 worktree 说明：见 [WORKFLOW.md](WORKFLOW.md)。
配置：见 [config.env](config.env)。

## 说明文档

第一次使用先读 [docs/QUICKSTART.md](docs/QUICKSTART.md)（从写任务到合并归档的完整走查）。

| 文档 | 内容 |
| --- | --- |
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | 第一次使用：写任务、领取、讨论、批准、实施、送审、合并归档 |
| [docs/REFERENCE.md](docs/REFERENCE.md) | 状态、任务字段、方案批准格式、命令与配置速查 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 锁残留、worktree 冲突、review/done 被拒绝、恢复步骤 |
| [docs/MIGRATION.md](docs/MIGRATION.md) | 从旧 `.ai/`、`ai-loop` 迁移 |
| [WORKFLOW.md](WORKFLOW.md) | 完整执行规则（手动会话与 `run` 模式） |

## 常用只读检查

```bash
.ai-workflow/scripts/ai-workflow.sh next    # 可领取任务 + 等待讨论任务
.ai-workflow/scripts/ai-workflow.sh check   # 校验 status 与目录、id 与文件名、批准与归档证据
```
