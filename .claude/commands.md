# 会话命令入口（本仓库自身）

对外只使用一个技能：**`/ai-workflow`**。

- 初始化：`/ai-workflow init`（生成 README、TEMPLATE、CONFIG、guide.html + inbox/doing/review/done/list）
- 整理任务：`/ai-workflow task`（可按 `list/` 里的列表拆分草稿）
- 领取并处理任务：`/ai-workflow <提示词>`，按 [`.ai-workflow/README.md`](../.ai-workflow/README.md)、
  [`.ai-workflow/CONFIG.md`](../.ai-workflow/CONFIG.md) 和 [`skills/ai-workflow/SKILL.md`](../skills/ai-workflow/SKILL.md) 执行
- 归档清理：`/ai-workflow archive`（批量整理 done/ 中的已完成任务并清理 worktree 与已合并分支）

任务流转由 AI 直接操作任务文件与 git：锁用 `mkdir .ai-workflow/.locks/<id>`，
worktree 使用独立平级目录 `.ai-worktrees/<id>/`，
有歧义进 `status: needs-discussion`，恢复前校验方案版本与 sha256，
审查通过不等于合并，`done` 必须有合并证据。没有随初始化分发的脚本。
