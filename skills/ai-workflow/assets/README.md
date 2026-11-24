<!-- ai-workflow:v3 — 本文件由 /ai-workflow init 生成；用户可编辑，重复 init 会保留本文件 -->
# ai-workflow

用**用户手写**的任务驱动 AI 编码会话：AI 只读探索 → 有歧义先讨论 → 用户批准方案 → 实施验证 →
人工审查 → 人工合并 → 归档。**AI 不合并、不 push、不删除 worktree。**

任务状态靠任务文件的 front-matter 和所在目录表达。状态操作由 AI 按本文直接执行，
没有随初始化分发的脚本。

## 1. 目录与状态

```text
.ai-workflow/
├── README.md      # 本文件
├── TEMPLATE.md    # 任务模板
├── inbox/         # new / needs-discussion / blocked
├── doing/         # claimed
├── review/        # needs_review / review_approved
├── done/          # done
└── list/          # 临时任务列表 / 方案草稿，供 AI 拆分任务
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

## 2. 项目配置（初始化后补全）

- 基准分支（`BASE_REF`）：TODO: 填 `dev` / `main` 等；空 = 领取时主 checkout 当前 HEAD。
  不要假设项目都用 `main`。
- 测试 / 构建命令：TODO: 填真实可执行的命令。
- worktree 依赖安装：TODO: 填安装命令；无第三方依赖写「无」。

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
- `risk`：`low` / `high`；缺失或写错按 `high`。`high` 只出方案，不改代码。
- front-matter 只写 `key: value`，不要写行内注释，值里不要出现 ` #`。

### 3.2 从 list/ 拆分任务

`list/` 用来临时放任务清单、需求列表、方案草稿（markdown 即可）。典型流程：

1. 用户把列表写到 `.ai-workflow/list/<名字>.md`；
2. 在会话里说「/ai-workflow task，分析 list/<名字>.md 并拆分任务」；
3. AI 只读分析列表，按 `TEMPLATE.md` 给出拆分方案：每条任务的标题、范围、验收标准、risk、
   依赖顺序；
4. AI 默认只展示拆分结果，**不自动写 inbox**；
5. 用户确认后，AI 才逐条写入 `.ai-workflow/inbox/<id>.md`，仍不领取、不实现。

`list/` 只是输入区，没有状态含义；拆分完成后由用户决定保留或删除原列表。

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

### 4.9 阻塞与拒绝

- 无法继续：`status: blocked`，任务移到 `inbox/`，删除锁，保留 worktree 和 diff。
- 人工拒绝审查：`status: blocked`，记录原因，任务移到 `inbox/`。
- 重新入池：用户补充信息后改 `status: new`，可重新领取。

## 5. worktree

- 位置：`.ai-workflow/worktrees/<id>/`；分支 `ai/<id>`。
- 基准优先级：任务 `base_ref` → 本文「项目配置」的基准分支 → 领取时主 checkout 当前 HEAD。
- 先看是否已有同分支 worktree（`git worktree list --porcelain`）；有就复用，不嵌套创建。
- 目录存在但不是该分支 worktree → 停止并报告，不删除、不覆盖。
- 主 checkout 当前在 `ai/<id>` 分支 → 拒绝领取。
- 已处于任务 worktree 时，先核验仓库与分支，再复用当前目录。
- 依赖由人/脚本按「项目配置」准备，不要软链主仓库的依赖目录。

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
