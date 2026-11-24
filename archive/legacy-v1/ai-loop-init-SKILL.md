---
name: ai-loop-init
description: 在当前工程里初始化一套「AI 任务池工作流」——AGENTS.md 路由与护栏、LESSONS.md 错题本、docs/code-standards.md 验收标准、.ai/ 任务池（inbox/doing/review/done/blocked）、.claude/loop.md、scripts/ai-loop.sh 无人值守脚本与回归测试。工程里已有 AGENTS.md / CLAUDE.md / LESSONS.md / code-standards.md 时，不覆盖：原样搬到 docs/legacy/ 再引用。只要用户提到「初始化 AI 工作流 / 任务池 / ai-loop / 让 AI 自动领任务」「给这个项目加上 AGENTS.md + 错题本 + 任务队列」「用 worktree 让 agent 跑任务」「按我那套 ai-loop 工作流搭一下」，或在一个新工程里要求搭建 agent 协作流程，即使没说出技能名，也要使用本技能。只想审阅或改进已有 AGENTS.md、不要任务池时，用 project-init。
---

# AI 任务池工作流初始化

在**当前工程**里装好一套可运行的 AI 协作骨架：agent 读规则 → 从 `.ai/inbox/` 领任务 → 在独立 worktree 里实现 → 结果进 `.ai/review/` 等人审。**合并、push、发版永远由人做。**

## 先搞清楚两件事

- **和 `project-init` 的关系**：`project-init` 只做三份文档（AGENTS / LESSONS / code-standards），适合日常开发；本技能在同样的三份文档之上再加任务池和脚本。用户只要文档、不要任务池时，用 `project-init`。
- **为什么这么设计**：agent 的上下文每次会话都清空，没写下来的东西下次就丢；所以规则分三个寿命（AGENTS 稳定、LESSONS 短而易腐、code-standards 慢慢长），错题踩够 3 次「毕业」成硬规矩。任务池的状态只由一方维护（脚本模式归脚本，交互模式归 agent），避免两边互相覆盖。细节见 `references/design.md`。

## 流程

### 0. 确认目标

目标 = 用户当前所在的工程根目录（不是本技能目录）。它必须是**有至少一个提交的 git 仓库**（worktree 和任务分支依赖它）；不是就告诉用户先 `git init` 并提交，不要替他做。

目标里会被写入或搬走的规则文件（`AGENTS.md`、`CLAUDE.md`、`LESSONS.md`、`docs/code-standards.md`、`.claude/loop.md`）若有未提交改动，安装会被拒绝——这些改动没有历史保护。`detect.sh` 会用 `BLOCKER:` 行提前列出。碰到时停下，对用户说：「`<文件>` 有未提交改动，请你先提交（要保留）或自己丢弃（不要），告诉我后我再继续」。不要替用户 commit、stash、checkout 或 reset。

### 1. 侦察（只读）

```bash
bash <skill-dir>/scripts/detect.sh <目标>
```

读输出里的：已有规则文件、是否已初始化、文档语言、依赖安装与测试命令的**线索**。再读目标的 `README.md` 和已有的 `AGENTS.md`（若有），弄清项目是什么、怎么构建、怎么测。线索不是事实——写进文档前自己跑一次。

**验证命令不能弄脏用户的工程。** 安装类命令（`pnpm install`、`npm ci`、`uv sync` 之类）会改写 lockfile、生成 `node_modules` / `.venv`，这是用户的文件。只验证测试 / 构建命令；安装命令要验证就在临时副本里跑（`cp -R` 到 `/tmp`，或 `git worktree add`），或者只核对 lockfile 非空、命令拼写对。每次跑完用 `git status` 确认工作区没被改，改了就还原并在汇报里说。

### 2. 出计划，必要时确认

```bash
bash <skill-dir>/scripts/install.sh --target <目标>        # 默认 --plan，不改任何文件
```

- 输出里有 `MOVE` 或 `REPLACE`（动了用户已有文件）→ **把计划原样给用户看，等他确认再往下**。这些文件是他的东西，原样搬出虽然不丢内容，但路径变了，他有权先知道。规则细节见 `references/existing-docs.md`。
- 只有 `CREATE` / `APPEND` / `REFERENCE` → 没有动用户已有文件，不用等确认，直接执行，所有事实在第 7 步一次汇报清楚。
- 脚本报错（目标文件有未提交改动、已有不是本技能生成的 `.ai/`、已初始化）→ 停下，把原因和最小的解法告诉用户，不要绕过去。

### 3. 执行

```bash
bash <skill-dir>/scripts/install.sh --target <目标> --apply
```

不会 `git add` / `commit`；提交由用户决定。

### 4. 填模板（这一步决定文档有没有用）

