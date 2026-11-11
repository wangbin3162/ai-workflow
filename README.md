# ai-loop-starter

用本地 markdown 任务池驱动 AI 循环的最小骨架：任务写进 `.ai/inbox/`，agent 在独立 git worktree 里实现，
结果进 `.ai/review/` 等人工审查合并。支持两种运行方式：

- Claude Code 交互会话内的 `/loop`（状态归 agent 管）
- `scripts/ai-loop.sh`（`claude -p` 无人值守，每次一个任务，状态归脚本管）

默认**不自动合并、不 push**，合并与发版由人完成。

> 状态：脚本逻辑已有回归测试（`bash scripts/test-ai-loop.sh`），但**还没用真实 `claude` 跑通过一轮**。
> 跑通前不要当无人值守用，见 `docs/ARCHITECTURE.md` 第 7 节。

## 快速开始

第一次在真实工程里试：先看 [docs/quickstart.md](docs/quickstart.md)（极简流程：初始化 → 写需求 → 手动跑 → 审查 → 稳定后再自动化）。下面是本仓库自身的说明。

1. 读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，确认流程和参数。
2. 按 `.ai/templates/task.md` 写一个任务到 `.ai/inbox/<id>.md`，`status: new`（front-matter 不要写行内注释）。也可以说「新增任务：…」，由 ai-loop-task 按模板追加一条，不开始做。
3. 先看会选哪个任务：

```bash
DRY_RUN=1 scripts/ai-loop.sh
```

4. 填上项目的测试命令后真正执行（`PROJECT_TOOLS` 为空 agent 跑不了测试）：

```bash
PROJECT_TOOLS='Bash(make test)' scripts/ai-loop.sh
```

5. 到 `.ai/review/` 看任务记录和 `ai/<id>` 分支 diff；人工合并后归档：

```bash
scripts/ai-loop.sh done <id>
```

拒绝则 `scripts/ai-loop.sh reject <id> "原因"`。随时可用 `scripts/ai-loop.sh check` 校验状态与目录是否一致。

## 目录

```
CLAUDE.md                # 只含 @AGENTS.md
AGENTS.md                # 路由表 + 硬性规矩
LESSONS.md               # 错题本（≤5 条，3 次复发后毕业）
.claude/loop.md          # 交互会话的每轮提示词
.ai/                     # 任务池：inbox / doing / review / done / blocked / templates
scripts/ai-loop.sh       # 无人值守脚本 + done / reject / check 子命令
scripts/test-ai-loop.sh  # 回归测试（临时仓库 + 假 claude）
docs/ARCHITECTURE.md     # 架构、参数、未验证风险
docs/code-standards.md   # 验收标准、提交信息、复盘与毕业规则
```

## 注意

- `.ai/inbox/EXAMPLE-T-20261110-001.md` 是格式示例，`status: example`，不会被领取，可删除。
- 第一次真正运行前，确认本机已安装并登录 `claude` CLI，且 git 已配置 user.name / user.email。
- 脚本把 `ai: claim/review/...` 的状态提交写在当前分支，且只包含该任务文件；想保持主分支历史干净，请在专门分支上运行。
- 项目要装依赖时用 `WORKTREE_SETUP`，不要软链 `node_modules`。
- 所有可调参数集中在 `scripts/ai-loop.sh` 顶部，支持环境变量覆盖，见 ARCHITECTURE。
