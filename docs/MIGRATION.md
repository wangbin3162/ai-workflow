# 迁移说明

当前初始化只生成 `.ai-workflow/README.md`、`TEMPLATE.md`、`CONFIG.md`、`guide.html`、
`inbox/GUIDE.md` 和 `inbox/doing/review/done/list` 五个目录。
旧 `.ai/`、v1/v2 历史结构和运行脚本都不会自动迁移或升级。

## 1. 从旧 `.ai/` 迁移

先备份或提交工作区，再复制（不是移动）：

```bash
mkdir -p .ai-workflow/{inbox,doing,review,done}
cp .ai/inbox/*.md   .ai-workflow/inbox/   2>/dev/null || true
cp .ai/doing/*.md   .ai-workflow/doing/   2>/dev/null || true
cp .ai/review/*.md  .ai-workflow/review/  2>/dev/null || true
cp .ai/done/*.md    .ai-workflow/done/    2>/dev/null || true
cp .ai/blocked/*.md .ai-workflow/inbox/   2>/dev/null || true
```

然后人工调整：

- `needs-discussion` / `blocked` 的任务放在 `inbox/`；
- 旧的 `discussion/`、`approved/`、`blocked/` 目录不再使用，任务按 status 合并到 inbox/review；
- 旧 `needs_review` 留在 `review/`；`review_approved` 也留在 `review/`；
- 旧 `claimed` 若没有对应 worktree/锁，不要当活跃任务，核对后改回 `new` 或 `blocked`；
- 旧 `done` 没有合并证据的，只作为历史记录，不要伪造证据。

## 2. 从带脚本的 v2 结构迁移

上一版 `.ai-workflow` 包含 `scripts/`、`docs/`、`templates/`、`config.env`、`.gitignore`、
`.initialized`、`discussion/`、`approved/`、`blocked/`。新初始化（v3）不会自动升级。

手动处理：

1. 保留已有的任务文件；
2. 把 `discussion/`、`blocked/` 里的任务移到 `inbox/`，确认 status；
3. 把 `approved/` 里的任务移回 `review/`，保留 `review_approved` 记录；
4. 删除旧 `scripts/`、`docs/`、`templates/`、`config.env`、`.gitignore`、`.initialized`；
5. 把旧 README 移走或备份，然后运行 `/ai-workflow init` 生成 v3 README + TEMPLATE + CONFIG + GUIDE + list/；
6. 把项目配置（基准分支、测试命令、依赖安装）写进新 `CONFIG.md`。

## 2.1 已有 v3 精简结构

运行 `/ai-workflow init` 会补建缺失的 `.ai-workflow/CONFIG.md`、`guide.html` 和
`inbox/GUIDE.md`，已存在的文件不覆盖。
README 里旧的「项目配置」内容需要手动搬进 `CONFIG.md`；`README.md` 仍可保留用户修改。
旧任务按 `TEMPLATE.md` 补 `execution` / `agent_model` 字段；不确定并行条件时保持 `execution: serial`。

旧状态机脚本与资产不再保留在仓库中；需要时从 git 历史查看。

## 3. 从 v1（ai-loop-init / ai-loop-task）迁移

- 旧技能入口不再提供；用 `/ai-workflow`。
- 旧脚本 `scripts/ai-loop.sh`、旧 `.ai/` 只提示，不读取、不修改。
- 任务状态与字段按上面的方式人工整理。
- 不要同时让旧流程和新流程派工。

## 4. 合并证据

新流程仍然要求：

1. 人工审查通过（`review_approved`）；
2. 人工执行合并；
3. 记录 `merge_target` / `merged_commit` / `merge_method` / 人工确认原话；
4. 才能 `status: done`。

旧 `done` 任务没有证据的，不要直接当作新流程的归档证据。
