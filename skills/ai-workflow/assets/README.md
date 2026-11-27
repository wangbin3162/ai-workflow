<!-- ai-workflow:v3 — 本文件由 /ai-workflow init 生成；用户可编辑，重复 init 会保留本文件 -->
# ai-workflow

用**用户手写**的任务驱动 AI 编码会话：AI 只读探索 → 有歧义先讨论 → 用户批准方案 → 实施验证 →
人工审查 → 人工合并 → 归档。**AI 不合并、不 push、不删除 worktree。**

任务状态靠任务文件的 front-matter 和所在目录表达。状态操作由 AI 按本文直接执行，
没有随初始化分发的脚本。流转图解见 [guide.html](guide.html)，怎么执行以本文为准。

## 1. 目录与状态

```text
.ai-workflow/
├── README.md      # 本文件
├── TEMPLATE.md    # 任务模板
├── CONFIG.md      # 项目配置：基准分支 / 测试命令 / 依赖安装
├── guide.html     # 流转图解；执行规则以本文件为准
├── HISTORY.md     # 任务全局历史与索引（防 ID 碰撞，按日期倒序）
├── inbox/         # new / needs-discussion / blocked；GUIDE.md 是任务池顺序指南
├── doing/         # claimed
├── review/        # needs_review / review_approved
├── done/          # done
└── list/          # 临时任务列表 / buglist.md / 方案草稿，供 AI 拆分任务
```

| status | 所在目录 | 含义 | 可领取 |
| --- | --- | --- | --- |
| `new` | `inbox/` | 新任务 | 是 |
| `needs-discussion` | `inbox/` | 有重要歧义，等用户补方案并批准 | 否 |
| `blocked` | `inbox/` | 失败、被拒绝或中断，需人工处理 | 否 |
| `claimed` | `doing/` | 已认领，有活跃写者 | 否 |
| `needs_review` | `review/` | 实现完成 + 验证记录已写，等人审 | 否 |
| `review_approved` | `review/` | 人工审查通过，**尚未合并** | 否 |
| `done` | `done/` | 人工确认合并并归档 | 否 |

- 只有 `inbox/` 里 `status: new` 的任务可以被领取。
- `needs-discussion` / `blocked` 虽然也在 `inbox/`，但**不得**按新任务领取。
- 实现完成、验证通过、审核通过、人工确认已合并、done/归档是五件事。
- `.ai-workflow/` 是否纳入版本控制由项目自己决定；本工作流不修改项目 `.gitignore`。

## 2. 项目配置

见 [CONFIG.md](CONFIG.md)。`init` 会预填当前分支；初始化会话应读取目标项目已有的
`AGENTS.md` / `README` / `docs` / CI，实际验证命令后再填，不要编造。

## 3. 任务模板与任务列表

### 3.1 手写任务

复制 [TEMPLATE.md](TEMPLATE.md) 到 `inbox/`，文件名用任务的 `id`，例如：

```bash
cp .ai-workflow/TEMPLATE.md .ai-workflow/inbox/T-20260101-001.md
```

至少填 `id`（与文件名一致）、`title`、`status: new`、`risk`、背景和验收标准。
复杂需求先讨论方案，把完整方案写进「## 方案」。

规则：

- `id` 必须与文件名一致，分支固定为 `ai/<id>`。
- **防重名与序号自增**：新建任务前必须查阅 `HISTORY.md` 当天最大编号，确保 ID 递增（如已有 002 则新任务为 003），绝不与已归档或已执行任务重名；并在 `HISTORY.md` 当日段落下记录。
- 模板分两部分：前半部分由用户填写（`id`、`title`、`type`、`status`、`risk`、`priority`、`created`、`base_ref`、`execution`、`agent_model`），后半部分由 AI 自动维护，无需手动编辑。
- `risk`：`low` / `high`；缺失或写错按 `high`。`high` 只出方案，不改代码。
- `execution`：默认 `serial`；只有通过并行检查才写 `parallel`。并行任务由 AI 填 `parallel_group`，如同一 `P1`。
- `agent_model`：默认空，表示子代理继承主代理模型；用户明确指定某个任务用其他模型时才填写。
- front-matter 只写 `key: value`，不要写行内注释，值里不要出现 ` #`。

### 3.2 从 list/ 拆分任务

`list/` 用来临时放任务清单、需求列表、方案草稿（markdown 即可）。典型流程：

