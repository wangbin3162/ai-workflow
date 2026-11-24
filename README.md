# ai-workflow

用一个**用户手写**的 markdown 任务池驱动 AI 编码会话：任务写进 `.ai-workflow/inbox/`，
agent 在独立 git worktree 里探索、讨论、实现、验证，结果进 `.ai-workflow/review/` 等人审。
**合并、push、发版永远由人做。**

项目原名 `ai-loop-starter`；现在对外只有一个技能入口：**`/ai-workflow`**。
本仓库不自动安装技能；需要你把 `skills/ai-workflow/` 放到 Claude Code 能发现的位置（位置由你决定）。

## 三个入口（同一个技能）

| 入口 | 用途 |
| --- | --- |
| `/ai-workflow init` | 在目标项目安全初始化 `.ai-workflow/`；只写这个目录，幂等，冲突就停 |
| `/ai-workflow task` | 按模板帮用户拆分/整理任务；不自动建任务、不实现 |
| `/ai-workflow <提示词>` | 领取用户手写任务 → 只读探索 → 有歧义先进讨论 → 批准后实施验证 → 送审 |

## 关键行为

- **初始化只写 `.ai-workflow/`**：不改目标项目的 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。
- **任务由人手写**：复制 `.ai-workflow/templates/task.md`；没有自动建任务的工具。
- **歧义先讨论**：任务进 `needs-discussion`，记录事实、问题、方案、建议；不会被自动再次领取。
- **恢复需要有版本的批准**：`plan_version` + 方案内容 sha256 + 用户原话；方案变化旧批准失效。
- **审查通过不等于合并**：`review → approved → done` 分开；done 必须有目标分支与合并提交证据。
- **两种运行方式共用锁**：手动 Claude/T3 会话与可选 `claude -p` 脚本不能抢同一个任务。
- **不自动提交任务状态、不合并、不 push、不删 worktree**。

## 在目标项目里的最短流程

```bash
# 在 Claude Code/T3 会话中：
/ai-workflow init

# 用户手写任务后：
.ai-workflow/scripts/ai-workflow.sh next
.ai-workflow/scripts/ai-workflow.sh claim T-20260101-001 --by 你的名字
# ……探索/讨论/实施……
.ai-workflow/scripts/ai-workflow.sh review T-20260101-001
.ai-workflow/scripts/ai-workflow.sh approve-review T-20260101-001 --commit <sha> --by 审查人 --note "通过"
# 人工合并后：
.ai-workflow/scripts/ai-workflow.sh done T-20260101-001 --target main --merged-commit <sha> --by 确认人 --note "已合并"
```

详细步骤见目标项目生成的 `.ai-workflow/WORKFLOW.md`，或源包 [docs/quickstart.md](docs/quickstart.md)。

## 源包结构

```text
skills/ai-workflow/          # 唯一技能入口（SKILL.md + assets + scripts + references + evals）
  assets/                    # 装进目标 .ai-workflow/ 的文件
  assets/docs/               # 目标项目内的 QUICKSTART / REFERENCE / TROUBLESHOOTING / MIGRATION
  scripts/                   # detect / install / verify
scripts/ai-workflow.sh       # 任务池状态机（源包版本）
scripts/test-ai-workflow.sh  # 隔离回归测试（临时 fixture + 假 claude）
.ai-workflow/                # 本仓库自己的示例任务池
docs/ARCHITECTURE.md         # 设计、状态机、锁、worktree、未验证项
docs/quickstart.md           # 第一次在真实工程里使用
docs/MIGRATION.md            # 旧 ai-loop / ai-loop-task 迁移
archive/legacy-v1/           # 旧版模板归档（不再被技能发现）
```

## 开发与检查

```bash
bash -n scripts/ai-workflow.sh && bash -n scripts/test-ai-workflow.sh
bash scripts/test-ai-workflow.sh          # 153 项隔离检查（模型调用全部 mock）
```

真实 `claude -p` 没有在真实项目里跑通一轮；跑通前不要把 `run` 当无人值守使用。
测试只证明脚本状态机、初始化与锁；不证明真实模型会遵守提示词。
