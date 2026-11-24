# ai-workflow — AI 协作说明

用**用户手写**的任务驱动 AI 编码会话：AI 只读探索 → 有歧义先讨论 → 用户批准方案 → 实施验证 →
人工审查 → 人工合并 → 归档。技术栈：bash + markdown，无第三方依赖。

对外只有一个技能入口：`skills/ai-workflow`（`/ai-workflow init|task|<提示词>`）。

## 改代码之前

1. **`LESSONS.md`** — 修改代码前阅读相关条目。
2. **`docs/code-standards.md`** — 什么算做完了、提交信息怎么写。
3. 改技能/初始化 → 读 `skills/ai-workflow/SKILL.md` 与 `references/design.md`。
4. 改任务模型/目录 → 读 `docs/ARCHITECTURE.md`。
5. 迁移旧结构 → 读 `docs/MIGRATION.md`。

## 项目结构

```text
├── AGENTS.md / LESSONS.md / CLAUDE.md
├── .claude/loop.md              # 交互会话薄入口
├── .ai-workflow/                # 示例任务池（README + TEMPLATE + inbox/doing/review/done/list）
├── skills/ai-workflow/          # 唯一技能入口
│   ├── SKILL.md
│   ├── assets/README.md         # 目标 .ai-workflow/ 的说明
│   ├── assets/TEMPLATE.md       # 目标 .ai-workflow/ 的任务模板
│   ├── scripts/                 # detect / install / verify（不随初始化分发）
│   ├── references/
│   └── evals/evals.json
├── scripts/test-ai-workflow.sh  # 初始化/结构回归测试
└── docs/                        # ARCHITECTURE / quickstart / MIGRATION / code-standards
```

## 构建与测试

- `bash -n skills/ai-workflow/scripts/*.sh` —— 语法检查
- `bash scripts/test-ai-workflow.sh` —— 初始化/结构回归测试（临时仓库，不碰真实 `.ai-workflow/`）
- `bash skills/ai-workflow/scripts/verify.sh <目标>` —— 目标项目结构验证

测试基线与实测日期只记在 `docs/code-standards.md`。

## 硬性规矩

- **单一入口**：对外只提供 `ai-workflow` 技能。
- **初始化只写 `.ai-workflow/`**：只生成 README、TEMPLATE 和五个目录；不碰 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。
- **不生成脚本/配置/额外文档**：任务流转由 AI 按 README 直接操作。
- **任务由人手写**：`/ai-workflow task` 只出草稿，用户明确要求才写文件。
- **歧义先讨论**：`needs-discussion` 不得被当作新任务领取；恢复需要用户明确批准当前方案版本与 sha。
- **审查通过 ≠ 合并**：`done` 必须有目标分支与合并提交证据。
- **不自动提交任务状态、不自动合并、不 push、不删 worktree/分支。**
- **`risk: high` 只出方案**；验收标准不能自己放宽；没跑写「未运行」。
- **不破坏用户已有改动**：不覆盖未提交改动。

## 约定

- 文档与注释用中文；脚本保持 `set -euo pipefail`。
- 不新增第三方依赖。

## 文档索引

| 文档 | 什么时候读 |
| --- | --- |
| [`LESSONS.md`](LESSONS.md) | 修改代码前 |
| [`docs/code-standards.md`](docs/code-standards.md) | 提交前、复盘时 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 改任务模型/目录/锁/worktree |
| [`docs/quickstart.md`](docs/quickstart.md) | 第一次使用 |
| [`docs/MIGRATION.md`](docs/MIGRATION.md) | 从旧 .ai / v1 / v2 迁移 |
| [`skills/ai-workflow/SKILL.md`](skills/ai-workflow/SKILL.md) | 使用/修改技能 |
| [`skills/ai-workflow/assets/README.md`](skills/ai-workflow/assets/README.md) | 初始化到目标项目的执行规则 |
| [`skills/ai-workflow/assets/TEMPLATE.md`](skills/ai-workflow/assets/TEMPLATE.md) | 初始化到目标项目的任务模板 |
