---
name: ai-workflow
description: 唯一的 AI 任务池工作流入口。用 /ai-workflow init 在目标项目安全初始化 .ai-workflow/（只写该目录，不碰 AGENTS.md / CLAUDE.md / docs / 根 .gitignore，可重复执行）；用 /ai-workflow task 按模板拆分或整理用户手写任务（不自动建任务、不实现）；用 /ai-workflow 加提示词领取一个用户手写任务，先只读探索，有重要歧义进入 needs-discussion 等用户补方案并明确批准，然后实施、验证、送入人工审查，绝不自动合并。用户说「初始化 AI 工作流 / 任务池 / ai-workflow / ai-loop / 让 AI 领任务」「新增任务 / 拆任务 / 写一条任务」「按任务池做一个任务」「用 worktree 让 agent 跑任务」，或提到旧技能 ai-loop-init / ai-loop-task 时，都使用本技能。
---

# ai-workflow — 单一技能入口

三个模式，按用户意图路由：

| 用户说的 | 模式 | 你会做什么 |
| --- | --- | --- |
| `/ai-workflow init`、「初始化 AI 工作流 / 任务池」 | **初始化** | 只写目标项目 `.ai-workflow/`，给出计划，冲突就停 |
| `/ai-workflow task`、「新增任务 / 拆分任务 / 把方案变成任务」 | **整理任务** | 按模板帮用户写任务草稿；不自动创建、不实现 |
| `/ai-workflow <提示词>`、「领取任务 / 按任务池做」 | **执行任务** | 领取用户手写任务 → 只读探索 → 讨论/批准 → 实施验证 → 送审 |

旧入口 `ai-loop-init` / `ai-loop-task` 不再提供；遇到旧说法时按本技能处理，并告诉用户入口已改名。
旧 `.ai/` 任务池、`scripts/ai-loop.sh` 不会被本技能调用，也不自动迁移。

---

## 模式一：初始化（`/ai-workflow init`）

目标 = 用户当前工程根目录（不是技能目录）。它必须是有至少一个提交的 git 仓库；不是就让用户先 `git init` 并提交，不要替他做。

### 1. 只读侦察

```bash
bash <skill-dir>/scripts/detect.sh <目标>
```

读输出：是否已初始化、是否已有 `.ai-workflow/`、旧版 `.ai/`、语言、基准分支与测试命令线索。
再读目标 `README.md` 和已有 `AGENTS.md`（若有），弄清项目是什么、怎么构建、怎么测。
线索不是事实：写进 `config.env` 前自己跑一次；不要在目标工程里跑会改文件的安装命令。

### 2. 出计划

```bash
bash <skill-dir>/scripts/install.sh --target <目标>          # 默认 --plan
```

- 输出 `CREATE` / `SKIP` → 没有冲突，可以直接执行。
- 输出 `CONFLICT` → **把冲突原样告诉用户并停止**；不覆盖、不合并、不删文件，等用户决定保留哪一版。
- `WARN` 里的旧版 `.ai/`、`scripts/ai-loop.sh` 只提示，不迁移；告诉用户迁移见源包 `docs/MIGRATION.md`。

初始化**只能**写目标项目的 `.ai-workflow/`。绝不移动、替换、追加或修改：
`AGENTS.md`、`CLAUDE.md`、`docs/` 下的任何文件、项目架构文档、其他规则文件、根 `.gitignore`。
需要项目自己忽略或配置的内容，只写进 `.ai-workflow/` 的说明或 `.ai-workflow/.gitignore`。

### 3. 执行

```bash
bash <skill-dir>/scripts/install.sh --target <目标> --apply
```

重复执行是幂等的：已有且相同的文件跳过，缺的补上，内容不同则冲突并停止且不写任何文件。
不得因为 `.ai-workflow/` 已存在就宣称初始化成功；以 `verify.sh` 结果为准。

### 4. 说明文档与 `config.env`

初始化会同时写入 `.ai-workflow/docs/`：

