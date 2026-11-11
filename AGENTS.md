# ai-loop-starter — AI 协作说明

用本地 markdown 任务池驱动 AI 循环的脚手架：任务写进 `.ai/inbox/`，agent 在独立 git worktree 里实现，
结果进 `.ai/review/` 等人审。技术栈：bash 脚本 + markdown，无第三方依赖。

## 改代码之前

按顺序读，别跳：

1. **`LESSONS.md`** — 近期踩过的坑和拦住它们的规则。**修改代码前阅读相关条目**，再动手。
2. **`docs/code-standards.md`** — 什么算「做完了」、提交信息怎么写、多久复盘一次。
3. 改 `scripts/` 或任务池结构 → 先读 `docs/ARCHITECTURE.md`。
4. 处理任务 → 交互会话按 `.claude/loop.md`；任务文件格式看 `.ai/templates/task.md`。

三份文件分工：本文件说「去哪找」，`LESSONS.md` 装近期错题（**会毕业，所以短**），`docs/code-standards.md` 装已经站住的硬规矩。

## 项目结构

```text
├── AGENTS.md / LESSONS.md / CLAUDE.md
├── .claude/loop.md          # 交互会话（/loop）的每轮提示词
├── .ai/                     # 任务池：inbox / doing / review / done / blocked / templates
├── scripts/
│   ├── ai-loop.sh           # claude -p 无人值守脚本 + done/reject/check 子命令
│   └── test-ai-loop.sh      # ai-loop.sh 的回归测试
└── docs/                    # ARCHITECTURE.md、code-standards.md、reference/
```

- 运行时产物（已 gitignore，不要提交）：`.ai-locks/`、`.ai-logs/`、`.worktrees/`。

## 构建与测试

没有构建步骤。真实存在的检查命令：

- `bash -n scripts/ai-loop.sh && bash -n scripts/test-ai-loop.sh` —— 语法检查
- `bash scripts/test-ai-loop.sh` —— 回归测试（临时仓库 + 假 claude，不碰真实 `.ai/`；不支持按用例筛选）
- `DRY_RUN=1 scripts/ai-loop.sh` —— 只看会选哪个任务
- `scripts/ai-loop.sh check` —— 校验 `status` 字段与所在目录一致

测试基线与实测日期只记在 `docs/code-standards.md`，这里不重复。

## 硬性规矩

- **不自动合并**：不执行 `git merge`，不把 `ai/*` 合进主分支。
- **不 push**：不执行 `git push`，不添加 / 修改 remote，不建 PR。
- **不发版、不改 CI**：不碰 `.github/`、部署配置、release 流程。
- **`risk: high` 只出方案**：碰支付、鉴权、权限、依赖升级、公共接口、数据迁移、CI 的任务，
  只写拆解方案，交人批，不改代码。`risk` 缺失或写错，一律按 high。
- **不改他人 worktree**：每个 worktree 只属于创建它的任务。
- **worktree 里不要自己装依赖、不要软链主仓库的 `node_modules`**：装依赖走 `WORKTREE_SETUP`（见 `docs/ARCHITECTURE.md`）。
- **不做无关重构**：只改任务需要的文件；顺手发现的问题写成新任务放进 `.ai/inbox/`。
- **验收标准不能自己放宽**：验收标准由人写；做不到就报 blocked，不许改成「基本完成」。
- **没跑就写「未运行」**：验证记录写真实命令、commit sha、输出摘要；没跑写原因。
- **不破坏用户已有的改动**：不覆盖未提交的改动；目标文件有未提交改动时只做追加式编辑。

## 约定

- **语言**：文档与注释用中文，命令与标识符保持原样。
- **格式**：bash 脚本保持 `set -euo pipefail`，改完跑上面的语法检查。
- **依赖**：不新增第三方依赖；`jq` 为可选（用于把 agent 汇报写进任务文件）。

## 提交与复盘

提交信息、验证披露、复盘触发条件和错题毕业规则，统一遵循 `docs/code-standards.md`。

## 文档索引

| 文档 | 什么时候读 |
| --- | --- |
| [`LESSONS.md`](LESSONS.md) | **修改代码前阅读相关条目** |
| [`docs/code-standards.md`](docs/code-standards.md) | 提交前、复盘时 |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 改脚本或任务池结构之前 |
| [`docs/quickstart.md`](docs/quickstart.md) | 第一次在真实工程里试这套流程时 |
| [`.claude/loop.md`](.claude/loop.md) | 在交互会话里处理任务时 |
| [`.ai/templates/task.md`](.ai/templates/task.md) | 写新任务时 |
| [`skills/ai-loop-task/SKILL.md`](skills/ai-loop-task/SKILL.md) | 把一句话需求转写成 inbox 任务，不实现 |
| [`docs/reference/magpie-ai-loop-guide.md`](docs/reference/magpie-ai-loop-guide.md) | 想知道设计来源时（参考资料，部分建议未落地） |
