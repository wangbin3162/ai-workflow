---
name: ai-workflow
description: 唯一的 AI 任务池工作流入口。用 /ai-workflow init 在目标项目安全初始化 .ai-workflow/（生成 README、TEMPLATE、CONFIG、guide.html 和 inbox/doing/review/done/list 五个目录，项目配置独立放 CONFIG.md，guide.html 只是流转图解，不生成脚本、不碰 AGENTS.md / CLAUDE.md / docs / .gitignore，可重复执行）；用 /ai-workflow task 按 TEMPLATE 整理用户手写任务，或分析 list/ 里的任务列表拆分任务（默认只出草稿，不自动建任务、不实现）；用 /ai-workflow 加提示词领取任务，由 AI 直接操作任务文件和 git，先只读探索，有歧义进入 needs-discussion 等用户补方案并明确批准，然后实施、验证、送人工审查，绝不自动合并；用 /ai-workflow archive 批量归档已完成任务并清理 worktree/分支。用户说「初始化 AI 工作流 / 任务池 / ai-workflow / ai-loop / 让 AI 领任务」「新增任务 / 拆任务」「按任务池做一个任务」「用 worktree 让 agent 跑任务」「归档清理」，或提到旧技能 ai-loop-init / ai-loop-task 时，都使用本技能。
---

# ai-workflow — 单一技能入口

四个模式：

| 用户说的 | 模式 | 做什么 |
| --- | --- | --- |
| `/ai-workflow init`、「初始化 AI 工作流 / 任务池」 | **初始化** | 只写目标项目 `.ai-workflow/README.md` + `TEMPLATE.md` + `CONFIG.md` + `guide.html` + 五个任务目录 |
| `/ai-workflow task`、「新增任务 / 拆分任务」 | **整理任务** | 按 README 模板帮用户写任务草稿；不自动创建、不实现 |
| `/ai-workflow <提示词>`、「领取任务 / 按任务池做」 | **执行任务** | 领取 → 只读探索 → 讨论/批准 → 实施验证 → 送审 |
| `/ai-workflow archive`、「归档清理 / 清理已完成任务」 | **归档清理** | 整理 `done/` 里的已完成任务和对应 worktree/分支 |

旧入口 `ai-loop-init` / `ai-loop-task` 不再提供；旧 `.ai/` 与旧脚本不会被调用，也不自动迁移。

**初始化后的任务流转由 AI 直接操作文件和 git，没有随初始化分发的脚本。**
目标项目内的工作流说明是 `.ai-workflow/README.md`，项目配置在 `.ai-workflow/CONFIG.md`，
流转图解是 `.ai-workflow/guide.html`。执行时以 README 和 CONFIG 为准。

---

## 模式一：初始化（`/ai-workflow init`）

目标 = 当前工程根目录，必须是有至少一个提交的 git 仓库；不是就让用户先 `git init` 并提交。

### 1. 只读侦察

```bash
bash <skill-dir>/scripts/detect.sh <目标>
```

读：是否已初始化、旧版结构、语言、基准分支与测试命令线索。
再读目标 `AGENTS.md`、`README.md`、`docs/`、CI 配置（若有）。线索不是事实：
写进 `CONFIG.md` 前自己跑一次；不要跑会改文件的安装命令。

### 2. 出计划

```bash
bash <skill-dir>/scripts/install.sh --target <目标>          # 默认 --plan
```

初始化只生成：

```text
.ai-workflow/
├── README.md
├── TEMPLATE.md
├── CONFIG.md
├── guide.html
├── inbox/
├── doing/
├── review/
├── done/
└── list/
```

- 不生成 `.gitignore`、`config.env`、`scripts/`、`docs/`、`templates/`、`.initialized`。
- `CONFIG.md` 独立放项目配置；`init` 预填当前分支，测试命令留 TODO 等初始化会话核实。
- `list/` 用于临时任务列表/方案草稿，供 `/ai-workflow task` 分析拆分。
- 已存在且带 `ai-workflow:v3` 标记的 README、已存在的 TEMPLATE / CONFIG / guide.html 视为用户文件：保留，不覆盖。缺失的 guide.html 会补上。
- 未标记的 README、旧版 `.initialized` / v1 / v2 结构：停止并提示人工处理，不自动升级。
- 只提示旧 `.ai/`、`scripts/ai-loop.sh`，不读取、不修改。

初始化**只能**写 `.ai-workflow/`。绝不移动、替换、追加或修改：
`AGENTS.md`、`CLAUDE.md`、`docs/`、项目架构文档、其他规则文件、根 `.gitignore`。

