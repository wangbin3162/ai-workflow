# 极简上手流程

## 1. 初始化

在目标工程根目录开 Claude Code：

> /ai-workflow init

只会生成：

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

不生成脚本，也不改 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。
用浏览器打开 `.ai-workflow/guide.html` 看流转；执行规则以 README 为准。
`CONFIG.md` 已预填当前分支；初始化会话按目标 `AGENTS.md` / README / docs / CI 验证命令后，
补测试 / 构建命令与依赖安装。运行 `bash skills/ai-workflow/scripts/verify.sh <目标>` 检查结构。

## 2. 手写任务或从列表拆分

复制 `.ai-workflow/TEMPLATE.md` 到 `.ai-workflow/inbox/T-20260101-001.md`。
至少填 `id`（与文件名一致）、`title`、`status: new`、`risk`、背景和验收标准。
复杂需求先讨论方案，把完整方案写进「## 方案」。

也可以把任务列表/方案草稿放进 `.ai-workflow/list/`，然后在会话里说：

> /ai-workflow task 分析 list/需求列表.md 并拆分任务

AI 默认只展示拆分草稿；你确认后才写 inbox。
拆分时会先判断哪些任务可以并行，并把任务池顺序写入 `.ai-workflow/inbox/GUIDE.md`。
例如前三个任务互不依赖、无文件交叉，后两个串行，指南会标成：

```text
1. [并行 P1] T-20260101-001
2. [并行 P1] T-20260101-002
3. [并行 P1] T-20260101-003
4. [串行] T-20260101-004
5. [串行] T-20260101-005
```

## 3. 在会话里执行

> /ai-workflow 处理 T-20260101-001

AI 会按 README：

1. `mkdir .ai-workflow/.locks/<id>` 加锁；
2. 任务移到 `doing/`，准备 worktree（位置 `.ai-worktrees/<id>/`，分支 `ai/<id>`）；
3. 只读探索；
4. 有重要歧义 → 写「## 讨论」→ status `needs-discussion`、移回 inbox、释放锁，保留已有改动；
5. 用户补方案 → 计算 sha256 → 用户明确批准 → 恢复；
6. 实施、验证、送 `review/`。

批量执行时：

```text
/ai-workflow 并行 T-20260101-001 T-20260101-002 T-20260101-003
/ai-workflow run-all
```

并行和 `run-all` 默认一任务一子代理。串行跑批时主代理只做调度，不直接改代码；
`run-all` / “推进全部任务”按指南顺序全部串行，不会自动并发；要并行必须明确说“并行…”。
子代理默认继承主代理模型。需要某个任务换模型时，在任务里写 `agent_model`，或在指令中直接说明。

## 4. 讨论、批准、恢复

用户明确说「批准版本 N」后，AI 才写：

- `approved_version` / `approved_plan_sha256`（必须与当前方案 sha256 一致）
- `approved_by` / `approved_at` / `approved_note`（用户原话）

方案内容或版本变化后旧批准失效。恢复前 AI 必须重新计算 sha256 并比对。

## 5. 审查、合并、归档

- 人工查看 diff 与「## 验证记录」；
- 人工审查通过：AI 记录 `review_approved_commit`（等于分支 HEAD）、status `review_approved`；
- 人工审查不通过：你写清拒绝原因与修改要求，AI 把 status 改为 `blocked`、任务移回 `inbox/`
  并删除锁；分支、worktree 和已有改动保留。`blocked` 不能当新任务领取，你补充信息或给出
  修改意见、把 status 改回 `new` 后，AI 才能重新认领续做；
- 人工执行合并；
- AI 校验合并提交在目标分支上，记录 `merged_commit`、`merge_target`、`merge_method`，
  status `done` 并移到 `done/`。

squash/rebase 只能确认合并提交在目标分支上，无法用 sha 证明内容等价，必须写明。
审查通过不等于已合并；没有合并证据不归档。

## 6. 归档清理与辅助检查

- 归档清理：在会话里输入 `/ai-workflow archive`（或「归档清理」），AI 会展示 `done/` 中可归档的任务清单，确认后自动将任务文件移入 `.ai-workflow/archive/`，移除对应 worktree 并安全删除已合并的分支。
- 运行时检查：技能自带 `bash skills/ai-workflow/scripts/check.sh <目标>` 检查任务文件状态与锁一致性。
- 状态总览：技能自带 `bash skills/ai-workflow/scripts/status.sh <目标>` 快速查看任务在各阶段的统计。

## 7. 旧结构

旧的 `.ai/`、v1/v2 `.ai-workflow` 结构、旧 `scripts/ai-loop.sh` 都不会自动迁移，
见 [MIGRATION.md](MIGRATION.md)。
