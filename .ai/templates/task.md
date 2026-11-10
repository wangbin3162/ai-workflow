---
id: T-YYYYMMDD-001            # 唯一，日期-序号
type: feature                 # bug | feature | chore
title: 一句话说明要做什么
status: new                   # new → claimed → in_progress → needs_review → done | blocked | rejected
priority: P1                  # P0 最高，P3 最低
created: YYYY-MM-DD
claimed_by:                   # 会话名或 worktree 名，如 loop-a（由 agent 填）
claimed_at:                   # ISO 时间（由 agent 填）
attempts: 0                   # 每次失败 +1（由脚本 / agent 维护）
max_attempts: 2               # 到上限就进 blocked/
branch: ai/T-YYYYMMDD-001     # 每个任务一个分支
budget_usd: 3                 # 单任务花费上限，对应脚本的 MAX_BUDGET_USD
risk: low                     # low | high；high = 碰支付、鉴权、依赖、CI、数据迁移、公共接口
---

## 背景 / 现象

<!--
bug：复现步骤、环境、期望 vs 实际、截图/日志路径。
feature：要解决的用户问题、现有做法、为什么现在做。
-->

## 验收标准（必须可验证）

- [ ] 新增测试：去掉本次修改时该测试必须失败
- [ ] `<项目检查命令>` 全绿（写真实命令，不要写“跑一下测试”）
- [ ] （UI 变更）Chromium 与 WebKit 各一张截图，路径写进验证记录

## 不要做

- 不改公共接口 / 数据格式 / 依赖（如有例外，在这里写清楚）
- 不顺手重构无关文件

## AI 记录区（agent 追加，人不改）

### 拆解

### 验证记录（在哪个 commit 上跑了什么、输出是什么；没跑的写“未运行”）

### 失败记录
