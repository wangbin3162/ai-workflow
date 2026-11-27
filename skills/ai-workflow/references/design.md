# 设计说明

## 为什么生成 README/TEMPLATE/CONFIG/guide.html/inbox/GUIDE.md + 五个目录

- 初始化产物越少，用户越容易找到入口。执行规则只放 README，任务模板放 TEMPLATE.md，
  项目配置放 CONFIG.md。`guide.html` 只画流转和操作，避免再写一份规则；冲突时以 README 为准。
- 已存在的 guide.html 视为用户文件，重复 init 不覆盖；缺失则补上。
- 目录按生命周期压缩为四个：`inbox`（new/needs-discussion/blocked）、`doing`（claimed）、
  `review`（needs_review/review_approved）、`done`（done）。`discussion`、`approved`、`blocked`
  不再单独建目录，状态写在 front-matter 里。
- 增加 `list/` 作为临时输入区：用户放任务列表/方案草稿，`/ai-workflow task` 分析后按 TEMPLATE
  拆分成任务草稿；默认不写 inbox，用户确认后才落盘。
- 增加 `inbox/GUIDE.md` 作为常驻任务池顺序：拆分时先判并行条件，再把未完成任务整体重建为
  并行组和串行链；任务完成归档后移除，全部完成后只清空内容，不删除文件、不累加历史。
  指南不是任务文件，领取范围仍由任务目录和 `status` 决定。
- 不再生成 `.gitignore`：是否忽略 `.ai-workflow/` 由项目自己决定，初始化不碰根 `.gitignore`。
- 不再生成 `config.env`：项目配置独立为 `CONFIG.md`。`init` 预填当前分支，
  初始化会话读取目标 `AGENTS.md` / README / docs / CI，实际验证后填测试命令与依赖安装；
  不把配置塞回 README。

## 为什么不再随初始化分发脚本

用户希望任务流转由会话里的 AI 直接操作。初始化只提供规则和模板：
加锁用 `mkdir`，移动任务用文件移动，状态/批准/合并证据写 front-matter，
方案指纹用 README 里给出的 `shasum -a 256` 命令计算。代价是没有脚本强制校验，
因此 README 和技能都把「必须满足的条件」写成可检查的字段；汇报时也必须说明未验证项。

旧状态机脚本、测试与资产已删除，需要时从 git 历史查看。

## 关键规则

- 只有 `inbox/` 中 `status: new` 可领取；`needs-discussion` / `blocked` 不得领取。
- 讨论、方案批准、审查批准、合并证据分开；方案批准绑定 `plan_version` + 方案正文 sha256 +
  用户原话；方案变化旧批准失效。
- 审查通过不等于合并；`done` 必须有目标分支与合并提交证据；squash/rebase 只能确认合并提交
  在目标分支上，无法证明内容等价。
- 任务锁是 `mkdir`；异常退出的锁由人确认后删除，不自动抢占。
- worktree 设在平级目录 `.ai-worktrees/<id>/`：与任务池目录 `.ai-workflow/` 平级隔离，避免嵌套，也避免用户将任务池纳入版本控制时误包含 worktree。
- 任务模板分层：TEMPLATE.md 明确区分「用户填写」与「AI 自动维护」，降低手写心智负担。
- 归档清理支持 `/ai-workflow archive`：可批量整理 done/ 任务到 archive/，安全清理 worktree 与已合并分支。
- 提供只读辅助脚本（`check.sh`、`status.sh`、`archive.sh`）：作为技能自身的开发与排查工具，不随初始化分发到目标项目。
- 批量执行默认一任务一子代理：并行按同一 `parallel_group` 派发；串行由主代理只做调度，
  按指南接力，子代理默认继承主代理模型，主代理只收简报以控制上下文长度。
- 不自动提交任务状态、不合并、不 push、不删未合并的 worktree/分支。

## 已知限制

- AI 是否严格遵守 README 规则无法由脚本证明；
- squash/rebase 的内容等价无法用 sha 证明；
- 没有 `.claude/settings.json` 的 permissions/hook 层护栏；
- 真实 `claude -p` 未验证，且本工作流不再随初始化分发 runner；
- 子代理并发数、模型选择和上下文隔离能力取决于宿主 Agent，技能只能约束调度流程，不能保证宿主一定支持；
- `guide.html` 只负责图解，可能落后于 README。执行以 README 为准。