1. 用户把列表写到 `.ai-workflow/list/<名字>.md`；
2. 在会话里说「/ai-workflow task，分析 list/<名字>.md 并拆分任务」；
3. AI 只读分析列表，**先判定并行条件**，再按 `TEMPLATE.md` 给出拆分方案：每条任务的标题、范围、
   验收标准、risk、`execution`、依赖顺序；
4. AI 默认只展示拆分结果，**不自动写 inbox**；
5. 用户确认后，AI 才逐条写入 `.ai-workflow/inbox/<id>.md`，同时重建
   `.ai-workflow/inbox/GUIDE.md` 任务池顺序，仍不领取、不实现；
6. **原清单自动归档**：确认写入 `inbox/` 后，原需求文件自动移入 `.ai-workflow/list/archive/<原文件名>`，保持 `list/` 根目录只保留待拆分的活跃文件。

`list/` 只是输入区，没有状态含义；拆分完成后原清单已归档。

并行判定必须保守，只有同时满足以下条件才标 `execution: parallel`：

- 任务之间没有前后依赖；
- 不修改同一个代码文件，也不共享可变模块、接口、数据库迁移、配置或测试夹具；
- 各任务能在独立 worktree 中验证，失败不会影响另一任务的判断；
- 任何不确定、需要改同一文件、或可能产生逻辑冲突的情况，一律串行。

### 3.3 任务池执行指南（inbox/GUIDE.md）

`.ai-workflow/inbox/GUIDE.md` 是常驻的当前执行顺序，不是任务文件，不参与领取和状态统计。

格式：

```markdown
# 任务池执行指南

执行摘要：T-20260101-001～T-20260101-003 可并行；T-20260101-004 → T-20260101-005 串行。

## 当前顺序

1. [并行 P1] T-20260101-001
2. [并行 P1] T-20260101-002
3. [并行 P1] T-20260101-003
4. [串行] T-20260101-004
5. [串行] T-20260101-005
```

维护规则：

- 拆分任务并确认写入 `inbox/` 时，扫描 `inbox/`、`doing/`、`review/` 中所有未完成任务，与本次新任务合并后**整体重建**指南。
- 保留已有未完成任务的相对顺序；同一任务 ID 只出现一次，不重复、不追加历史批次。
- 任务进入 `done/` 或归档后，从指南中移除。
- 全部任务完成后，只把摘要和当前顺序清空为「暂无未完成任务」，文件永久保留；不删除文件、不保留历史。
- 指南只表达顺序。实际可领取范围仍由任务状态决定，只有 `inbox/` 里的 `status: new` 可执行。

### 3.4 Bug 清单与快速收割（bugcheck 与 bugfix）

初始化时会在 `.ai-workflow/list/buglist.md` 自动生成开箱即用的 Bug 跟踪池，格式支持手工随手记，也支持外接脚本从禅道、Jira、飞书等自动化同步写入。

- **`/ai-workflow bugcheck [要求]`（仅拆分与标记）**：
  1. 读取 `list/buglist.md` 中所有未打勾 `[ ]` 的待处理条目；
  2. 结合代码库检索相关文件与上下文，按 `TEMPLATE.md` 拆分为 `type: bugfix`、`risk: low` 的任务写入 `inbox/`；
  3. 自动将 `buglist.md` 中对应的条目移至「已拆分处理」区块，并标记对应的任务 ID（如 `- [x] ... -> T-xxx`）；
  4. 仅拆分，不直接改业务代码。
- **`/ai-workflow bugfix`（一键合并、拆分并批量自动推进）**：
  1. 检索 `list/buglist.md` 中的未处理条目；
  2. **智能归并**：分析若有多条 Bug 涉及同一模块或相同文件，自动归并为单一任务，杜绝后续文件交叉冲突；不同模块拆为独立任务；
  3. 自动生成任务写入 `inbox/`，按并行条件重建 `inbox/GUIDE.md`，并同步更新 `buglist.md`；
  4. 立即启动自动批量执行：默认串行流水线、一任务一子代理，在专属 worktree 中修复、运行测试验证，并一并送入 `review/`。

## 4. AI 执行流程

### 4.1 领取

1. 只领取 `inbox/` 中 `status: new` 的任务。
2. 用任务锁保证同一任务只有一个活跃写者：

```bash
mkdir .ai-workflow/.locks/<id>
```

已存在就停止；确认无人使用后由人删除。

3. 移动到 `doing/`，改 `status: claimed`，写 `claimed_by`、`claimed_at`。
4. 准备 worktree（见第 5 节），记录 `worktree`、`base_commit`。
5. 先**只读探索**，不改业务代码。

