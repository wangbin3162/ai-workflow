# 设计说明

## 为什么只生成 README/TEMPLATE + 五个目录

- 初始化产物越少，用户越容易找到入口；说明集中在一个 README，任务模板单独一个 TEMPLATE.md，
  避免 README/WORKFLOW/docs 多处漂移。
- 目录按生命周期压缩为四个：`inbox`（new/needs-discussion/blocked）、`doing`（claimed）、
  `review`（needs_review/review_approved）、`done`（done）。`discussion`、`approved`、`blocked`
  不再单独建目录，状态写在 front-matter 里。
- 增加 `list/` 作为临时输入区：用户放任务列表/方案草稿，`/ai-workflow task` 分析后按 TEMPLATE
  拆分成任务草稿；默认不写 inbox，用户确认后才落盘。
- 不再生成 `.gitignore`：是否忽略 `.ai-workflow/` 由项目自己决定，初始化不碰根 `.gitignore`。
- 不再生成 `config.env`：基准分支、测试命令、依赖安装写进 README 的「项目配置」，
  由用户/初始化会话补全。

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
- worktree 复用已有分支/目录；不嵌套、不删除、不切用户分支。
- 不自动提交任务状态、不合并、不 push、不删 worktree。

## 已知限制

- AI 是否严格遵守 README 规则无法由脚本证明；
- squash/rebase 的内容等价无法用 sha 证明；
- 没有 `.claude/settings.json` 的 permissions/hook 层护栏；
- 真实 `claude -p` 未验证，且本工作流不再随初始化分发 runner。
