# 极简上手流程

适用于在一个真实工程里第一次试这套工作流：**先手动写需求、手动跑；稳定后再上自动化。**
机制和参数见 [ai-loop-architecture.md](ai-loop-architecture.md)（装进工程后的名字；本仓库里是 [ARCHITECTURE.md](ARCHITECTURE.md)）。

## 1. 初始化（一次性）

在目标工程目录里开 Claude Code，说：

> 初始化 AI 任务池工作流，别帮我提交。

- 它会先给计划。计划里出现 `MOVE` / `REPLACE`（动了你已有的 `AGENTS.md` 等文件），回复「确认」；原文件会原样搬到 `docs/legacy/`。
- 目标文件有未提交改动时它会停下，先自己提交或丢弃再来。
- 装完看汇报的三项：`TODO:` 列表、搬走了哪些文件、`.ai/loop.env` 里 `PROJECT_TOOLS` 填了什么。
- 自己核对新 `AGENTS.md` 里的构建 / 测试命令，再看 `git status`，没问题就**提交一次**，让任务分支基于干净的初始化状态。
- 没触发技能就直接说「用 ai-loop-init 初始化」。

## 2. 写一个需求

两种写法，文件格式相同。

**说一句话**：在工程目录里对 Claude 说：

> 新增任务：改订单列表的样式，参考某某文件，只改样式不改接口。

会按模板在 `.ai/inbox/` 追加一条 `status: new` 的任务，不开始做。没触发就说「用 ai-loop-task」。

**手写**：复制 `.ai/templates/task.md` 到 `.ai/inbox/<id>.md`（`id` 形如 `T-20261110-001`，与文件名一致），改这几处：

- `id`、`title`、`created`；`status` 保持 `new`；`risk` 先用 `low`。
- 背景：bug 写复现步骤和「期望 vs 实际」；界面优化写哪个页面、改成什么样；feature 写要解决的问题。
- 验收标准写**真实命令**，或写人工复现步骤和修改前后可区分的现象；不要写「跑一下测试」。
- front-matter 里不要写行内注释。
- 前 2~3 个任务选小需求，别一上来就做大的。

## 3. 手动跑一轮

在主目录的 Claude Code 里说：

> 按 `.claude/loop.md` 处理一个任务

交互模式下你能看到它在做什么。它会：领任务 → 建 worktree `.worktrees/<id>` 和分支 `ai/<id>` → 实现并验证 → 提交到任务分支 → 任务移到 `.ai/review/`。
需求不清它会停下来，任务进 `.ai/blocked/`，问题写在任务文件里。

## 4. 审查

```bash
git diff <主分支>...ai/<id>        # 看改动
cat .ai/review/<id>.md             # 看验证记录
```

看三件事：验证记录是不是真实命令和结果、有没有越界改动、「没试过」写没写。

## 5. 通过或拒绝

```bash
# 通过
git merge --no-ff ai/<id>
git worktree remove .worktrees/<id>
git branch -d ai/<id>
scripts/ai-loop.sh done <id>

# 拒绝
scripts/ai-loop.sh reject <id> "原因"
```

出现返工、误判、验证太薄，往 `LESSONS.md` 记一条（格式见该文件）。

## 6. 什么时候上自动化

连续 3~5 个任务都满足：验证记录是真实命令、没有越界改动、没有返工。然后：

1. 在 `.ai/loop.env` 填好 `PROJECT_TOOLS`（命令先在本机跑通，逐条写）和 `WORKTREE_SETUP`（依赖安装命令，没有就不填）。
2. 先 `DRY_RUN=1 scripts/ai-loop.sh` 看会选哪个任务。
3. 再手动 `scripts/ai-loop.sh` 跑几次，**第一次要盯着看**。
4. 稳定后才考虑 cron / launchd。

注意：真实 `claude -p` 在这套脚本下还没有跑通记录，以 [code-standards.md](code-standards.md) 第一章第 4 条为准：没跑通之前，不宣称可以无人值守。