### 4.2 有重要歧义

不要用默认假设开工。先在「## 讨论」写清事实、问题、可选方案、建议、当前代码改动、用户下一步，然后：

- `status: needs-discussion`；
- 任务移回 `inbox/`；
- 删除任务锁；
- **保留** worktree、提交和 diff，不 reset、不删除。

### 4.3 方案版本与批准

用户补全「## 方案」后，计算方案正文指纹：

```bash
awk '/^## 方案/{f=1;next} /^## /{f=0} f' .ai-workflow/inbox/<id>.md \
  | shasum -a 256 | awk '{print $1}'
```

写入 `plan_version`（正整数）和 `plan_sha256`。

只有用户明确说「批准版本 N」后，才写入批准记录：

```yaml
approved_version: N
approved_plan_sha256: <与 plan_sha256 相同>
approved_by: <批准人>
approved_at: <时间>
approved_note: <用户批准原话>
```

并在「## 审查与合并记录」追加一行批准记录。
只写方案不算批准；AI 自评「可行」也不算。方案内容或版本变化后旧批准失效。

### 4.4 恢复实施

用户明确要求恢复后：

1. 重新计算「## 方案」的 sha256；
2. 必须满足：`approved_version == plan_version`、`approved_plan_sha256 == 当前 sha256`、
   批准人和原话非空；
3. 任一不满足就停下，不恢复；
4. 满足后重新 `mkdir .ai-workflow/.locks/<id>`，任务移到 `doing/`，`status: claimed`，复用原 worktree。

### 4.5 实施与验证

只在 worktree（分支 `ai/<id>`）里改代码。验证记录写进「## 验证记录」：

- 准确命令、执行目录、退出码、结果；
- 已验证 / 未验证 / 被阻塞分别写清；
- 没跑就写「未运行」及原因。

### 4.6 送审

要求：

- worktree 没有未提交改动；
- `risk: low` 至少有 1 个新 commit；`risk: high` 不允许有 commit；
- 「## 验证记录」非空。

然后：记录 `review_commit`（无代码任务写 `none`），`status: needs_review`，任务移到 `review/`，
删除任务锁。**不合并、不 push、不删 worktree。**

### 4.7 人工审查批准（不等于合并）

人工查看 diff 与验证记录后，由 AI 记录：

- `review_approved_commit`：审查对象 commit，必须等于分支当前 HEAD；
- `review_approved_by` / `_at` / `_note`；
- `status: review_approved`，任务留在 `review/`。

审查后代码再变化，旧批准失效。

### 4.8 人工合并与归档

合并必须由人执行。合并后由 AI 校验并记录：

- `merge_target`：目标分支；
- `merged_commit`：合并提交，必须能在目标分支上找到；
- `merge_method`：`merge` / `squash` / `rebase`；
- `merged_by` / `merged_at` / `merged_note`：人工确认人、时间、原话。

`merge` 方式要求被批准 commit 是合并提交的祖先。
`squash` / `rebase` 只能确认合并提交在目标分支上，**无法用 sha 证明内容等价**，必须写明这一限制。
批准后分支 HEAD 有变化、缺少人工确认或合并证据时，不归档。
无代码任务（`risk: high` 只出方案）确认后可直接 `status: done` 并移入 `done/`。

归档后 **不删除** worktree 或分支，由人决定何时清理。
可使用 `/ai-workflow archive` 批量整理 `done/` 里的任务。

### 4.9 阻塞与拒绝

- 无法继续：`status: blocked`，任务移到 `inbox/`，删除锁，保留 worktree 和 diff。
- 人工拒绝审查：`status: blocked`，记录原因，任务移到 `inbox/`。
- 重新入池：用户补充信息后改 `status: new`，可重新领取。

## 5. worktree

- 位置：`.ai-worktrees/<id>/`（与 `.ai-workflow/` 平级）；分支 `ai/<id>`。
- 基准优先级：任务 `base_ref` → CONFIG.md 的基准分支 → 领取时主 checkout 当前 HEAD。
- 先看是否已有同分支 worktree（`git worktree list --porcelain`）；有就复用，不嵌套创建。
- 目录存在但不是该分支 worktree → 停止并报告，不删除、不覆盖。
- 主 checkout 当前在 `ai/<id>` 分支 → 拒绝领取。
- 已处于任务 worktree 时，先核验仓库与分支，再复用当前目录。
- **环境文件拷贝**：由于 `.env`、`.env.local` 等配置文件通常被 `.gitignore` 忽略，检出新 worktree 时不会自动携带。AI 检出 worktree 后，应主动检查主工程根目录是否存在相关环境配置文件（如 `.env*`），若存在则拷贝至该 worktree 根目录，避免启动服务或运行测试时因缺少环境配置报错。
- 依赖由人/脚本按 CONFIG.md 准备，不要软链主仓库的依赖目录。

