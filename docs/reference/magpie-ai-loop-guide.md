# 复刻 magpie 的「AI 循环维护」工作流：调研与落地指南

> 调研日期：2026-11-09（北京时间）。仓库快照：`yetone/magpie` main @ `8f72f9530`（2026-11-09 23:08 北京时间）。
> 标注：【官方】= magpie 仓库原文 / yetone 本人发言 / Anthropic 官方文档；【社区】= 第三方文章、帖子；【未证实】= 有人说但我没核实到；【我的推断】= 我根据证据推出来的，或者是我建议的做法。
> 所有链接在 2026-11-09 用 curl 检查过，返回 200。X 帖子时间已换算成北京时间。

---

## 0. 一句话结论

- **magpie 实际做了什么**：yetone 在本机的 Claude Code 里，用官方 Opus 5.5 **同时开 3 个 `/loop`**：①盯 GitHub issue/PR 和 Discord；②盯 X 上的反馈；③定期清理烂代码、写经验教训、拉黑低质量贡献者。每晚他自己只花一点时间修 UI/UX。【官方】[yetone 原帖，2026-10-13 11:56](https://x.com/yetone/status/2109855710444237018)
- **这套循环不在 GitHub Actions 里跑，仓库也没有 `.claude/` 目录。** 3 条 loop 提示词只出现在帖子截图里，没有提交进仓库。仓库里放的是 loop 依赖的“规则书”：`CLAUDE.md → AGENTS.md → LESSONS.md / docs/code-standards.md / docs/contributors.md`。【官方】（我 clone 仓库后核实）
- **真正值得抄的不是提示词**，而是 4 样东西：①错题本 `LESSONS.md`（同一条教训在 3 个不同日子出现，就升级成硬规则）；②写死的验收标准（必须有“去掉修改就会失败”的测试，没跑的检查要写“没跑”）；③在真实的三端环境里复现；④人只守几道闸门。【官方】
- **你的项目可以没有 issue 渠道**：用 `.ai/inbox/*.md` 当任务池，让 `/loop` 或 `claude -p` 的脚本按“扫描→认领→在 worktree 里实现→测试→等人审→归档”来跑。这比 magpie 保守，**默认不自动合并、不自动发版**。【我的推断】见第 5 节。

---

## 1. magpie 仓库本身：实际有什么

### 1.1 基本信息
- 正确仓库：<https://github.com/yetone/magpie>（官网 usemagpie.ai）。它是本地 AI 网关桌面应用，Go 写的。【官方】
  - ⚠️ 别搞混：`magpie.apache.org`（Apache Magpie）是另一个项目，那里的 `spec-loop` 和 yetone 无关。
- 截至 2026-11-09：约 3.3 万星，7078 个 commit，3427 个 tag。最早的 commit 在 2026-09-22 21:47（北京时间）。【官方】GitHub API / git log
- 6293 个 commit 的作者是 `yetone <yetoneful@gmail.com>`。commit 里很少写 AI 署名：`Co-authored-by: Claude Opus 5.5` 加 `Co-Authored-By: Claude...` 合计不到 50 条。另有 112 条 `Generated-by: GLM-5.3-Flash (ZCode)`，基本来自社区贡献者。**也就是说，agent 是以 yetone 本人的 git 身份提交的，没有 bot 账号。**【官方】（`git log` 统计）+【我的推断】（“agent 用本人身份”是从文档说法和提交量推出来的）
- 2026-11-03 至 11-09，每天 87–183 个 commit。【官方】git log

### 1.2 agent 相关文件（这些都在）
| 文件 | 作用 | 来源 |
|---|---|---|
| `CLAUDE.md` | 只有两行：`@AGENTS.md`、`@LESSONS.md`（用 import 引入另外两个文件） | 【官方】[CLAUDE.md](https://github.com/yetone/magpie/blob/main/CLAUDE.md) |
| `AGENTS.md` | 路由表：改子系统先读 `docs/subsystems/`；写代码、审代码照 `docs/code-standards.md`；审社区 PR 先读 `docs/contributors.md`；改代码前先读 `LESSONS.md` | 【官方】[AGENTS.md](https://github.com/yetone/magpie/blob/main/AGENTS.md) |
| `LESSONS.md` | 第一句：“magpie's code is written, reviewed, merged and released by agents. Each night the day's commits are reviewed…”。每条教训写成“规则 / 原因 / 证据（commit、issue 号）/ Seen N×”。**同一条在 3 个以上不同日子出现，就移进 code-standards.md** | 【官方】[LESSONS.md](https://github.com/yetone/magpie/blob/main/LESSONS.md) |
| `docs/code-standards.md` | 审查规则表和 **Acceptance criteria**：去掉修改测试必须失败；测试在临时 HOME 沙箱里跑；`gofmt`、三平台 vet/build、`go test ./...`；GUI 测试要在 Chromium 和 WebKit 两个引擎、多语言下都跑；能用真账号验证就要验证；“A check that wasn't run is listed as not run”；合并用 `gh pr merge --match-head-commit <reviewed sha>` | 【官方】[code-standards.md](https://github.com/yetone/magpie/blob/main/docs/code-standards.md) |
| `docs/contributors.md` | 审社区 PR 的规则：**先查有没有危害**。碰 `.github/`、发布脚本、Dockerfile，加网络地址、依赖、编码 blob 等，一律停下等维护者。哪些 PR 不审直接关；什么条件下拉黑。**“An agent only proposes… the maintainer decides.”** 那个 PR 还有一句“Never merge it in the same tick it was opened” | 【官方】[contributors.md](https://github.com/yetone/magpie/blob/main/docs/contributors.md) |
| `docs/subsystems/*.md` | 每个子系统一份设计参考，供 agent 改代码前读 | 【官方】 |

### 1.3 不在仓库里的东西（实测确认）
- **没有** `.claude/`（没有 commands、skills、hooks、agents、settings），也没有 `.codex/`、`.cursor/`、`loop.md`。【官方】（`find` 核实）
- `.github/workflows/` 共 8 个：`test.yml`、`release.yml`、`docker*.yml`、`notes-mirror.yml`、`privacy-filter.yml`、`ui-preview.yml`。**没有一个调用 Claude 或 `claude-code-action`。** 唯一用到 AI 的是 `ui-preview.yml`：它给 DeepSeek 看 PR 的 diff，让它规划截图和录屏场景，再用 Playwright 录屏，结果贴进 PR 描述。【官方】[ui-preview.yml](https://github.com/yetone/magpie/blob/main/.github/workflows/ui-preview.yml)
- 现在**不接受外部 PR**。README 写着“This repository doesn't take pull requests. Only maintainers can open them”，反馈要发到 Discord。这句话是 2026-10-09 加进 README 的（commit `b91569d31`）。所以“自动合并社区 PR”主要发生在 10 月上旬，现在主要处理 issue 和 Discord。【官方】
- GitHub labels 只有默认那几个（bug/enhancement/…），**没有用 label 做状态机**。【官方】API

### 1.4 issue 和 commit 里的 AI 痕迹（它是怎么跑起来的）
- **认领协议是在评论里写 “take” 或 “Taking this now”。** 比如 [#5800](https://github.com/yetone/magpie/issues/5800)（2026-11-09 22:35）里 yetone 账号写“Taking this now: a mutex on `asked`…”。没接手的会话会写“Not taking it: recording the numbers for whoever has it.”【官方】（issue 评论 API）
- **agent 会自己开 issue 记录红测试**，标题像“gui tests: i18n-keys … red on main 9d143eaca”，修好后再自己关掉。【官方】
- **commit 正文里写验证记录**，比如“Run on mote at the pushed head (rebased onto be9dbce02): gofmt -l clean; go vet …: ok”，还会写反馈来源，比如“Jevik_AI on X”。`mote` 应该是跑 agent 的那台机器。【官方】+【我的推断】
- **并行会话会撞车，规则也是从撞车里长出来的。** LESSONS.md 记录过：两个会话在同一个 checkout 里提交，把对方的文件混进了自己的 commit；一个会话把另一个会话的 worktree 切走；多个会话同时跑测试套件把机器拖到 load 313。于是有了这些规则：“Two sessions never commit from the same checkout”“A checkout, worktree or log belongs to the session that made it”，以及用 `lockf ~/suite.lock` 让测试套件排队，一台机器同时只跑一套。【官方】LESSONS.md
- 有一个叫 ggbdpq 的协作者，评论风格也很像 agent（长篇根因分析加“take”）。他是不是也在跑 agent，**未证实**。

**小结（magpie 实际怎么跑）**：本机 Claude Code 交互会话里开 3 个 `/loop`。agent 用 `gh` 和 browser use 读写 GitHub、Discord、X，直接在 main 上提交，打 tag 后由 CI 发版。规则靠 CLAUDE.md 引入的文档；记忆靠 Claude Code 的 memory；多个并行会话之间靠 issue 评论和锁文件协调。【官方】+【我的推断】（“直接在 main 上提交”：社区统计到 yetone 只开过 1 个 PR，【社区】[nuts digest 10-08](https://nuts.nvirellia.im/digests/2026-10-08-yetone-magpie-agent-workflow)）

---

## 2. yetone 本人的分享（X）

| 时间（北京时间） | 内容 | 链接 |
|---|---|---|
| 2026-10-13 11:56 | “我没有任何的魔法…就是用 Claude Code，然后用官方的 Opus 5.5 模型执行 loop…并行执行图里的 3 个 loop，然后每晚抽一点时间铲铲屎（主要是 UI/UX）”。附 3 张提示词截图 | 【官方】[原帖](https://x.com/yetone/status/2109855710444237018) |
| 10-13 12:00 | 关键补充：要把**真实运行环境**给 agent，一台 macOS、一台 Windows，Windows 上再开个 Linux 虚拟机，每次都在三端真实复现再修 | 【官方】[回复](https://x.com/yetone/status/2109856834010132602) |
| 10-13 13:04 | 决策依赖“claude code 那套简陋但有效的记忆系统和 repo 中的设计文档”。早期和 Claude Code 头脑风暴的内容被它记进了记忆文件 | 【官方】[回复](https://x.com/yetone/status/2109872805668147561) |
| 10-13 13:01 / 次日 03:43 | 只在一端装 agent，其他机器通过 ssh 连 | 【官方】[回复1](https://x.com/yetone/status/2109872149427315157)、[回复2](https://x.com/yetone/status/2110094084895654400) |
| 10-13 13:06 | “所有的操作都是 browser use”（回答“盯推特是不是用 tw cli”） | 【官方】[回复](https://x.com/yetone/status/2109873349426045168) |
| 10-13 14:33 | “基本上就是用 Jev 在前面拦一刀”（Jev 是便宜的决策模型，magpie 文档里叫 decision model `jev-*`） | 【官方】[回复](https://x.com/yetone/status/2109895290035859593)；仓库 `docs/subsystems/provider-plugins.md` |
| 10-14 04:49 | 被问 `/loop` 比 scheduled task 好在哪：“没有优势，目的就是监听而已，只要能达成目的，啥方式都可以” | 【官方】[回复](https://x.com/yetone/status/2110110702040219931) |
| 10-13 12:54 | 花费：Magpie 加 Alma 每月至少 400 美元，另外还有 200 美元的工作订阅。为了验证功能，订阅了所有已支持的供应商 | 【官方】[回复](https://x.com/yetone/status/2109870274833510739) |
| 10-14 03:24 | 为什么这么激进：magpie 要适配无数 agent 和供应商，注定是 UGC 式的，用户提需求、agent 实现。他也承认有副作用：功能堆砌、发版太快。之后的对策是把 Provider 和 Agent 插件化 | 【官方】[长帖](https://x.com/yetone/status/2110089344187056263) |

**3 条 loop 原文**（我直接从原帖图片读的，下面是转述要点。原文见 [Tony's Lab 全文照录](https://u1-lab.xiaoxia.io/yetone-loop-workflow/)）【官方】
1. `/loop` 盯 GitHub issues：判断值不值得做，做了就发版并回复，不做也要回复；中转站广告商统一回一句话，不要加进产品。PR 要逐行 review，**拉下来实际跑**，验证过才合并，不然就回复或者关掉。同时监控 Discord 所有频道，真正 @ 到人。
2. `/loop` 盯推特上关于 magpie 的反馈：有价值或者真实可复现的就修，上线后回复推文。**先用便宜的决策模型（jev）判断相关性，不相关就别转给主模型**，省 token。
3. `/loop` 定时清理烂代码和恶意代码，总结经验教训（哪些不该合、哪些验证不严），写进经验文件，并把老提交低质量代码的人拉黑。
- 注意：3 条都**没写间隔**，也就是用 `/loop <prompt>` 让 Claude 自己决定间隔。这一点是【我的推断】，依据是截图里没有 `5m` 这类参数。

> 别混淆：2026-10-31 yetone 说“Claude Code Provider 从 `claude -p` 改为直接用 Claude Code TUI”，这是 **magpie 产品**怎么驱动 Claude Code，不是他的开发工作流。【官方】（dotey 转推的内容）

---

## 3. 社区分析（按价值排序）

- **wquguru《yetone 的魔法：magpie 是怎么让 AI 自己维护项目的》**（X Article，2026-10-12 22:19）：统计了 19 天 2862 个 commit、1204 个 tag、合并 383 个社区 PR。拆解了 CLAUDE.md→AGENTS.md→LESSONS.md 的结构，以及“Seen 3× 就升级成规则”的机制。yetone 的原帖就是在引用这篇。【社区】[X 原帖](https://x.com/wquguru/status/2109650264601117141)｜[镜像全文](https://teapawt.org/wquguru/article/2109650264601117141)
- **nuts digest（2026-10-08 / 10-13 两篇，英文）**：最细的仓库考古。结论是“no `.claude/`… no AI review bots in CI”；yetone 只开过 1 个 PR，直接在 main 上工作；commit 按小时分布全天都有，符合 agent 24 小时在跑；loop 提示词不在仓库里。【社区】[10-08](https://nuts.nvirellia.im/digests/2026-10-08-yetone-magpie-agent-workflow)｜[10-13](https://nuts.nvirellia.im/digests/2026-10-13-yetone-magpie-loops)
- **Tony's Lab《三个 Loop，一个人铲屎》**（2026-10-14）：照录了 3 条提示词，指出这套流程的三个缺口：并行 agent 的工作区隔离和权限边界、跨渠道 bug 去重、“什么情况必须叫人”的规则。【社区】[链接](https://u1-lab.xiaoxia.io/yetone-loop-workflow/)
- **宝玉 @dotey 解读**（2026-10-14 03:04，754 赞）：【社区】[链接](https://x.com/dotey/status/2110084393255514268)
- **linux.do 讨论帖**（2026-10-12）：有人担心从外部渠道直接喂 agent 会被注入，建议先收进一个“池子”缓冲，再让 agent 处理。也有人抽样看了代码，认为质量不高但产品好用。【社区】[linux.do/t/topic/3011171](https://linux.do/t/topic/3011171)
- **@MindfulReturn（bittide 收录）**：把它和 DeepSeek SuperAgent 的工单引擎做了对比，认为“yetone 更多靠提示词与人工习惯”，SuperAgent 则由宿主强制白名单和权限。【社区】[链接](https://bittide.aicompass.dev/article/4643af0f-ef09-4401-8fa4-88a7b141898c?locale=zh)
- 其他：@Zhuangxg 建议先做一张“转交单”（来源、复现、验收）再交给编码 agent。【社区】[X](https://x.com/Zhuangxg/status/2109908229887062025)。[Yupo Niu 的 SDLC 量化视频页](https://portfolio.dissidia.tech/watch/yetone-sdlc)【社区】（内容我没细看）。
- HN 和 V2EX：**没搜到**专门分析 magpie 工作流的帖子。可能是搜索覆盖不到，不代表一定没有。

---

## 4. Claude Code 官方实现依据（只列我在文档里核实过的）

### 4.1 `/loop`（会话内循环）【官方】[scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks)
- `/loop 5m <prompt>`：固定间隔，单位支持 s/m/h/d，秒会向上取整到分钟。`/loop <prompt>`：由 Claude 每轮自己选间隔（1 分钟到 1 小时）。只写 `/loop`：跑内置的维护提示词，如果有 `loop.md` 就跑 `loop.md`。
- 可以循环一个 skill：`/loop 20m /review-pr 1234`。被标了 `disable-model-invocation: true` 的 skill 不会执行。
- `.claude/loop.md`（项目级，优先）或 `~/.claude/loop.md` 可以替换默认提示词，修改在下一轮生效，超过 25,000 字节的部分会被截断。
- **限制**：会话必须开着，而且空闲时才会触发；循环任务 **7 天后自动过期**；一个会话最多 50 个任务；有 jitter（时间抖动）；错过的不补跑。底层工具是 `CronCreate` / `CronList` / `CronDelete`。
- 停止：自己选间隔的 loop 按 `Esc`；固定间隔的 loop 要让 Claude 取消。

### 4.2 更持久的调度【官方】
- **Desktop 计划任务**：在本机跑，不用一直开着会话，但应用要开着、电脑要醒着。最小间隔：表单里是 1 小时，让 Claude 设可以到 1 分钟。可以勾选 **Worktree**，让每次运行都在独立的 git worktree 里。错过的运行在开机或唤醒后只补跑 1 次。每个任务可以单独设权限模式。[desktop-scheduled-tasks](https://code.claude.com/docs/en/desktop-scheduled-tasks)
- **Cloud 计划任务 / Routines**：在 Anthropic 云上跑，每次是一个全新的 clone，最小间隔 1 小时。[routines](https://code.claude.com/docs/en/routines)

### 4.3 Headless：`claude -p`【官方】[headless](https://code.claude.com/docs/en/headless)｜[cli-reference](https://code.claude.com/docs/en/cli-reference)
核实过的参数：
- `--max-turns N`：限制轮数，默认不限。
- `--max-budget-usd 5.00`：按客户端估算的费用封顶，可能略微超过，要留余量；子 agent 的花费也计入。
- `--output-format json|stream-json`、`--json-schema`：结构化输出。
- `--allowedTools "Bash(npm test *),Read,Edit"` 和 `--disallowedTools`：控制哪些工具可用、哪些要拦。
- `--permission-mode acceptEdits|auto|dontAsk|plan|bypassPermissions`。v2.1.302 起，`-p` 默认是 Manual 模式，需要审批的操作会被拒绝。
- `--permission-prompts none`（需要 v2.1.259+）：无人值守时，所有需要审批的操作直接拒绝，并告诉 Claude 不要重试。
- `--bare`：不加载 CLAUDE.md、hooks、skills 等，启动更快。**跑循环任务时别用**，否则规则文件不会加载。
- `--worktree/-w <name>`：在 `<repo>/.claude/worktrees/<name>` 里启动。文档里这个参数和 `-p` 能不能一起用，我**没找到明确说明**，所以下面的脚本改用 `git worktree add`。
- `-p` 模式下可以在提示词里写 `/skill-name` 来调用 skill。

### 4.4 Hooks【官方】[hooks](https://code.claude.com/docs/en/hooks)
- `PreToolUse` 可以 allow、deny、ask，能用来拦 `git push`、改 `.github/`、`rm -rf` 这类操作。
- `Stop` / `SubagentStop` 的 hook 返回 exit code 2，会把 Claude“打回去继续干”。输入里有 `stop_hook_active`，用它判断，避免无限打回。
- 注意：用 `@` 引用的文件不会触发 `PreToolUse`。

### 4.5 Subagents【官方】[sub-agents](https://code.claude.com/docs/en/sub-agents)
- frontmatter 里写 `isolation: worktree`，子 agent 就在临时 worktree 里干活（默认从默认分支切出）；没改动的话会自动清理。

### 4.6 GitHub Actions【官方】[github-actions](https://code.claude.com/docs/en/github-actions)｜[claude-code-action](https://github.com/anthropics/claude-code-action)
- `anthropics/claude-code-action@v1`。没写 `prompt` 时是交互模式（响应 `@claude` 评论）；写了 `prompt` 时是自动化模式，可以挂在任意事件或 cron 上。
- 自动化模式默认没有 shell 和 GitHub 权限，要用 `claude_args: '--allowedTools ...'` 授权。
- 公开仓库的定时任务，60 天没活动就会被 GitHub 停掉。
- 认证：`ANTHROPIC_API_KEY` 或 `CLAUDE_CODE_OAUTH_TOKEN`。

### 4.7 官方方法论
- Anthropic《Loop engineering: Getting started with loops》：按时间触发的 loop（`/loop`、`/schedule`）适合“任务不变、输入变化”的周期性工作；控制用量的办法是间隔设长一点，或者改成按事件触发。【官方】[链接](https://claude.com/resources/articles/getting-started-with-loops)

---

## 5. 落地方案：用本地 markdown 任务池驱动 AI 循环（我们建议的做法）

> 下面全是【我的推断】和建议，**我没在你的机器上实测过**。原则是：借用 magpie 的规则书、错题本、验收标准和认领协议，**比它保守**，默认人工合并、不自动发版。

### 5.1 目录结构
```
your-app/
├── CLAUDE.md                 # 只写 import：@AGENTS.md @.ai/LESSONS.md
├── AGENTS.md                 # 路由表：什么活先读哪份文档（学 magpie）
├── .ai/
│   ├── README.md             # 任务池规则（人看）
│   ├── inbox/                # 人写的新需求和 bug（status: new）
│   ├── doing/                # 已认领（status: claimed / in_progress）
│   ├── review/               # 等人审（status: needs_review），附验证记录
│   ├── done/                 # 人确认合并后归档
│   ├── blocked/              # 失败超过上限、需求不清、碰了闸门
│   ├── LESSONS.md            # 错题本：规则 / 原因 / 证据 / Seen N×
│   ├── STANDARDS.md          # 验收标准（错题本里 Seen≥3 的升级到这里）
│   └── templates/task.md
├── .ai-locks/                # 认领锁（加进 .gitignore，只在主 checkout 里）
└── .claude/
    ├── loop.md               # 裸 /loop 的默认提示词（见 5.3）
    ├── settings.json         # deny 规则和 hooks
    └── skills/ai-task/SKILL.md  # 可选：把“处理一个任务”写成 skill
```
为什么分成几个目录：靠 `git mv` 移动文件就是状态迁移，人一眼能看出每个任务在哪一步。`status` 字段和所在目录必须一致，不一致就当成异常，移到 `blocked/`。

### 5.2 任务文件模板 `.ai/templates/task.md`
```markdown
---
id: T-20261109-001          # 唯一，用 日期-序号
type: bug | feature | chore
title: 登录页在 Safari 下按钮错位
status: new                 # new → claimed → in_progress → needs_review → done | blocked | rejected
priority: P1                # P0 最高
created: 2026-11-09
claimed_by:                 # 会话名或 worktree 名，例如 loop-a
claimed_at:
attempts: 0                 # 每次失败 +1
max_attempts: 2             # 到上限就进 blocked/
branch:                     # ai/T-20261109-001
budget_usd: 3               # 单个任务的花费上限（传给 --max-budget-usd）
risk: low | high            # high = 碰支付、鉴权、依赖、CI、数据迁移，必须先出方案等人批
---

## 背景 / 现象
（bug：复现步骤、环境、期望 vs 实际、截图路径）

## 验收标准（必须可验证）
- [ ] 在 Safari 和 Chrome 下截图对比（Playwright WebKit + Chromium）
- [ ] 新增一个测试，去掉修改时失败
- [ ] `pnpm lint && pnpm typecheck && pnpm test` 全绿

## 不要做
- 不改 API 契约；不升级依赖

## AI 记录区（agent 追加，人不改）
### 拆解
### 验证记录（在哪个 commit 上跑了什么、输出是什么；没跑的写“未运行”）
### 失败记录
```

### 5.3 循环提示词（`.claude/loop.md`）
```markdown
你是本仓库的维护 agent。每一轮只处理**一个**任务，然后停下汇报。

1. 先读 AGENTS.md、.ai/STANDARDS.md、.ai/LESSONS.md。
2. 如果 .ai/review/ 里已有 ≥3 个待审任务，本轮什么都不做，只汇报“等人审”。（人审闸门，防止任务堆积）
3. 扫描 .ai/inbox/，按 priority、created 排序，取第一个 status: new 且 risk: low 的任务。
   risk: high 的任务只写拆解方案到记录区，改成 status: needs_review，移到 review/，不写代码。
4. 认领：执行 `mkdir .ai-locks/<id>`。失败就说明别的会话已认领，换下一个。
   成功后用 git mv 移到 doing/，填 claimed_by/claimed_at，status: claimed。
5. 建 worktree：`git worktree add ../wt/<id> -b ai/<id>`，后面所有改动只在这个 worktree 里做。
   不要在主 checkout 里改代码；不要碰别的会话的 worktree。
6. 需求不清就不要猜：在记录区写下问题，status: blocked，移到 blocked/，释放锁。
7. 实现：先写会失败的测试，再修。改完按 STANDARDS.md 跑完整检查（不是只跑你觉得相关的）。
   把命令、commit sha、输出摘要写进验证记录。没跑的写“未运行”及原因。
8. 失败：attempts+1，失败原因写进失败记录。attempts ≥ max_attempts 就移到 blocked/，释放锁，不要再试。
9. 成功：在分支上 commit（正文写验证记录）。任务改成 status: needs_review，移到 review/，释放锁。
   **不要 merge、不要 push 到 main、不要发版、不要改 .github/ 和依赖文件。**
10. 如果这一轮发现了“返工、误判、验证不严”的情况，往 .ai/LESSONS.md 追加或更新一条（规则 / 原因 / 证据 / Seen N× 日期）。
```
启动方式（在 Claude Code 交互会话里）【官方语法】：
- `/loop 30m`：每 30 分钟按 `loop.md` 跑一次。
- 或者直接 `/loop`：让 Claude 自己选间隔。
- 再开一个会话，每天跑一次复盘（相当于 magpie 的第 3 条 loop）：`/loop 1d 复盘今天 ai/* 分支和 .ai/done、.ai/blocked：哪些返工、哪些不该过、哪些验证太弱，更新 .ai/LESSONS.md；Seen 在 3 个不同日子出现的条目移进 .ai/STANDARDS.md，并单独列出来给我确认`
- 记住 `/loop` 任务 7 天会过期，而且依赖会话一直开着。要长期跑，就用 Desktop 计划任务并勾选 Worktree，或者用下面的脚本。

### 5.4 无人值守脚本版（`claude -p`，每个任务一个全新上下文）
```bash
#!/usr/bin/env bash
# scripts/ai-loop.sh — 每轮最多处理 1 个任务；用 launchd/cron 或手动 while 循环调用
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mkdir -p .ai-locks ../wt
[ "$(ls .ai/review 2>/dev/null | wc -l)" -ge 3 ] && { echo "review 队列已满，等人审"; exit 0; }

for f in $(ls .ai/inbox/*.md 2>/dev/null | sort); do
  id=$(basename "$f" .md)
  grep -q '^risk: high' "$f" && continue
  mkdir ".ai-locks/$id" 2>/dev/null || continue        # 原子认领：mkdir 只有一个进程能成功
  trap 'rmdir ".ai-locks/$id" 2>/dev/null || true' EXIT
  git worktree add "../wt/$id" -b "ai/$id" >/dev/null
  git mv "$f" ".ai/doing/$id.md" && git commit -qm "ai: claim $id"
  ( cd "../wt/$id" && claude -p "按 .claude/loop.md 第 5–10 步处理任务 $id（任务文件在主仓库 .ai/doing/$id.md 的副本中）。" \
      --max-turns 60 --max-budget-usd 3 \
      --permission-mode acceptEdits --permission-prompts none \
      --allowedTools "Read,Edit,Write,Bash(pnpm *),Bash(git add *),Bash(git commit *),Bash(git diff *),Bash(git status *)" \
      --disallowedTools "Bash(git push *),Bash(git merge *),Bash(rm -rf *)" \
      --output-format json > "../wt/$id.result.json" ) || echo "$id 失败，见 result.json"
  break                                                  # 每轮只做 1 个
done
```
说明：
- 这些参数都在官方 CLI 文档里核实过【官方】；脚本整体是【我的推断，未实测】。
- 任务文件的状态迁移（doing→review/blocked）最好由脚本根据 `result.json` 加 `git -C ../wt/$id log` 来做，而不是让 agent 跨 worktree 去改主仓库的文件。上面为了简化写得比较粗，第一版建议先手动跑几次再调整。
- `--max-budget-usd` 只在 API 计费时有意义。如果你用 Claude 订阅，就靠 `--max-turns`、每轮只做 1 个任务、限制调用频率来控制额度。

### 5.5 护栏清单
| 风险 | 护栏 | 依据 |
|---|---|---|
| 两个会话认领同一个任务 | `mkdir .ai-locks/<id>` 原子锁，锁只放在主 checkout 里；脚本退出时释放；超过 2 小时的锁由复盘任务清理 | 【我的推断】；magpie 用 issue 评论里的“take”加 `lockf ~/suite.lock`【官方】 |
| 并行改代码互相覆盖 | 一个任务一个 worktree 和分支；“一个 checkout 只属于创建它的会话” | 【官方】magpie LESSONS（两个会话共用 checkout 出过事故）；subagent `isolation: worktree`、Desktop 计划任务的 Worktree 选项【官方】 |
| 假完成 | 验收标准写进任务文件；必须有“去掉修改就失败”的测试；跑完整测试套件；验证记录写 sha 和输出；没跑的写“未运行” | 【官方】magpie code-standards |
| 前端视觉问题 | Playwright 在 Chromium 和 WebKit 下各截一张图放进记录区；UI/UX 最终由人判断（yetone 也是每晚自己修 UI） | 【官方】yetone 原帖、code-standards 第 4 条 |
| 越权 | `settings.json` 的 `permissions.deny` 加上 `PreToolUse` hook，拦 push、merge、`.github/`、`package.json` 依赖改动、`.env` | 【官方】hooks 和 permissions 文档 |
| 人工闸门 | 人只 merge `review/` 里的任务；`risk: high` 先出方案；review 队列满 3 个就停下 | 【我的推断】；magpie 的对应做法是“An agent only proposes”加危害清单【官方】 |
| 额度失控 | 每轮 1 个任务；`--max-turns`、`--max-budget-usd`；便宜模型先做分诊（magpie 用 Jev 拦一刀）；`/loop` 间隔别太短 | 【官方】CLI 文档、yetone 回复 |
| 失败重试死循环 | `attempts` 和 `max_attempts: 2`，到上限就进 `blocked/`；Stop hook 检查 `stop_hook_active` | 【官方】hooks；其余【我的推断】 |
| 提示词注入 | 任务池只接受你自己写的 md；外部反馈（用户群、邮件）先由人或便宜模型整理成任务文件再放进 inbox | 【社区】linux.do 帖里的“池子缓冲”建议 |
| 熵增 | 每日复盘 loop，更新错题本，Seen≥3 就升级成标准 | 【官方】magpie LESSONS 机制 |

### 5.6 本地任务池 vs GitHub issue 驱动
| 维度 | `.ai/inbox` 本地 md | GitHub issue + `claude-code-action` |
|---|---|---|
| 前提 | 只要有 git 仓库，离线也行 | 要 GitHub、Actions、密钥 |
| 运行在哪 | 本机：能用真实浏览器、模拟器、本地账号（这是 magpie 的关键优势） | 云端 runner，每次全新 clone，拿不到本机环境 |
| 状态和认领 | 目录加 front-matter 加锁目录，要自己实现 | label、assignee、评论，天然有，可以用 `@claude` 触发 |
| 审计 | git 历史加任务文件记录区 | issue 和 PR 时间线，更适合团队协作 |
| 外部反馈接入 | 要人或脚本把反馈转成 md | 用户可以直接提 issue（也更容易被注入，要有门禁） |
| 成本控制 | 本机订阅或 API，靠脚本限流 | Actions 分钟数加 API 费用；`claude_args` 控制工具和轮数 |
| 适合 | 个人项目、私有项目、需要本机环境复现的项目（前端、桌面应用） | 开源项目、多人协作、要留公开记录的项目 |
| 混合方案 | 本地 loop 跑实现；GitHub 上只开 PR 让人审（`gh pr create` 由人执行或放进 ask 规则） | 【我的推断】推荐的进阶形态 |

### 5.7 建议的上手步骤（结合你装的工具）
1. 第 1 天：只建 `.ai/` 目录和模板，手写 3 个小任务。在 Claude Code 里手动说“按 .claude/loop.md 处理一个任务”，观察它的拆解和验证记录。
2. 第 2–3 天：用 `/loop 30m` 在白天盯着跑。人只审 `review/`，把发现的问题写进 LESSONS。
3. 第 1 周后：换成 Desktop 计划任务（勾选 Worktree）或 `scripts/ai-loop.sh`，再加上每日复盘任务。
4. 可选：分诊交给便宜模型。比如用 Pi 或 DeepSeek Harness 加 V4.1 Flash 把杂乱的反馈整理成任务文件，主模型只做实现。审查交给 Codex（`codex-plugin-cc`，见之前的多 agent 笔记）。这些是【我的推断】。
5. 始终保留：人工 merge、人工发版、UI 由人终审。等错题本稳定之后，再考虑放开 low-risk 任务自动合并。

---

## 6. 还不确定的点
- yetone 的 loop 具体间隔、权限模式（是否用 `--dangerously-skip-permissions` 或 auto）、是否用了 hooks：**都没公开**【未证实】。
- “browser use”具体用的是什么工具：他只回答了“claude code”，没说是哪个 MCP 或插件【未证实】。
- 合并社区 PR 的数量（383 个）来自 wquguru 的统计，我没有重新统计【社区】。
- 10-09 之后不接受外部 PR，所以第 1 条 loop 现在实际以 issue 和 Discord 为主，这一点是【我的推断】。