`AGENTS.md` 和 `docs/code-standards.md` 里留着 `{{...}}` 占位符（可能跨多行），全部替换成真实内容并删掉文件顶部的「填写说明」注释块：

- **只写真实存在、能跑的命令**。能执行的先执行一次；跑不了的保留命令并写 `TODO:` 说明缺什么。写了不存在的命令，agent 会「跑」它并报告成功，比没写更糟。
- **一个事实只放一处**。有 `docs/legacy/AGENTS.md` 时，项目自己的构建、约定留在那里，`AGENTS.md` 的「构建与测试」只写已核实的命令并链接过去，不要整段复制（复制品会和原文漂移）。
- **不知道就写 `TODO:` 加具体问题**，别猜。不适用的小节直接删。
- **文档语言跟随仓库**（detect 的 `language`，依据是已有规则文件优先、其次 README 的汉字数）；英文仓库要翻译的是面向读者的四份：`AGENTS.md`、`LESSONS.md`、`docs/code-standards.md`、`.claude/loop.md`。`docs/ai-loop-architecture.md`、`.ai/templates/task.md`、`.ai/loop.env` 的注释体量大或会被人复制，保持中文也可以，但要在汇报里说明没翻。依据很弱（文件几乎是空的）时，问用户一句，别默认。
- **校准阈值并写下理由**：复盘频率和 `LESSONS.md` 体量上限要匹配项目能承受的投入——个人项目按需复盘、≤5 条；小团队 ≤8 条；高频多 agent ≤12 条。选定后同步改 `docs/code-standards.md` 和 `LESSONS.md` 里的数字。写了做不到的标准，两周后没人看，反而污染每次会话。
- 无测试框架的项目，把验收第 1 条改成可执行的替代（人工复现步骤 + 修改前后可区分的现象），不要留一条做不到的标准。
- 项目特有的红线（凭据不入库、生成物不手改等）写进 `AGENTS.md` 硬性规矩，从 legacy 文件里找，核对后再写。

### 5. 配 `.ai/loop.env`

按 detect 的线索和你实际跑通的命令，取消注释并填 `PROJECT_TOOLS`（agent 能跑的测试 / 构建命令，逐条写，不用 `npm *` / `python *` 这类通配）和 `WORKTREE_SETUP`（依赖安装）。没验证过的不填。项目没有第三方依赖、不需要安装步骤时，`WORKTREE_SETUP` 保持注释并在旁边写一句原因。`PROJECT_TOOLS` 为空时脚本会警告：agent 只能读写文件，跑不了测试——这是合法的初始状态，但要在汇报里说。

### 6. 机械验证

```bash
bash <skill-dir>/scripts/verify.sh <目标>
```

检查必需文件、占位符、AGENTS.md 里的链接、legacy 文件是否被引用、脚本语法、`scripts/test-ai-loop.sh` 回归测试、`ai-loop.sh check`。有 FAIL 就修到通过；WARN（如 TODO）不用修，但要列进汇报。注意：它会跑脚本回归测试和 `check`，在工程里留下空的 `.ai-locks/`、`.ai-logs/`、`.worktrees/`——它们已被 `.gitignore` 忽略，是脚本的运行时产物，不用清理。`verify.sh` 不检查 `LESSONS.md` 的体量上限与 `code-standards.md` 的复盘档位是否一致，选档后自己对一遍。

### 7. 汇报（3~5 行，说事实）

- 模式：全新 / 已有文件被搬出（列出 `原路径 → docs/legacy/…`）
- 选定的校准值和理由
- 开放的 `TODO:` 清单
- **未验证**：真实 `claude -p` 在这个工程里没跑过，跑通前不要当无人值守用；`PROJECT_TOOLS` 里没实测的命令
- 一个下一步：说「新增任务：…」（ai-loop-task）或手写一个小任务到 `.ai/inbox/`，然后 `DRY_RUN=1 scripts/ai-loop.sh` 看候选，再完整跑一轮；提交文件由用户决定

## 不要做

- 不覆盖、不改写用户已有文件的内容；只能整份搬到 `docs/legacy/` 后新建。
- 不 `git add` / `commit` / `push`，不动 CI。
- 已初始化（`AGENTS.md` 里有 `ai-loop-init:v1`）就停，不重复安装。
- 不编造测试基线数字、错题或命令输出；`LESSONS.md` 保持「暂无」是正确状态。

## 文件

- `scripts/detect.sh` — 只读侦察；`scripts/install.sh` — 计划 / 执行安装；`scripts/verify.sh` — 机械验证
- `assets/` — 要装进工程的文件模板（`ai-loop.sh`、`test-ai-loop.sh`、`AGENTS.md.template` 等）
- `references/existing-docs.md` — 工程已有规则文件时的搬运与引用细则
- `references/design.md` — 设计原因、状态机、两种运行模式、已知风险
- `evals/evals.json` — 本技能的测试用例