### 3. 执行

```bash
bash <skill-dir>/scripts/install.sh --target <目标> --apply
```

### 4. 补 CONFIG.md 的项目配置

`init` 已把当前分支预填进 `.ai-workflow/CONFIG.md`。初始化会话要把它补成可执行配置：

- 读目标 `AGENTS.md` / `README.md` / `docs/` / CI 配置，找出项目声明的测试、构建、依赖安装方式；
- 实际跑一次不改源码的检查命令（如已有测试 / 语法检查）；需要装依赖或会改工作区时先征得用户同意；
- 基准分支：当前分支通常可用；如果当前是 feature 分支，改成 `dev` / `main` 等开发基准；
- worktree 依赖安装：有依赖写安装命令，没有写「无」；
- 无法核实的内容保留 `TODO:`，并在汇报里列出来。

### 5. 机械验证

```bash
bash <skill-dir>/scripts/verify.sh <目标>
```

有 FAIL 修到通过；WARN（如 CONFIG.md 仍有 TODO、旧结构残留）列进汇报。

### 6. 汇报（3~5 行）

模式（新建 / 已存在保留 / 旧结构停止）、生成的结构、CONFIG.md 里未填的 TODO、未验证项。
不要 `git add` / `commit` / `push`。

---

## 模式二：整理任务（`/ai-workflow task`）

任务由用户手写；没有自动建任务的工具。

1. 读 `.ai-workflow/TEMPLATE.md` 和 README 的「任务模板与任务列表」「目录与状态」。
2. 按模板起草；用户没说拆成几条就不要拆。
3. `id` 与文件名一致，`status: new`；`risk` 拿不准写 `high`。
4. 验收标准只写已核实的命令或可观察步骤；没核实过的写 `TODO:`。
5. 复杂需求先讨论，把完整方案写进「## 方案」。

**分析 `list/` 拆分任务**：

- 读 `.ai-workflow/list/<名字>.md`，按 TEMPLATE 拆成一组任务草稿；
- 给出标题、范围、验收标准、risk、依赖顺序；
- 默认只展示拆分结果，不写 inbox；
- 用户明确确认后，才逐条写入 `.ai-workflow/inbox/<id>.md`，仍不认领、不实现；
- 不覆盖已有任务文件；`list/` 原文件由用户决定保留或删除。

---

## 模式三：执行任务（`/ai-workflow <提示词>`）

前提：目标项目已初始化，任务由用户手写。**先读 `.ai-workflow/README.md`**，
按其中的「AI 执行流程」操作；以下是必须遵守的要点。

### 1. 领取

- 只选 `inbox/` 中 `status: new` 的任务；`needs-discussion` / `blocked` 不得领取。
- `mkdir .ai-workflow/.locks/<id>` 做任务锁；已存在就停，确认无人使用后由人删除。
- 任务移到 `doing/`，改 `status: claimed`，写 `claimed_by`、`claimed_at`。
- 准备 worktree（位置 `.ai-worktrees/<id>/`）：基准 = 任务 `base_ref` → `CONFIG.md` 的基准分支 → 主 checkout 当前 HEAD。
- 已有同分支 worktree 就复用；目录存在但不是该分支 worktree 就停止报告；不嵌套创建。
- 记录 `worktree`、`base_commit`。

### 2. 只读探索（此阶段不改业务代码）

读任务、项目原有规则、相关代码/接口/依赖/验收条件；判断是否存在影响实现的重要未决事项
（业务口径、接口行为、数据模型、权限、兼容性、任务范围等）。

### 3. 有重要歧义 → needs-discussion

不要用默认假设开工。在「## 讨论」写：已确认事实（附证据）、待决问题、可选方案与影响、
建议方案（标为建议）、当前代码改动状态、用户下一步。

然后：`status: needs-discussion`，任务移回 `inbox/`，删除任务锁；
**保留** worktree、提交和 diff，不 reset、不删除。

### 4. 方案版本与用户批准

用户补全「## 方案」后，用 README 里的命令计算方案正文 sha256，写 `plan_version` / `plan_sha256`。

只有用户明确说「批准版本 N」之后，才写：

- `approved_version`、`approved_plan_sha256`（必须与当前 sha256 一致）
- `approved_by`、`approved_at`、`approved_note`（用户原话）

只写方案不算批准；AI 自评「可行」也不算。方案内容或版本变化后旧批准失效。

### 5. 恢复实施

