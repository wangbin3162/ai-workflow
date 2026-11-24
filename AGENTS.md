# ai-workflow — AI 协作说明

用**用户手写**的 markdown 任务池驱动 AI 编码会话：任务进 `.ai-workflow/inbox/`，
agent 在独立 git worktree 里探索、讨论、实现、验证，结果进 `.ai-workflow/review/` 等人审。
技术栈：bash 脚本 + markdown，无第三方依赖。

对外只有一个技能入口：`skills/ai-workflow`（`/ai-workflow init|task|<提示词>`）。

## 改代码之前

按顺序读，别跳：

1. **`LESSONS.md`** — 近期踩过的坑和拦住它们的规则。**修改代码前阅读相关条目**，再动手。
2. **`docs/code-standards.md`** — 什么算「做完了」、提交信息怎么写、多久复盘一次。
3. 改状态机或任务池结构 → 先读 `docs/ARCHITECTURE.md`。
4. 改技能/初始化 → 读 `skills/ai-workflow/SKILL.md` 和 `references/design.md`。
5. 迁移旧任务/旧入口 → 读 `docs/MIGRATION.md`。

## 项目结构

```text
├── AGENTS.md / LESSONS.md / CLAUDE.md
├── .claude/loop.md            # 交互会话的薄入口（指向 /ai-workflow）
├── .ai-workflow/              # 本仓库示例任务池（inbox/discussion/doing/review/approved/done/blocked）
├── skills/ai-workflow/        # 唯一技能入口
│   ├── SKILL.md
│   ├── assets/                # 装进目标 .ai-workflow/ 的文件
│   ├── scripts/               # detect.sh / install.sh / verify.sh
│   ├── references/            # 设计说明、旧入口归档
│   └── evals/evals.json
├── scripts/
│   ├── ai-workflow.sh         # 任务池状态机
│   └── test-ai-workflow.sh    # 隔离回归测试
├── docs/                      # ARCHITECTURE / quickstart / code-standards / MIGRATION
└── archive/legacy-v1/         # 旧版模板归档（不是技能入口）
```

运行时产物（`.ai-workflow/.gitignore` 与根 `.gitignore` 均忽略）：`.ai-workflow/worktrees/`、`locks/`、`logs/`。

## 构建与测试

没有构建步骤。真实存在的检查命令：

- `bash -n scripts/ai-workflow.sh && bash -n scripts/test-ai-workflow.sh` —— 语法检查
- `bash scripts/test-ai-workflow.sh` —— 隔离回归测试（临时仓库 + 假 claude；不碰真实任务池）
- `DRY_RUN=1 scripts/ai-workflow.sh run` —— 只打印候选任务
- `scripts/ai-workflow.sh check` —— 校验状态/目录、批准与归档证据

测试基线与实测日期只记在 `docs/code-standards.md`。

## 硬性规矩

- **单一入口**：对外只提供 `ai-workflow` 技能；不再新增 `ai-loop-*` 技能入口。
- **初始化只写 `.ai-workflow/`**：不移动/替换/追加/修改目标项目的 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。
- **任务由人手写**：不提供自动创建任务的工具；`/ai-workflow task` 只出草稿，用户明确要求才写文件。
- **不自动合并**：不执行 `git merge`，不把 `ai/*` 合进业务分支。
- **不 push**：不执行 `git push`，不添加 / 修改 remote，不建 PR。
- **不发版、不改 CI**。
- **不自动提交任务状态**：脚本不 `git add/commit`；需要版本化时提示用户。
- **歧义先讨论**：`needs-discussion` 任务不得被自动领取；恢复需要用户明确批准当前方案版本与内容 sha。
- **审查通过 ≠ 合并**：`done` 必须有目标分支与合并提交证据；没有证据不归档。
- **不改他人 worktree / 不删 worktree/分支**：已有 diff、commit、worktree 一律保留。
- **`risk: high` 只出方案**：碰支付、鉴权、权限、依赖升级、公共接口、数据迁移、CI 的任务只写方案。
- **验收标准不能自己放宽**；没跑就写「未运行」。
- **不破坏用户已有改动**：不覆盖未提交改动；目标文件有未提交改动时只做追加式编辑。

## 约定

- **语言**：文档与注释用中文，命令与标识符保持原样。
- **格式**：bash 脚本保持 `set -euo pipefail`，改完跑语法检查。
- **依赖**：不新增第三方依赖；`jq` 为可选（用于解析 agent 汇报）。

## 文档索引

| 文档 | 什么时候读 |
| --- | --- |
| [`LESSONS.md`](LESSONS.md) | **修改代码前阅读相关条目** |
| [`docs/code-standards.md`](docs/code-standards.md) | 提交前、复盘时 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 改状态机、锁、worktree 之前 |
| [`docs/quickstart.md`](docs/quickstart.md) | 第一次在真实工程里使用 |
| [`docs/MIGRATION.md`](docs/MIGRATION.md) | 从旧 ai-loop / ai-loop-task 迁移 |
| [`skills/ai-workflow/SKILL.md`](skills/ai-workflow/SKILL.md) | 使用/修改技能时 |
| [`.ai-workflow/templates/task.md`](.ai-workflow/templates/task.md) | 写新任务时 |
