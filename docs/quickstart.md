# 极简上手流程

## 1. 初始化

在目标工程根目录开 Claude Code：

> /ai-workflow init

只会生成：

```text
.ai-workflow/
├── README.md
├── TEMPLATE.md
├── inbox/
├── doing/
├── review/
├── done/
└── list/
```

不生成脚本、配置、额外文档，也不改 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。
然后打开 `.ai-workflow/README.md`，补「项目配置」：基准分支、测试命令、依赖安装。
运行 `bash skills/ai-workflow/scripts/verify.sh <目标>` 检查结构。

## 2. 手写任务或从列表拆分

复制 `.ai-workflow/TEMPLATE.md` 到 `.ai-workflow/inbox/T-20260101-001.md`。
至少填 `id`（与文件名一致）、`title`、`status: new`、`risk`、背景和验收标准。
复杂需求先讨论方案，把完整方案写进「## 方案」。

也可以把任务列表/方案草稿放进 `.ai-workflow/list/`，然后在会话里说：

> /ai-workflow task 分析 list/需求列表.md 并拆分任务

AI 默认只展示拆分草稿；你确认后才写 inbox。

## 3. 在会话里执行

> /ai-workflow 处理 T-20260101-001

AI 会按 README：

1. `mkdir .ai-workflow/.locks/<id>` 加锁；
2. 任务移到 `doing/`，准备 worktree（分支 `ai/<id>`）；
3. 只读探索；
4. 有重要歧义 → 写「## 讨论」→ status `needs-discussion`、移回 inbox、释放锁，保留已有改动；
5. 用户补方案 → 计算 sha256 → 用户明确批准 → 恢复；
6. 实施、验证、送 `review/`。

## 4. 讨论、批准、恢复

用户明确说「批准版本 N」后，AI 才写：

- `approved_version` / `approved_plan_sha256`（必须与当前方案 sha256 一致）
- `approved_by` / `approved_at` / `approved_note`（用户原话）

方案内容或版本变化后旧批准失效。恢复前 AI 必须重新计算 sha256 并比对。

## 5. 审查、合并、归档

- 人工查看 diff 与「## 验证记录」；
- 人工审查通过：AI 记录 `review_approved_commit`（等于分支 HEAD）、status `review_approved`；
- 人工执行合并；
- AI 校验合并提交在目标分支上，记录 `merged_commit`、`merge_target`、`merge_method`，
  status `done` 并移到 `done/`。

squash/rebase 只能确认合并提交在目标分支上，无法用 sha 证明内容等价，必须写明。
审查通过不等于已合并；没有合并证据不归档。

## 6. 旧结构

旧的 `.ai/`、v1/v2 `.ai-workflow` 结构、旧 `scripts/ai-loop.sh` 都不会自动迁移，
见 [MIGRATION.md](MIGRATION.md)。