## 6. 人工检查清单

- 每个任务只有一个活跃写者（锁存在且归属明确）。
- `status` 与目录一致。
- `needs-discussion` / `blocked` 没有被当作新任务领取。
- 恢复实施前，批准版本与方案 sha256 都匹配。
- `review_approved` 不是 `done`；`done` 有目标分支与合并提交证据。
- 没有自动合并、push、删除 worktree/分支。
- 任务文件没有被悄悄提交到业务分支。

## 7. 硬性规则

- 不自动合并、不 push、不建 PR、不改 CI、不发版。
- 不删除 worktree/分支；不 reset 用户改动；不覆盖已有任务或文件。
- 不自动迁移旧 `.ai/` 任务，不改写旧状态。
- 没有用户明确批准，不恢复 discussion 任务；没有合并证据，不 done。
- 初始化不会修改项目的 `AGENTS.md`、`CLAUDE.md`、`docs/` 或 `.gitignore`。

## 8. 归档清理

已完成的任务和对应 worktree/分支可用 `/ai-workflow archive`（或「归档清理」）批量整理：

1. 扫描 `done/` 目录，筛选 `status: done` 且 `merged_commit` 非空的任务；
2. 默认只展示归档清单（任务 id、合并提交、目标分支），不直接操作；
3. 用户确认后：
   - 将任务文件移入按日归档目录 `.ai-workflow/archive/YYYYMMDD/${id}.md`（自动创建）；
   - 同步更新 `.ai-workflow/HISTORY.md` 中对应任务状态为 `[done]` 并记录合并证据；
   - 移除对应 worktree（`.ai-worktrees/<id>/`）；
   - 安全删除已合并的分支 `ai/<id>`（`git branch -d`，未合并的不强删）；
   - 清理残留锁 `.ai-workflow/.locks/<id>/`；
   - 从 `.ai-workflow/inbox/GUIDE.md` 移除已归档任务；全部完成后只清空指南，不删除文件。
4. 不 push、不改远程、不处理非 done 状态的任务。

## 9. 最佳实践推荐流（黄金工作流）

`ai-workflow` 底层依赖「原子锁（`.locks/`）」与「独立平级 worktree（`.ai-worktrees/<id>/`）」，天然支持多 Agent 并行而不会发生目录污染或任务抢占。

### 9.1 黄金实践三步走

1. **主会话（规划与拆分）**：
   - 将需求或方案草稿放入 `.ai-workflow/list/<需求>.md`；
   - 运行 `/ai-workflow task 分析 list/<需求>.md 并拆分任务`；
   - 审阅拆分草稿（范围、验收标准、并行条件、依赖顺序），确认后由 AI 写入
     `.ai-workflow/inbox/` 并重建 `inbox/GUIDE.md`。
2. **按指南执行**：
   - 并行任务直接说 `/ai-workflow 并行 T-xxx T-xxx`，默认自动派子代理；
   - 串行任务说 `/ai-workflow run-all` 或「推进全部任务」，主代理只做调度，一任务一子代理；
   - 需要人工讨论时，子代理把任务转入 `needs-discussion`，主代理不替人批准。
   - 示例：前 3 个并行任务先执行 `/ai-workflow 并行 T-001 T-002 T-003`；完成后执行
     `/ai-workflow run-all`，只推进剩余未完成的串行任务。
3. **主工程统一审查与合并（闭环归档）**：
   - 任务完成后自动移入 `review/`，并释放任务锁；
   - 人工在主工程审查 diff 并执行 `git merge`；
   - 全部任务完成后，运行 `/ai-workflow archive` 一键自动归档任务文件、删除已合并分支、清理
     worktree，并清空任务池指南。

### 9.2 子代理调度规则

- 用户说并行、挑并行任务或 `run-all` 时，不需要再提醒“开子代理”，默认直接派发。
- 并行：同一个 `parallel_group` 的可执行任务一任务一子代理并发执行；主代理只收简报。
- 串行：主代理只做调度，一任务一子代理接力；前一个送审后再派下一个。
- `run-all` / “推进全部任务”按指南行序全部串行，不自动把并行组改成并发；并行必须明确要求。
- 子代理默认继承主代理模型。用户明确指定时，优先读取任务的 `agent_model`，否则使用本次指定模型。
- 宿主不支持子代理或模型选择时，先说明限制并停在调度前，不能假装并发。
- 主代理不读源码 diff 和完整日志，只核对 `inbox/GUIDE.md`、任务 front-matter、简报和 git 状态。

