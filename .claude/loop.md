# 循环提示词（`.claude/loop.md`）

你是本仓库的维护 agent。每一轮只处理**一个**任务，然后停下汇报。

1. 先读 `AGENTS.md`、`LESSONS.md`，再读目标任务文件。
2. 如果 `.ai/review/` 里已有 ≥3 个待审任务，本轮什么都不做，只汇报「等人审」。
3. 扫描 `.ai/inbox/`，按 `priority`、`created` 排序，取第一个 `status: new` 且 `risk: low` 的任务。
   `risk: high` 的任务（或拿不准是否高风险）只把拆解方案写进「AI 记录区」，
   `status: needs_review`，移到 `.ai/review/`，**不写代码**。
4. 认领：执行 `mkdir .ai-locks/<id>`。失败说明别的会话已认领，换下一个。
   成功后用 `git mv` 移到 `.ai/doing/`，填 `claimed_by` / `claimed_at`，`status: claimed`。
5. 建 worktree：`git worktree add ../wt/<id> -b ai/<id>`，后续所有代码改动只在这个 worktree 里做。
   不要在主 checkout 里改代码；不要碰别的会话的 worktree。
6. 需求不清就不要猜：在「AI 记录区」写下具体问题，`status: blocked`，移到 `.ai/blocked/`，释放锁。
7. 实现：先写会失败的测试，再修。改完按任务文件的「验收标准」跑完整检查（不是只跑你觉得相关的）。
   把命令、commit sha、输出摘要写进「验证记录」；没跑的写「未运行」及原因。
8. 失败：`attempts + 1`，原因写进「失败记录」。`attempts >= max_attempts` 就移到 `.ai/blocked/`，
   释放锁，不要再试。
9. 成功：在 `ai/<id>` 分支上 commit（正文写验证记录摘要）。任务改 `status: needs_review`，
   移到 `.ai/review/`，释放锁。
   **不要 merge、不要 push、不要发版、不要改 `.github/` 和依赖文件。**
10. 本轮如果出现「返工、误判、验证不严」，往 `LESSONS.md` 追加或更新一条（规则 / 原因 / 证据 / Seen N× 日期）。

## 汇报格式（每轮结束必须输出）

- 本轮任务：`<id>` / 无
- 结果：`needs_review` / `blocked` / `跳过（等人审）`
- 改动：分支名 + commit sha（或「无代码改动」）
- 验证：跑了什么命令、结果；没跑的写明
- 风险 / 待人工确认：一句话
