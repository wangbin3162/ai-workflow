# ai-loop-starter

用本地 markdown 任务池驱动 AI 循环的最小骨架：任务写进 `.ai/inbox/`，agent 在独立 git worktree 里实现，
结果进 `.ai/review/` 等人工审查合并。支持两种运行方式：

- Claude Code 交互会话内的 `/loop`
- `scripts/ai-loop.sh`（`claude -p` 无人值守，每次一个任务）

默认**不自动合并、不 push**，合并与发版由人完成。

## 快速开始

1. 读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，确认流程和参数。
2. 按 `.ai/templates/task.md` 写一个任务到 `.ai/inbox/<id>.md`，`status: new`。
3. 手动跑一轮：

```bash
DRY_RUN=1 scripts/ai-loop.sh
```

4. 确认候选正确后真正执行：

```bash
scripts/ai-loop.sh
```

5. 到 `.ai/review/` 看任务记录和 `ai/<id>` 分支 diff，人工合并后把任务移到 `.ai/done/`。

## 目录

```
CLAUDE.md              # 只做 import
AGENTS.md              # agent 规则与护栏
LESSONS.md             # 错题本
.claude/loop.md        # /loop 的循环提示词
.ai/                   # 任务池：inbox / doing / review / done / blocked
scripts/ai-loop.sh     # claude -p 无人值守脚本
docs/ARCHITECTURE.md   # 架构与参数说明
```

## 注意

- `.ai/inbox/EXAMPLE-T-20261110-001.md` 是格式示例，`status: example`，不会被领取，可删除。
- 第一次真正运行前，确认本机已安装并登录 `claude` CLI，且 git 已配置 user.name / user.email。
- 所有可调参数集中在 `scripts/ai-loop.sh` 顶部，支持环境变量覆盖，见 ARCHITECTURE。
