# AGENTS.md — agent 工作规则

本文件是 AI 在本仓库工作的总规则，`CLAUDE.md` 通过 `@AGENTS.md` 引入，`LESSONS.md` 是错题本。
任务池在 `.ai/`，运行方式见 `.claude/loop.md` 和 `scripts/ai-loop.sh`。

## 1. 先读什么（路由表）

| 你要做的事 | 先读 |
| --- | --- |
| 任何任务 | 本文件、`LESSONS.md`、目标任务的 `.ai/**/<id>.md` |
| 领取 / 实现任务 | `.claude/loop.md`、`.ai/templates/task.md` |
| 改脚本或任务池结构 | `docs/ARCHITECTURE.md` |
| 遇到失败或返工 | `LESSONS.md`，命中已有条目就按条目执行 |

## 2. 工作循环（一次只做一个任务）

1. 读 `AGENTS.md`、`LESSONS.md`。
2. `.ai/review/` 已有 ≥3 个任务时，本轮不领新任务，只汇报「等人审」。
3. 按 `priority`、`created` 排序扫描 `.ai/inbox/`，取第一个 `status: new` 的任务。
4. 认领：`mkdir .ai-locks/<id>`（只有一个进程能成功）；成功后在主 checkout 里
   `git mv` 文件到 `.ai/doing/`，填 `claimed_by` / `claimed_at`，`status: claimed`。
5. `git worktree add ../wt/<id> -b ai/<id>`，之后所有代码改动只在该 worktree 内。
6. 需求不清就停下：记录问题，`status: blocked`，移到 `.ai/blocked/`，释放锁。
7. 实现：先写会失败的测试，再改代码；按任务文件的验收标准跑完整检查。
8. 失败：`attempts + 1`，原因写入「失败记录」；达到 `max_attempts`（默认 2）就进 `blocked/`。
9. 成功：在 worktree 分支上 commit（正文带验证记录摘要），任务改 `status: needs_review`，
   移到 `.ai/review/`，释放锁。
10. 出现返工、误判、验证不严时，更新 `LESSONS.md`。

## 3. 硬性护栏（不得越过）

- **不自动合并**：不执行 `git merge`、不把 `ai/*` 合进主分支。
- **不 push**：不执行 `git push`，不添加 / 修改 remote，不建 PR。
- **不发版、不改 CI**：不碰 `.github/`、部署配置、release 流程。
- **`risk: high` 只出方案**：碰支付、鉴权、权限、依赖升级、公共接口、数据迁移、CI 的任务，
  只在任务文件「拆解」里写方案，`status: needs_review` 后交人批，不改代码。
- **不改他人 worktree**：每个 worktree 只属于创建它的任务。
- **不做无关重构**：只改任务需要的文件；顺手发现的问题写成新任务放进 `.ai/inbox/`。
- **验收标准不能自己放宽**：验收标准由人写在任务文件里；做不到就进 `blocked/`，不许改成「基本完成」。
- **没跑就写「未运行」**：验证记录里必须写真实命令、commit sha、输出摘要；没跑写原因。

## 4. 任务文件约定

- `status` 必须与所在目录一致，不一致视为异常，移到 `.ai/blocked/`。
- 人写：front-matter、`背景`、`验收标准`、`不要做`。
- agent 写：`claimed_*`、`attempts`、`AI 记录区`。
- 文件名 = `<id>.md`，分支 = `ai/<id>`。

## 5. 经验记录格式（写进 LESSONS.md）

每条包含四行：

```
### <一句话规则>
- 原因：为什么会犯
- 证据：commit / 日志 / 任务 id，可核查
- Seen：N 次（最近一次 YYYY-MM-DD）
```

规则在 3 个不同日期重复出现后，升级为「硬性护栏」或写进任务模板的「不要做」。

## 6. 完成前自检

- 有没有超出任务范围？
- 有没有把没验证的事写成已完成？
- 有没有用 workaround 掩盖根因？
- 有没有留下临时文件、调试代码、无关改动？
- 锁释放了吗？worktree 与分支名是否与任务 id 一致？
