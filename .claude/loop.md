# 交互会话入口（本仓库自身）

对外只使用一个技能：**`/ai-workflow`**。不要在这里复制整套流程。

- 初始化另一个项目：`/ai-workflow init`
- 整理/拆分任务：`/ai-workflow task`
- 领取并处理任务：`/ai-workflow <提示词>`，流程见 [`skills/ai-workflow/SKILL.md`](../skills/ai-workflow/SKILL.md)
  与 [`skills/ai-workflow/assets/WORKFLOW.md`](../skills/ai-workflow/assets/WORKFLOW.md)

本仓库自己的示例任务池在 `.ai-workflow/`；状态机脚本是 `scripts/ai-workflow.sh`。

强制顺序：

1. 先 `claim`，只读探索，不改业务代码；
2. 有重要歧义 → 填「## 讨论」→ `pause`，任务进 `discussion/`；
3. 用户补方案、`plan-seal`、明确批准、`approve`、用户要求后 `resume`；
4. 实施验证 → `review`；不自动合并、不 push、不删 worktree；
5. 人工 `approve-review` 并合并后，`done` 才会归档。
