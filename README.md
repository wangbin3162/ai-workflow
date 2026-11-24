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

在支持 Slash Command 的 Agent 会话中，通过单一入口 **`/ai-workflow`** 调度四大工作模式：

| 指令 | 模式 | 作用 |
| :--- | :--- | :--- |
| **`/ai-workflow init`** | **初始化任务池** | 在目标项目根目录执行一次，只生成 `.ai-workflow/`（含配置、模板、图解与 5 个任务目录），不碰业务代码与根 `.gitignore`。 |
| **`/ai-workflow task`** | **拆分与整理任务** | 将需求列表放进 `list/`，输入 `/ai-workflow task 分析 list/需求.md 并拆分任务`，AI 仅出草稿，你确认后再写入 `inbox/`。 |
| **`/ai-workflow <提示词>`** | **执行任务** | 输入 `/ai-workflow 处理 T-xxx`。AI 自动原子加锁并在 `.ai-worktrees/<id>/` 独立沙盒中工作；遇歧义停下等批准，完成后送审。 |
| **`/ai-workflow archive`** | **归档清理** | 任务合并后，输入 `/ai-workflow archive` 批量清理已完成的 worktree、删除对应分支并归档任务文件。 |

---

## 💡 最佳协作实践（黄金工作流）

通过底层「**原子任务锁（`.locks/`）**」与「**独立平级 worktree（`.ai-worktrees/<id>/`）**」，`ai-workflow` 天然支持多 Agent 并行：

```text
       ┌──────────────┐
       │ 1. 主会话规划 │  /ai-workflow task 拆分需求草稿 -> 确认写入 inbox/
       └──────┬───────┘
              ▼
   ┌──────────────────────┐  各开一个窗口，输入 /ai-workflow 处理 T-xxx
   │ 2. 多会话独立并行执行 │  无需手动切 worktree，物理目录隔离防冲突
   └──────────┬───────────┘  遇到业务歧义在当前窗口直面人类讨论 (needs-discussion)
              ▼
       ┌──────────────┐
       │ 3. 主工程验收 │  人工审查 diff -> 人工 git merge -> /ai-workflow archive 一键归档
       └──────────────┘
```

1. **无需手动切 worktree**：Agent 认领任务后会自动创建并切换到专属 worktree，主工程根目录永远保持干净安全。
2. **多独立窗口并行优于盲目子代理**：推荐在终端或 T3 中开 2~3 个独立会话窗口分别认领任务。上下文彻底隔离，遇到业务决策随时沟通。
3. **文件交叉与冲突防御**：
   - AI 绝不自动合入基准分支；
   - 多个任务若修改同文件，后合入的任务直接在 worktree 中让 Agent `git rebase main` 并重跑测试后再次送审；
   - 有明确强依赖的任务，在模板中填写 `base_ref: ai/T-前序任务` 串联开发。

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
