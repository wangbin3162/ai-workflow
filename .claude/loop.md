# 循环提示词（`.claude/loop.md`）— 交互会话模式

适用于在主 checkout 里用 `/loop` 或手动触发。**这个模式下状态归你管**（移文件、改 `status`）；
无人值守脚本 `scripts/ai-loop.sh` 的 worker 模式相反：状态归脚本管，见 `docs/ARCHITECTURE.md` 第 4 节。
硬性规矩见 `AGENTS.md`，验收与提交格式见 `docs/code-standards.md`，这里不重复。

你是本仓库的维护 agent。每一轮只处理**一个**任务，然后停下汇报。

1. 先读 `AGENTS.md`、`LESSONS.md`，再读目标任务文件。
2. `.ai/review/` 里已有 ≥3 个待审任务，本轮什么都不做，只汇报「等人审」。
3. 扫描 `.ai/inbox/`，按 `priority`、`created` 排序，取第一个 `status: new` 的任务。
   `risk` 不是 `low`（含缺失、写错、拿不准）的任务**只出方案**：把拆解写进「AI 记录区」，
   `status: needs_review`，移到 `.ai/review/`，不写代码，到此结束。
4. 认领：`mkdir .ai-locks/<id>`。失败说明别的会话已认领，换下一个。
   成功后移到 `.ai/doing/`（已提交过的用 `git mv`，没提交过的用 `mv`），填 `claimed_by` / `claimed_at`，`status: claimed`。
5. 建 worktree：`git worktree add .worktrees/<id> -b ai/<id>`，后续所有代码改动只在这里做。
   需要装依赖时按 `docs/ARCHITECTURE.md` 的 worktree 依赖策略做。
6. 需求不清就不要猜：在「AI 记录区」写下具体问题，`status: blocked`，移到 `.ai/blocked/`，释放锁。这不消耗 `attempts`。
7. 实现：先写会失败的测试，再修。按任务文件的「验收标准」跑完整检查，不是只跑你觉得相关的。
   命令、commit sha、输出摘要写进「验证记录」；没跑的写「未运行」及原因。
8. 失败：`attempts + 1`，原因写进「失败记录」。`attempts >= max_attempts` 就移到 `.ai/blocked/`，
   否则退回 `.ai/inbox/`，`status: new`；释放锁，不要当轮重试。
9. 成功：在 `ai/<id>` 分支上 commit（正文按 `docs/code-standards.md` 三段式）。
   `status: needs_review`，移到 `.ai/review/`，释放锁。
10. 本轮出现返工、误判、验证不严，往 `LESSONS.md` 追加或更新一条（格式见该文件）。

收尾前跑一次 `scripts/ai-loop.sh check`，确认 `status` 与目录一致。

## 汇报格式（每轮结束必须输出）

- 本轮任务：`<id>` / 无
- 结果：`needs_review` / `blocked` / `跳过（等人审）`
- 改动：分支名 + commit sha（或「无代码改动」）
- 验证：跑了什么命令、结果；没跑的写明
- 风险 / 待人工确认：一句话
