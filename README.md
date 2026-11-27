# ai-workflow

> 用**用户手写任务 + 独立 worktree + 人工审查合并**驱动 AI 编码会话的 Agent 技能包。

AI 只读探索 → 有歧义先讨论 → 用户批准方案 → 实施验证 → 人工审查 → 人工合并 → 归档。  
**AI 绝不自动合并、不 push、不删除 worktree。**

对外唯一技能入口：**`/ai-workflow`**

---

## 📦 技能安装

本项目已完全适配 open agent skills 生态标准（[skills.sh](https://skills.sh)）。只要有 Node.js 环境，无需手动克隆代码，使用 `npx` 即可一键安装：

### 1. 全局安装（推荐，所有项目可用）

```bash
npx skills add wangbin3162/ai-workflow -g
```

### 2. 当前项目安装

```bash
npx skills add wangbin3162/ai-workflow
```

### 3. 为指定 Agent 安装

支持 Claude Code、Cursor、Antigravity 等主流 Coding Agent：

```bash
# 只安装给 Claude Code
npx skills add wangbin3162/ai-workflow -a claude-code -g

# 一键安装给系统中检测到的所有 Agent
npx skills add wangbin3162/ai-workflow -a '*' -g
```

### 4. 手动安装（离线 / 本地开发）

克隆本仓库后，将 `skills/ai-workflow/` 目录软链或复制到你的 Agent 技能目录中：
- Claude Code 全局目录：`~/.claude/skills/ai-workflow/`
- 项目级目录：`.claude/skills/ai-workflow/` 或 `.agents/skills/ai-workflow/`

---

## 🚀 技能怎么使用

在支持 Slash Command 的 Agent 会话中，通过单一入口 **`/ai-workflow`** 调度各项核心工作模式：

| 指令 | 模式 | 作用 |
| :--- | :--- | :--- |
| **`/ai-workflow init`** | **初始化任务池** | 在目标项目根目录执行一次，生成 `.ai-workflow/`（含配置、模板、图解、`HISTORY.md`、`inbox/GUIDE.md`、`list/buglist.md` 与 5 个任务目录），不碰已有业务文件。 |
| **`/ai-workflow task`** | **拆分与整理任务** | 将需求草稿放进 `list/`，输入 `/ai-workflow task 分析 list/需求.md 并拆分任务`，AI 先判并行条件，仅出草稿；你确认后写入 `inbox/`、重建 `inbox/GUIDE.md`，并将原文件归档至 `list/archive/`。 |
| **`/ai-workflow bugcheck`** | **Bug 清单拆分** | 自动读取 `list/buglist.md`，结合代码库拆分为低风险 bugfix 任务入 `inbox/`，并在 buglist 中标记已拆分项。 |
| **`/ai-workflow bugfix`** | **Bug 一键收割** | 自动读取未处理 bug，同模块智能归并，一键拆分并启动批量自动推进送审（适合下班前一键收割）。 |
| **`/ai-workflow 处理 T-xxx`** | **单任务执行** | 自动原子加锁并在 `.ai-worktrees/<id>/` 独立沙盒中工作；遇歧义停下等批准，跑通测试后送审。 |
| **`/ai-workflow 串行/并行推进`** | **任务包批量跑批** | `run-all` 默认串行：主代理只做调度，一任务一子代理，通过连环 `base_ref` 层层递进。并行任务默认同组并发派子代理。 |
| **`/ai-workflow archive`** | **归档清理** | 任务合并后，输入 `/ai-workflow archive` 按日目录（`archive/YYYYMMDD/`）批量清理 worktree、删除对应分支并同步更新 `HISTORY.md`。 |

---

## 💡 最佳协作实践（黄金工作流）

通过底层「**原子任务锁（`.locks/`）**」与「**独立平级 worktree（`.ai-worktrees/<id>/`）**」，`ai-workflow` 天然支持多 Agent 并行与夜间自动跑批：

```text
       ┌──────────────┐
       │ 1. 白天规划   │  需求放 list/ 或记入 list/buglist.md -> 聊透方案并拆分任务入 inbox/
       └──────┬───────┘
              ▼
   ┌──────────────────────┐  日常开 2~3 个独立窗口，输入 /ai-workflow 处理 T-xxx；
   │ 2. 执行与夜间跑批    │  或下班前执行 /ai-workflow run-all (主代理调度，一任务一子代理)；
   └──────────┬───────────┘  遇到业务歧义转 needs-discussion，主代理不替人批准
              ▼
       ┌──────────────┐
       │ 3. 验收与归档 │  第二天到公司集中审查 diff -> 人工 git merge -> /ai-workflow archive 一键归档
       └──────────────┘
```

### 1. 任务池指南与子代理跑批
- **任务池顺序**：拆分任务时先分析并行条件，把“并行组 + 串行链”写入 `.ai-workflow/inbox/GUIDE.md`。
  指南只记录未完成任务，任务完成归档后移除；全部完成后只清空，不删除、不累加历史。
- **串行跑批（默认）**：`run-all` / “推进全部任务”按 GUIDE 顺序执行。主代理只调度，一个任务一个子代理；前一个送审后再接力，默认继承主代理模型。
- **并行跑批**：`并行 T-xxx ...` / `run-all --parallel` 默认直接派子代理；只允许同组、无依赖、无文件交叉任务，否则自动降级串行。

### 2. Bug 与轻量调整三级敏捷策略（拒绝流程官僚主义）
- **L1 微小调整（直接改，不入池）**：文案、错别字、1~2 行样式微调，日常会话直接改完 commit，不走任务池。
- **L2 明确的小 Bug / 样式修复（极简直通车）**：白天随手记入 `.ai-workflow/list/buglist.md`，下班前执行 `/ai-workflow bugfix` 智能归并、自动拆分并批量修完送审。
- **L3 复杂 / 根因不明 Bug（严格正规军流转）**：涉及多模块联动、偶现或数据一致性的重大 Bug。先在会话中让 AI 只读探索定位根因，出具完整方案由你批准后，方可编码实施。

### 3. 文件交叉与冲突防御
- AI 绝不自动合入基准分支；发生冲突时后合入的任务直接在专属 worktree 中 `git rebase main` 并重跑测试后再次送审；强依赖任务用 `base_ref` 串联。

### 4. HISTORY.md 全局索引与防撞号机制
- 所有任务状态流转统一在 `.ai-workflow/HISTORY.md` 中按日期倒序沉淀；
- 新建或拆分任务前，AI 必须读取当天最大编号自增（如已有 002 则新任务必为 003），彻底避免 ID 和 Git 分支重名冲突；
- 归档清理时，任务文件自动按日移入 `archive/YYYYMMDD/` 目录，并同步回写合并记录至 `HISTORY.md`。

---

## 📚 详细文档导航

- 📖 [docs/workflow-guide.md](docs/workflow-guide.md) —— **任务流转与执行完整指南**（初始化至 `.ai-workflow/README.md` 的详细规格说明）
- ⚡️ [docs/quickstart.md](docs/quickstart.md) —— **极简上手指引**（新手 5 分钟上手）
- 🏛️ [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— **系统架构与设计说明**
- 📏 [docs/code-standards.md](docs/code-standards.md) —— **代码规范与验收标准**
- 🔄 [docs/MIGRATION.md](docs/MIGRATION.md) —— **从旧版 .ai/v1/v2 结构迁移指引**

---

## 🛠 本地开发与测试

```bash
# 脚本语法检查
bash -n skills/ai-workflow/scripts/*.sh

# 初始化/结构隔离回归测试（106 项检查）
bash scripts/test-ai-workflow.sh

# 目标项目结构验证
bash skills/ai-workflow/scripts/verify.sh <目标目录>
```
