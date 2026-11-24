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
| **`/ai-workflow init`** | **初始化任务池** | 在目标项目根目录执行一次，生成 `.ai-workflow/`（含配置、模板、图解、`list/buglist.md` 与 5 个任务目录），不碰已有业务文件。 |
| **`/ai-workflow task`** | **拆分与整理任务** | 将需求草稿放进 `list/`，输入 `/ai-workflow task 分析 list/需求.md 并拆分任务`，AI 仅出草稿，你确认后再写入 `inbox/`。 |
| **`/ai-workflow bugcheck`** | **Bug 清单拆分** | 自动读取 `list/buglist.md`，结合代码库拆分为低风险 bugfix 任务入 `inbox/`，并在 buglist 中标记已拆分项。 |
| **`/ai-workflow bugfix`** | **Bug 一键收割** | 自动读取未处理 bug，同模块智能归并，一键拆分并启动批量自动推进送审（适合下班前一键收割）。 |
| **`/ai-workflow 处理 T-xxx`** | **单任务执行** | 自动原子加锁并在 `.ai-worktrees/<id>/` 独立沙盒中工作；遇歧义停下等批准，跑通测试后送审。 |
| **`/ai-workflow 串行/并行推进`** | **任务包批量跑批** | 批量推进 `inbox/` 任务包：串行模式通过连环 `base_ref` 层层递进（夜间跑批神器）；并行模式多沙盒独立并发。 |
| **`/ai-workflow archive`** | **归档清理** | 任务合并后，输入 `/ai-workflow archive` 批量清理已完成的 worktree、删除对应分支并归档任务文件。 |

---

## 💡 最佳协作实践（黄金工作流）

通过底层「**原子任务锁（`.locks/`）**」与「**独立平级 worktree（`.ai-worktrees/<id>/`）**」，`ai-workflow` 天然支持多 Agent 并行与夜间自动跑批：

```text
       ┌──────────────┐
       │ 1. 白天规划   │  需求放 list/ 或记入 list/buglist.md -> 聊透方案并拆分任务入 inbox/
       └──────┬───────┘
              ▼
   ┌──────────────────────┐  日常开 2~3 个独立窗口，输入 /ai-workflow 处理 T-xxx；
   │ 2. 执行与夜间跑批    │  或下班前执行 /ai-workflow 串行推进 (连环 base_ref 递进，main 分支纯净)；
   └──────────┬───────────┘  遇到业务歧义在当前窗口直面人类讨论 (needs-discussion)
              ▼
       ┌──────────────┐
       │ 3. 验收与归档 │  第二天到公司集中审查 diff -> 人工 git merge -> /ai-workflow archive 一键归档
       └──────────────┘
```

### 1. 任务包批量推进与夜间跑批模型
- **串行连环 Worktree 模式（最常用）**：
  Task 1 基于基准分支开工送审后，Task 2 自动以 `base_ref: ai/T-1` 为基准拉出新分支开工，层层递进。主分支 `main` 始终不被污染。下班前一条命令跑批，第二天集中审查合并。
- **并行并发模式**：针对互相解耦、经分析无模块文件交叉的独立任务，由调度器分配独立沙盒并发执行。

### 2. Bug 与轻量调整三级敏捷策略（拒绝流程官僚主义）
- **L1 微小调整（直接改，不入池）**：文案、错别字、1~2 行样式微调，日常会话直接改完 commit，不走任务池。
- **L2 明确的小 Bug / 样式修复（极简直通车）**：白天随手记入 `.ai-workflow/list/buglist.md`，下班前执行 `/ai-workflow bugfix` 智能归并、自动拆分并批量修完送审。
- **L3 复杂 / 根因不明 Bug（严格正规军流转）**：涉及多模块联动、偶现或数据一致性的重大 Bug。先在会话中让 AI 只读探索定位根因，出具完整方案由你批准后，方可编码实施。

### 3. 文件交叉与冲突防御
- AI 绝不自动合入基准分支；发生冲突时后合入的任务直接在专属 worktree 中 `git rebase main` 并重跑测试后再次送审；强依赖任务用 `base_ref` 串联。

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

# 初始化/结构隔离回归测试（83 项检查）
bash scripts/test-ai-workflow.sh

# 目标项目结构验证
bash skills/ai-workflow/scripts/verify.sh <目标目录>
```
