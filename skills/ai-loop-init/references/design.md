# 设计说明

给「用户追问为什么这么设计」或「要调整本技能」时看。完整的运行机制在装进工程的 `docs/ai-loop-architecture.md` 里，这里只讲取舍。

## 来源与取舍

- 三份文档（AGENTS / LESSONS / code-standards）、错题「毕业」、提交信息「跑了什么 / 没试过」证据包，来自全局技能 `project-init`；原因见它的 `references/why.md`。
- 任务池 + worktree + 无人值守脚本，是本技能在此之上加的一层。**这一层在作者自己的参考项目里没有真实运行记录**，所以模板里把「真实 `claude` 没跑通前不宣称可无人值守」写成了验收条目。
- `CLAUDE.md` 只放 `@AGENTS.md`：`project-init` 倾向不要 `CLAUDE.md`，但 Claude Code 实际读取的是 `CLAUDE.md`，所以保留一行转发，让 `AGENTS.md` 仍是唯一入口。

## 状态机与「谁管状态」

状态 6 个，目录即状态：`new`（inbox）→ `claimed`（doing）→ `needs_review`（review）→ `done`；`blocked`。没有 `in_progress` / `rejected`：从未被写入的状态只会让文档和脚本对不上。

两种运行方式的状态归属不同，不能混：

- 交互 `/loop`：agent 自己移文件、改 status，规则在 `.claude/loop.md`。
- 脚本 worker 模式：脚本管状态；agent 只在 worktree 里写代码，不写 `.ai/`，结论用汇报末行 `AI_LOOP_RESULT: done|blocked|failed` 传回。原因：agent 要跨目录写主 checkout 的文件，在 `acceptEdits` + 无人确认下很可能被拒，而且「agent 自报 blocked」只靠退出码和 commit 数判断不出来。

## 几个容易回头踩的决定

- `risk` 只认 `low`；缺失或写错按 `high`（只出方案）。原因：模板曾带行内注释，解析不剥注释时 `risk: high   # …` 会被当成 low，护栏悄悄失效。
- 白名单不放行 `npm *` / `node *` / `python *` 这类通配：它们能间接 `git push` 或装依赖。项目的测试命令用 `.ai/loop.env` 的 `PROJECT_TOOLS` 逐条写。
- 依赖安装由脚本通过 `WORKTREE_SETUP` 执行，不让 agent 装，也不软链主仓库的依赖目录：pnpm 会顺着软链改写主仓库的 `node_modules`（contract-review 项目 `LESSONS.md` 里有真实事故）。
- 状态迁移只提交该任务文件（`git commit -- <paths>`），不带走 inbox 里的草稿或用户已 staged 的改动。
- `doing/` 里没有锁的任务视为上次中断，下次运行开头按失败处理；worktree 目录已存在时不中断、不删该目录，按失败处理。

## 已知未验证 / 未做

- 真实 `claude -p` 的完整一轮（见装进工程的架构文档第 7 节）。
- `.claude/settings.json` 的 `permissions.deny` 与 `PreToolUse` hook 没生成：它们会影响工程里所有 Claude 会话，应由用户单独决定。
- `--max-turns` 在作者本机的 `claude --help` 里不存在，脚本默认不传。
- `assets/ai-loop.sh`、`assets/test-ai-loop.sh` 是从 `ai-loop-starter` 仓库 `scripts/` 复制来的；两处改动要手工同步。
