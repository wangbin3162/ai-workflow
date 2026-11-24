# 架构说明

`ai-workflow` 用**用户手写任务 + 独立 worktree + 人工审查合并**驱动 AI 编码会话。
核心约束：**讨论、批准、审查、合并、归档都必须有人的明确动作。**

对外只有一个技能入口：`skills/ai-workflow`。初始化不生成脚本；任务流转由 AI 按
目标项目里的 `.ai-workflow/README.md` 直接操作任务文件和 git。

## 1. 初始化结构

```text
.ai-workflow/
├── README.md      # 说明 + 状态表 + AI 执行流程
├── TEMPLATE.md    # 任务模板
├── inbox/         # new / needs-discussion / blocked
├── doing/         # claimed
├── review/        # needs_review / review_approved
├── done/          # done
└── list/          # 临时任务列表/方案草稿，供 AI 拆分任务
```

不生成 `.gitignore`、`config.env`、`scripts/`、`docs/`、`templates/`、`.initialized`。
初始化只写 `.ai-workflow/`，不改目标项目 `AGENTS.md`、`CLAUDE.md`、`docs/`、根 `.gitignore`。

幂等：

- README 已存在且首行有 `ai-workflow:v3` 标记 → 视为用户文件，保留，只补缺失目录；
- 已存在的 TEMPLATE.md 保留，不覆盖；
- 未标记的 README、旧 `.initialized` / v1 / v2 结构 → 停止并提示人工迁移，不自动升级；
- 旧 `.ai/`、`scripts/ai-loop.sh` 只警告，不读取、不修改。

## 2. 状态与目录

| status | 目录 | 含义 | 可领取 |
| --- | --- | --- | --- |
| `new` | inbox | 新任务 | 是 |
| `needs-discussion` | inbox | 有重要歧义，等用户补方案并批准 | 否 |
| `blocked` | inbox | 失败/拒绝/中断，需人工 | 否 |
| `claimed` | doing | 已认领，有活跃写者 | 否 |
| `needs_review` | review | 实现完成 + 验证记录已写 | 否 |
| `review_approved` | review | 人工审查通过，**尚未合并** | 否 |
| `done` | done | 人工确认合并并归档 | 否 |

只有 `inbox/` 里 `status: new` 可领取；AI 必须按 status 过滤，不能把 discussion/blocked 当新任务。

## 3. AI 执行方式

没有随初始化分发的脚本。`list/` 只是输入区：用户放任务列表/方案草稿，
`/ai-workflow task` 读取后按 TEMPLATE 拆分，默认只出草稿，用户确认后才写 inbox。

AI 按 README 直接执行：

1. 领取：`mkdir .ai-workflow/.locks/<id>`；任务移到 `doing/`，改 status/claimed_by/at；
2. 只读探索；有歧义 → 写「## 讨论」→ status `needs-discussion`、移回 inbox、删除锁、
   保留 worktree/commit/diff；
3. 方案批准：计算「## 方案」正文 sha256，记录 `plan_version` / `plan_sha256`；
   用户明确批准后才写 `approved_*`；恢复时重新计算并比对；
4. 实施验证 → `review_commit` / status `needs_review`、移到 review、删除锁；
5. 人工审查 → `review_approved_commit` / status `review_approved`，留在 review；
6. 人工合并 → 记录 `merge_target` / `merged_commit` / `merge_method` / 人工确认；
   status `done`、移到 done；
7. 阻塞/拒绝 → status `blocked`、移回 inbox、删除锁、保留 worktree。

AI 不使用额外的状态工具；一致性靠 README 规则与人工检查。

## 4. 锁

- 任务锁：`.ai-workflow/.locks/<id>/`，`mkdir` 原子获取。
- 正常结束：pause/review/block/done 时删除锁。
- 会话异常退出：锁可能残留；确认对应会话结束后由人删除。
- 不在锁存在时领取同一任务；不自动抢占。

## 5. worktree

- 位置：`.ai-workflow/worktrees/<id>/`；分支 `ai/<id>`。
- 基准优先级：任务 `base_ref` → README「项目配置」→ 领取时主 checkout 当前 HEAD。
- 已有同分支 worktree → 复用；目录存在但不是该分支 worktree → 停止报告，不删除、不嵌套。
- 主 checkout 当前在 `ai/<id>` 分支 → 拒绝领取。
- 已处于任务 worktree → 核验仓库/分支后复用。

## 6. 批准与合并证据

- 方案批准：`plan_sha256` 必须与当前「## 方案」正文一致，`approved_version == plan_version`，
  且 `approved_plan_sha256` 相同；方案变化后旧批准失效。
- 审查批准：`review_approved_commit` 必须等于分支当前 HEAD。
- 归档：`merge_target` 是真实分支，`merged_commit` 在目标分支上；
  `merge` 方式要求被批准 commit 是合并提交的祖先。
- squash/rebase 无法用 sha 证明内容等价，只确认合并提交在目标分支上，并如实标注。
- 无代码任务（risk high 只出方案）确认后可归档，但必须写明无代码改动。

## 7. 验证状态

**已验证**（`bash scripts/test-ai-workflow.sh`，临时仓库）：
初始化只生成 README/TEMPLATE + 五目录；不生成 scripts/docs/config/.gitignore；
不修改 AGENTS/CLAUDE/docs/根 .gitignore；幂等并保留用户 README；
未标记 README 冲突不写入；旧 v1 结构不自动升级；旧 `.ai/` 只警告；
verify 能发现结构缺失；单一技能入口；assets 只剩 README。

**未验证 / 限制**：

- AI 是否严格遵守 README 中的状态与批准规则（没有脚本强制）；
- 锁在会话异常退出后的自动恢复（需人工确认并删除）；
- squash/rebase 的内容等价无法用 sha 证明；
- 没有 `.claude/settings.json` 的 permissions/hook 层护栏；
- 真实 `claude -p` 未验证；本工作流不随初始化分发 runner。
