# 设计说明

给「为什么这么设计」「要调整本技能」时看。运行机制和命令见目标项目生成的 `.ai-workflow/WORKFLOW.md`。

## 单一入口

旧的 `ai-loop-init` + `ai-loop-task` 两个技能合并为 `ai-workflow`：

- 用户只需记住 `/ai-workflow`；`init` / `task` / 直接提示词三种模式。
- `ai-loop-task` 的自动建任务能力取消：任务由用户手写；`task` 模式只起草，用户确认后才写文件。
- 旧 SKILL 内容归档到 `references/legacy-ai-loop-task.md`，不再被技能发现机制扫描。
- 原因：两个入口会让「初始化」和「写任务」看起来像两套系统，也容易让旧入口继续派工。

## 初始化边界

初始化只写 `.ai-workflow/`：

- 不再生成/搬动 `AGENTS.md`、`CLAUDE.md`、`LESSONS.md`、`docs/code-standards.md`、`.claude/loop.md`；
- 不追加根 `.gitignore`，运行时产物由 `.ai-workflow/.gitignore` 忽略；
- 旧 `.ai/` 只警告，不迁移。

原因：这些文件属于目标项目，初始化技能不应替用户改规则或搬运文档；旧方案把用户的 `AGENTS.md`
搬到 `docs/legacy/`，路径和引用都会变，风险与收益不匹配。

幂等与冲突：

- 同名内容相同 → SKIP；缺失 → CREATE；内容不同 → CONFLICT，整次不写。
- 不因为目录已存在就宣称成功；以 `verify.sh` 与 `check` 为准。

## 讨论优先于默认实现

`needs-discussion` 是独立状态和目录：

- 初始只读探索发现歧义 → 记录事实/问题/方案/建议/代码改动状态 → `pause`；
- 等待讨论的任务不会被 `run` 或 `next` 领取；
- 实施后才发现歧义同样 `pause`，保留 worktree/commit/diff，不 reset、不删除。

原因：默认假设会制造「看起来完成、实际口径错误」的改动；先讨论能把决策留给用户。

## 批准必须绑定内容

只写方案不等于批准，模型自评也不等于批准。因此：

- `plan-seal` 计算「## 方案」正文 sha256 + 版本号；
- `approve` 同时校验版本和 sha，并记录批准人、时间和用户原话；
- `resume` 重新计算 sha，任何内容变化都使旧批准失效；
- `plan-seal` 检测内容变化时清空批准字段。

不采用「status: approved」这类可随手保持一致的状态标签，因为它不能证明用户批准了哪一版内容。

## 五件事分开

任务状态区分：

1. 实现完成（`review` 前）；
2. 验证记录（写在任务里，人工判断厚薄）；
3. 审核通过（`approved/`，`review_approved`）；
4. 人工确认已合并（`done` 的合并证据）；
5. done/归档。

`done` 校验目标分支、合并提交、批准 commit；squash/rebase 无法用 sha 证明内容等价，
只确认合并提交在目标分支上，并在证据里写明边界。

## 锁

- `mkdir` 原子锁，两种运行方式共用；
- 手动会话的锁跨命令存在，不能靠进程退出清理；正常在 `pause/review/block/reject/done` 释放，
  异常用 `release <id>`；
- `run` 的锁只在进程已退出且超过阈值时自动清理；手动锁不自动清理，避免误抢跨轮次讨论的任务；
- `doing/` 无锁视为中断，转入 `blocked/` 并保留 worktree，不消耗 attempts。

## worktree

- 基准优先级：任务 `base_ref` → `BASE_REF` → 主 checkout 当前 HEAD；不臆定 main；
- 已注册同分支 worktree 复用；会话已在任务 worktree 则核验后复用，不嵌套；
- 主 checkout 在任务分支时拒绝领取；
- 复用已有分支时用 merge-base 记录 `base_commit`，避免已有提交被算成 0。

## 不自动提交任务状态

旧脚本会把 `ai: claim/review/...` 提交到当前分支，可能污染用户业务分支。
新脚本只改工作区文件，不 `git add/commit`。代价是任务状态默认不跨机器同步；
需要时由用户自行提交 `.ai-workflow/`。

## 已知未验证

- 真实 `claude -p` 在真实项目中的完整一轮；
- T3 的具体命令/API（不假设、不伪造）；
- squash/rebase 的内容等价校验（无法用 sha 证明）；
- 手动会话锁跨轮次的进程存活判断（只提供显式 release，不做自动抢占）。
