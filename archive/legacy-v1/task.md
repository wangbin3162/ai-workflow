---
id: T-YYYYMMDD-001
type: feature
title: 一句话说明要做什么
status: new
priority: P1
created: YYYY-MM-DD
claimed_by:
claimed_at:
attempts: 0
max_attempts: 2
risk: low
---

<!--
也可以对 agent 说「新增任务：…」（技能 ai-loop-task），按本模板追加一条，不必手抄。

字段说明（front-matter 里不要写行内注释；值里不要出现 " #"）：
- id：唯一，日期-序号；必须与文件名一致。分支固定为 ai/<id>。
- type：bug | feature | chore。仅供人看，脚本不读。
- status：新任务写 new。之后由脚本（或交互会话里的 agent）维护，不要手改。
  合法值：new → claimed → needs_review → done | blocked；example 表示示例，不会被领取。
- priority：P0 最高，P3 最低；与 created 一起决定领取顺序。
- claimed_by / claimed_at / attempts：由脚本维护，新任务保持原样。
- max_attempts：失败几次后进 blocked/；不写则用脚本默认值。
- risk：low | high。high = 碰支付、鉴权、权限、依赖升级、CI、数据迁移、公共接口；
  high 只出方案不改代码。缺失或写错一律按 high 处理。
单任务预算不支持：预算只有脚本的全局 MAX_BUDGET_USD。
-->

## 背景 / 现象

<!--
bug：复现步骤、环境、期望 vs 实际、截图 / 日志路径。
feature：要解决的用户问题、现有做法、为什么现在做。
-->

## 验收标准（必须可验证）

- [ ] 新增测试：去掉本次修改时该测试必须失败
- [ ] `<项目检查命令>` 全绿（写真实命令，见 docs/code-standards.md「构建与检查」；不要写「跑一下测试」）
- [ ] （无测试框架时）写明人工复现步骤，以及修改前后可区分的现象

## 不要做

- 不改公共接口 / 数据格式 / 依赖（如有例外，在这里写清楚）
- 不顺手重构无关文件
- 不在 worktree 里自己装依赖、不软链主仓库的 node_modules

## AI 记录区（脚本 / agent 追加，人不改）

### 拆解

### 验证记录（在哪个 commit 上跑了什么、输出是什么；没跑的写「未运行」）

### 失败记录
