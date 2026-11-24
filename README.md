# ai-workflow

用**用户手写**的任务驱动 AI 编码会话：AI 只读探索 → 有歧义先讨论 → 用户批准方案 → 实施验证 →
人工审查 → 人工合并 → 归档。**AI 不合并、不 push、不删除 worktree。**

对外只有一个技能入口：**`/ai-workflow`**（`init` / `task` / 加提示词）。
项目原名 `ai-loop-starter`；本仓库不自动安装技能，需要你把 `skills/ai-workflow/` 放到
Claude Code 能发现的位置。

## 初始化后只有这些

```text
.ai-workflow/
├── README.md      # 说明 + 状态表 + AI 执行流程
├── TEMPLATE.md    # 任务模板
├── inbox/         # new / needs-discussion / blocked
├── doing/         # claimed
├── review/        # needs_review / review_approved
├── done/          # done
└── list/          # 临时任务列表/方案草稿，供 AI 拆分
```

不生成脚本、`config.env`、`docs/`、`templates/` 或 `.gitignore`。
任务流转由 AI 直接操作任务文件和 git；`.ai-workflow/` 是否纳入版本控制由项目自己决定。

## 三个入口（同一个技能）

| 入口 | 用途 |
| --- | --- |
| `/ai-workflow init` | 只写 `.ai-workflow/README.md`、`TEMPLATE.md` + 五个目录；幂等，旧结构不自动升级 |
| `/ai-workflow task` | 按 TEMPLATE 整理任务草稿；分析 `list/` 里的列表拆分任务；默认不写 inbox |
| `/ai-workflow <提示词>` | 领取任务 → 只读探索 → 讨论/批准 → 实施验证 → 送审 |

## 关键行为

- **歧义先讨论**：`needs-discussion` 在 `inbox/`，不得被当作新任务领取。
- **恢复需要有版本的批准**：`plan_version` + 「## 方案」sha256 + 用户原话；方案变化旧批准失效。
- **审查通过不等于合并**：`review_approved` 仍留在 `review/`；`done` 必须有目标分支与合并提交证据。
- **两种写者共用任务锁**：`.ai-workflow/.locks/<id>/`（`mkdir`），会话异常后由人确认再删。
- **不自动提交任务状态、不合并、不 push、不删 worktree**。

## 最短流程

```bash
# 在目标项目（Claude Code/T3 会话）
/ai-workflow init

# 用户按 .ai-workflow/TEMPLATE.md 手写任务；列表可放 .ai-workflow/list/
# 在会话里：
/ai-workflow task 分析 list/需求列表.md 并拆分任务
/ai-workflow 处理 T-20260101-001
```

AI 会按 `.ai-workflow/README.md` 完成领取、探索、讨论、批准、实施、验证、送审；
人工审查、合并、归档同样按该文件执行。

## 源包结构

```text
skills/ai-workflow/          # 唯一技能入口
  SKILL.md
  assets/README.md           # 目标 .ai-workflow/ 的说明与执行规则
  assets/TEMPLATE.md         # 目标 .ai-workflow/ 的任务模板
  scripts/                   # detect / install / verify（技能自身工具，不随初始化分发）
  references/                # 设计说明、旧入口归档
  evals/evals.json
scripts/test-ai-workflow.sh  # 初始化/结构回归测试
docs/                        # ARCHITECTURE / quickstart / MIGRATION / code-standards
```

## 开发与检查

```bash
bash -n skills/ai-workflow/scripts/*.sh
bash scripts/test-ai-workflow.sh     # 47 项隔离检查
bash skills/ai-workflow/scripts/verify.sh <目标项目>
```

真实 `claude -p` 没有在真实项目里验证；本工作流不随初始化分发运行脚本，
任务流转由会话里的 AI 按 README 执行。