- `QUICKSTART.md`：第一次使用的完整走查；
- `REFERENCE.md`：状态、字段、批准格式、命令与配置速查；
- `TROUBLESHOOTING.md`：锁、worktree、review/done 失败的恢复；
- `MIGRATION.md`：旧 `.ai/`、`ai-loop` 迁移。

汇报时明确告诉用户先读 `.ai-workflow/docs/QUICKSTART.md`，入口索引在 `.ai-workflow/README.md`。

按侦察和实际跑通的命令填 `.ai-workflow/config.env`：

- `BASE_REF`：项目明确的开发基准分支/提交（如 `dev`）；**不要假设都是 main**。空 = 领取时主 checkout 当前 HEAD。
- `PROJECT_TOOLS`：agent 能跑的测试/构建命令，逐条写；没验证过的不填。
- `WORKTREE_SETUP`：依赖安装命令；没有依赖就保持注释并说明。

```bash
bash <skill-dir>/scripts/verify.sh <目标>
```

有 FAIL 就修到通过；WARN（如 `PROJECT_TOOLS` 为空）列进汇报。不要为了让验证通过而放宽门槛。

### 5. 汇报（3~5 行）

模式（新建 / 补充 / 冲突停止）、`BASE_REF` 选择、未填的配置、未验证项；
不要 `git add` / `commit` / `push`。

---

## 模式二：整理任务（`/ai-workflow task`）

用于把一个需求或一份方案整理成任务池里的任务文件。**任务由用户手写；没有自动建任务的工具。**

1. 确认 `.ai-workflow/templates/task.md` 和 `.ai-workflow/inbox/` 存在；缺就先让用户初始化。
2. 读模板，按模板章节起草；用户没说拆成几条就不要拆。
3. 任务字段必须真实：`id` 与文件名一致、`status: new`、`risk` 拿不准就写 `high`。
4. 验收标准只写已核实的命令或可观察步骤；没核实过的写 `TODO:`，不要编。
5. 复杂需求：先和用户把方案讨论清楚，把完整方案贴到任务末尾的「## 方案」。
6. 默认只把草稿给用户看。只有用户明确说「写入 / 创建这个文件」才写 `.ai-workflow/inbox/<id>.md`；
   不改其他任务，不认领，不建 worktree，不开始实现。
7. 不要覆盖已有任务文件。

回复：文件路径（或草稿）、`id`、`type`、`priority`、`risk` 及一句话理由、没核实的命令。

---

## 模式三：执行任务（`/ai-workflow <提示词>`）

前提：目标项目已初始化；任务由用户手写。所有状态命令都用 `.ai-workflow/scripts/ai-workflow.sh`。

### 1. 找任务并领取

```bash
.ai-workflow/scripts/ai-workflow.sh next
.ai-workflow/scripts/ai-workflow.sh claim <id> --by <你的标识>
```

- 同一任务只能有一个活跃写者（`mkdir` 任务锁）。
- `discussion/` 里的任务只有方案与用户批准都有效时才能 `resume`，不能直接领取。
- 领取会创建或复用 worktree（分支 `ai/<id>`）；如果会话已经在对应 worktree，先核验仓库/分支/任务，不要嵌套创建。
- 主 checkout 当前在 `ai/<id>` 分支时拒绝执行；已有不匹配目录时报告冲突，不删除。

### 2. 只读探索（此阶段不改业务代码）

读任务、项目原有规则、相关代码/接口/依赖/验收条件；判断是否存在影响实现的重要未决事项
（业务口径、接口行为、数据模型、权限、兼容性、任务范围等）。

### 3. 有重要歧义 → needs-discussion

不要用默认假设开工。在任务文件「## 讨论」写清：

- 已确认事实（附文件路径或命令证据）；
- 待决问题；
- 可选方案及影响；
- 建议方案（明确标为建议，不是用户决定）；
- 当前是否已有业务代码改动（有/无；已提交与未提交各多少）；
- 用户下一步应补充和批准什么。

```bash
.ai-workflow/scripts/ai-workflow.sh pause <id> --reason "为什么需要讨论"
```

`pause` 进入 `discussion/`、释放锁、保留 worktree/提交/diff，任务不会被自动再次领取。
用户可以把任务带到别的 Claude/T3 会话讨论，把完整方案写回「## 方案」。