用户明确要求恢复后，重新计算当前方案 sha256，确认版本与批准 sha 都一致；
否则停下。满足后重新加锁，任务移到 `doing/`，`status: claimed`，复用原 worktree。

### 6. 实施与验证

只在 worktree 里改代码。验证记录写进「## 验证记录」：准确命令、执行目录、退出码、结果；
区分已验证、未验证、被阻塞。没跑写「未运行」及原因。验收标准不得自行放宽。

### 7. 送审

要求：worktree 无未提交改动；`risk: low` 至少 1 个 commit，`risk: high` 无 commit；
验证记录非空。然后记录 `review_commit`（无代码任务写 `none`），`status: needs_review`，
移到 `review/`，删除任务锁。**不合并、不 push、不删 worktree。**

### 8. 人工审查批准（不等于合并）

人工确认后记录 `review_approved_commit`（必须等于分支当前 HEAD）、批准人和结论，
`status: review_approved`，任务留在 `review/`。审查后代码变化，旧批准失效。

### 9. 人工合并后归档

人工合并后记录：

- `merge_target`、`merged_commit`（必须能在目标分支上找到）
- `merge_method`：`merge` / `squash` / `rebase`
- `merged_by` / `merged_at` / `merged_note`（人工确认原话）

`merge` 要求被批准 commit 是合并提交的祖先；`squash` / `rebase` 只能确认合并提交在目标分支上，
**无法用 sha 证明内容等价**，必须写明。
批准后分支变化、缺少人工确认或合并证据时，不归档。
无代码任务确认后可直接 `status: done` 并移入 `done/`。

### 10. 阻塞与恢复

无法继续或人工拒绝：`status: blocked`，任务移到 `inbox/`，记录原因，删除锁，保留 worktree 和 diff。
重新入池由用户补充信息后改 `status: new`。

---

## 模式四：归档清理（`/ai-workflow archive`）

整理已完成的任务：移动任务文件到归档目录，清理对应 worktree 和分支。

### 前提

- 目标项目已初始化。
- 只处理 `done/` 目录中 `status: done` 且有完整合并证据（`merged_commit` 非空）的任务。

### 流程

1. 扫描 `done/` 目录，列出所有满足归档条件的任务：
   - `status: done`
   - `merged_commit` 非空
   - `merge_target` 非空

2. 展示归档清单（任务 id、标题、合并时间、目标分支），**默认只展示，不执行**。

3. 用户确认后，对每个任务执行：
   a. 移动任务文件到 `.ai-workflow/archive/`（自动创建）；
   b. 如果对应 worktree 存在（`.ai-worktrees/<id>/`），执行 `git worktree remove`；
   c. 如果对应分支存在（`ai/<id>`），且已被合并到 `merge_target`，执行 `git branch -d`；
   d. 如果锁残留（`.ai-workflow/.locks/<id>/`），删除。

4. 汇报：归档了几个任务，清理了几个 worktree/分支，跳过了哪些（条件不满足或分支未合并）。

### 安全规则

- **不删除未合并的分支**：分支未合并到目标分支时跳过并报告，不用 `-D` 强删。
- **不处理非 done 状态的任务**：即使用户要求也不清理进行中的任务。
- **归档目录是 `.ai-workflow/archive/`**：不移到项目其他位置。
- **不 push、不改远程**。

---

## 硬性禁止

- 不自动合并、不 push、不建 PR、不改 CI、不发版。
- 不删除 worktree/分支；不 reset 用户改动；不覆盖已有任务或文件。
- 不自动迁移旧 `.ai/` 任务，不改写旧状态。
- 不在初始化时碰 `.ai-workflow/` 之外的任何文件。
- 没有用户明确批准，不恢复 discussion 任务；没有合并证据，不 done。
- 不把任务状态偷偷提交到业务分支。

## 文件

- `scripts/detect.sh` — 只读侦察
- `scripts/install.sh` — 计划 / 幂等初始化（README、TEMPLATE、CONFIG、guide.html + 五目录）
- `scripts/verify.sh` — 结构验证
- `assets/README.md` — 目标 `.ai-workflow/` 的说明与执行规则
- `assets/TEMPLATE.md` — 目标 `.ai-workflow/` 的任务模板
- `assets/CONFIG.md` — 目标 `.ai-workflow/` 的项目配置模板（init 预填当前分支）
- `assets/guide.html` — 目标 `.ai-workflow/` 的流转图解（执行规则仍以 README 为准）
- `references/design.md` — 设计原因与边界
- `references/legacy-ai-loop-task.md` — 旧任务整理入口归档（不是技能入口）
- `evals/evals.json` — 测试用例