### 9.3 任务包批量推进与夜间跑批模型

对于已在白天规划好方案或拆分好的低风险任务包（如多个小优化、一网打尽的 Bug 列表）：

- **串行推进流水线（最常用，也是 `run-all` 默认）**：
  - 指令：`/ai-workflow 串行推进`、`/ai-workflow run-all`、`/ai-workflow 推进全部任务`
  - 机制：
    1. 主代理读取 `inbox/GUIDE.md` 的行序，只派发 `status: new` 任务；即使行内标了并行组，`run-all` 也只串行；
    2. 一个任务一个子代理；子代理在专属 worktree 修复验证并提交送审，只回简报；
    3. Task 2 没有显式 `base_ref` 时，主代理写入 `base_ref: ai/T-Task1`，使其继承 Task 1；
    4. 前一个进入 `review/` 后才接力下一个；遇到 `needs-discussion`/`blocked` 停止依赖链。
  - **优势**：主分支（`main`）一尘不染，任务成果层层累积。下班前启动，第二天早上你只需在 `review/` 中逐级审查或直接审查最后一级，一次性合并入 `main`。
- **并行推进并发（Parallel Fan-out）**：
  - 指令：`/ai-workflow 并行推进` 或 `/ai-workflow run-all --parallel`
  - 机制：只选同一 `parallel_group` 且无依赖、无文件交叉的任务，一任务一子代理并发执行并分别送审。
  - 若指定任务不满足并行条件，降级为串行并说明原因，不强行并发。

### 9.4 Bug 与轻量调整敏捷分级策略

避免为了流程而流程，根据投入产出比（ROI）建立三级分类：

1. **L1 微小调整（直接改，不入池）**：
   - 错别字、文案微调、明显 1~2 行样式/参数修复。直接在日常会话改完、跑测试提交，无需使用任务池。
2. **L2 明确的小 Bug / 样式修复（极简直通车）**：
   - 随手记入 `.ai-workflow/list/buglist.md`，下班前一条指令 `/ai-workflow bugfix` 自动合并拆分并自动修完送审。
3. **L3 复杂 / 根因不明 Bug（严格正规军流转）**：
   - 涉及多模块联动、偶现或数据一致性的重大 Bug。先在 `list/` 或会话中让 AI 只读探索定位根因，出具完整方案并由你批准后，方可编码实施。

## 10. 文件交叉与合并冲突防御

当多个并行任务同时修改同一代码文件时，Git 合并可能产生文本冲突或逻辑冲突。`ai-workflow` 从机制上提供三层防御与标准化处理：

### 10.1 核心防御机制

1. **绝对不自动合并到基准分支**：
   AI 无论怎么改、怎么提交，都限制在自己的分支 `ai/<id>` 和 `.ai-worktrees/<id>/` 临时工作树中。基准分支（如 `main`）永远保持干净安全。
2. **保留完整的隔离现场**：
   发生冲突时，各任务的代码现场完好保留在各自 worktree 中，不会污染主工作区。
3. **强制测试与人工审查**：
   即使 Git 文本自动合入无冲突，也必须通过项目测试套件验证，防止隐式逻辑破坏。

### 10.2 应对与处理的三种模式

- **模式 1：先后合并，后者在 worktree 中 rebase（最常用）**：
  - 任务 A 先合入 `main`；
  - 任务 B 准备合并时发现与 `main` 冲突；
  - 在任务 B 的会话中对 Agent 发送指令：“主分支已更新，请在当前 worktree 中 rebase main 并解决冲突，然后重新跑全量测试”；
  - Agent 在 `.ai-worktrees/T-B` 中完成 rebase 并跑通测试，提交重新审查后再合并。
- **模式 2：明确有前后依赖的任务（指定 `base_ref`）**：
  - 若任务 B 强依赖任务 A 的接口或改动，在任务 B 的 front-matter 中指定：
    ```yaml
    base_ref: ai/T-TaskA
    ```
  - 任务 B 领取时会直接以任务 A 的分支为基准，天然包含 A 的改动。
- **模式 3：核心模块大面积重构（排期串行）**：
  - 涉及同一核心文件的架构大改，建议在拆分阶段排为先后顺序，不建议盲目并行。