### 4. 方案版本与用户批准（恢复的门槛）

```bash
.ai-workflow/scripts/ai-workflow.sh plan-seal <id> --version N
# 只有用户明确说「批准版本 N」之后：
.ai-workflow/scripts/ai-workflow.sh approve <id> --version N --by <用户> --note "用户批准原话"
# 只有用户明确要求恢复之后：
.ai-workflow/scripts/ai-workflow.sh resume <id>
```

- 只写方案不等于批准；你说「方案可行」也不等于用户批准。
- 批准必须对应当前 `plan_version` 和「## 方案」内容的 sha256；方案更新后旧批准失效。
- 不要自动扫描 discussion/ 并接手等待讨论的任务。
- 已经写代码后才发现歧义：同样 `pause`。不要 reset、不要删 worktree；如实记录已有改动和验证。

### 5. 实施与验证

只在 worktree 里改代码。验证记录写进「## 验证记录」：准确命令、执行目录、退出码、结果；
区分已验证、未验证、被阻塞。没有测试证据就不能说完成。验收标准不得自行放宽。

### 6. 送审（实现完成）

```bash
.ai-workflow/scripts/ai-workflow.sh review <id>
```

要求 worktree 无未提交改动；`risk: low` 有 commit，`risk: high` 无 commit（只出方案）；
「## 验证记录」非空。`review` 只进入 `review/`，不合并、不 push、不删 worktree。

### 7. 人工审查批准（不等于合并）

```bash
.ai-workflow/scripts/ai-workflow.sh approve-review <id> --commit <sha> --by <审查人> --note "审查结论"
```

审查对象必须是当前分支 HEAD；审查后代码再变化，旧批准失效。

### 8. 人工合并后归档

```bash
.ai-workflow/scripts/ai-workflow.sh done <id> --target <分支> --merged-commit <sha> --by <确认人> --note "已确认合并"
```

脚本校验合并提交在目标分支上、`--method merge` 时被批准 commit 是合并提交的祖先。
squash/rebase 用 `--method squash|rebase`，脚本会如实标注「无法用 sha 证明内容等价」。
没有人工确认或有效合并证据时，不归档；`review/` 不能直接 done。
不自动 merge、push、删除 worktree 或分支。

---

## 可选：`claude -p` 无人值守

```bash
DRY_RUN=1 .ai-workflow/scripts/ai-workflow.sh run
.ai-workflow/scripts/ai-workflow.sh run
```

它是可选运行方式，不等同于手动会话；两者共用任务锁。`run` 只领取 `status: new`，
不领取 discussion/ 任务。agent 报告 `AI_WORKFLOW_RESULT: discussion` 时进 discussion 并保留改动。
真实 `claude -p` 未验证前，不宣称可无人值守。

## 硬性禁止

- 不自动合并、不 push、不建 PR、不改 CI、不发版。
- 不删除 worktree/分支；不 reset 用户改动；不覆盖已有任务或文件。
- 不自动迁移旧 `.ai/` 任务，不改写旧状态。
- 不自行 `git add` / `commit` / `push` 真实仓库；需要版本化时提示用户。
- 不在初始化时碰 `.ai-workflow/` 之外的任何文件。
- 没有用户明确批准，不恢复 discussion 任务；没有合并证据，不 done。

## 文件

- `scripts/detect.sh` — 只读侦察
- `scripts/install.sh` — 计划 / 幂等初始化（只写 `.ai-workflow/`）
- `scripts/verify.sh` — 机械验证
- `assets/` — 装进目标 `.ai-workflow/` 的文件（README、WORKFLOW、config.env、任务模板、脚本）
- `assets/docs/` — 目标项目内的使用说明（QUICKSTART / REFERENCE / TROUBLESHOOTING / MIGRATION）
- `references/design.md` — 设计原因与边界
- `references/legacy-ai-loop-task.md` — 旧任务整理入口的归档内容（不再被发现为独立技能）
- `evals/evals.json` — 本技能的测试用例
