---
id: T-YYYYMMDD-001
type: feature
title: 一句话说明要做什么
status: new
priority: P1
created: YYYY-MM-DD
base_ref:
claimed_by:
claimed_at:
worktree:
base_commit:
attempts: 0
max_attempts: 2
risk: low
plan_version: 0
plan_sha256:
approved_version:
approved_plan_sha256:
approved_by:
approved_at:
approved_note:
review_commit:
review_approved_commit:
review_approved_by:
review_approved_at:
review_approved_note:
merge_target:
merged_commit:
merge_method:
merged_by:
merged_at:
merged_note:
---

<!--
这是「用户手写任务」模板。复制到 .ai-workflow/inbox/<id>.md 后填写；没有自动建任务的工具。
front-matter 只写简单 key: value，不要写行内注释，值里不要出现 " #"。

状态含义（目录即状态；脚本用 ai-workflow.sh check 校验）：
- new              inbox/       可领取；只有 status: new 会被领取
- needs-discussion discussion/  只读探索发现重要歧义；不会被自动再次领取，需用户补方案并批准后 resume
- claimed          doing/       已认领，同一任务只有一个活跃写者
- needs_review     review/      实现完成且已写验证记录；等待人工审查
- review_approved  approved/    人工审查通过；**尚未合并**
- done             done/        已提供合并证据并人工确认归档
- blocked          blocked/     失败达上限 / 被人拒绝 / 中断；需人工处理
- example          inbox/       示例文件，不会被领取，可删除

字段（脚本维护的字段不要手改）：
- id：唯一，与文件名一致；分支固定 ai/<id>。
- type：bug | feature | chore，仅供人看。
- priority / created：P0 最高；与 created 一起决定领取顺序。
- risk：low | high。high = 碰支付、鉴权、权限、依赖升级、CI、数据迁移、公共接口；
  high 只出方案不改代码；缺失或写错一律按 high。
- base_ref：任务 worktree 的基准分支或提交；空 = .ai-workflow/config.env 的 BASE_REF；
  再空 = 领取时主 checkout 的当前 HEAD。不要假设项目都用 main。
- attempts / max_attempts：失败次数 / 上限，由脚本维护。
- plan_version / plan_sha256：方案版本与内容指纹，由 plan-seal 写入。
- approved_*：用户对某一版方案的明确批准，由 approve 写入。只写方案不算批准；
  方案内容或版本变化后旧批准失效。
- review_commit：送审时的 commit（risk high 只出方案时为 none）。
- review_approved_*：人工审查批准的对象与结论；审查通过不等于合并。
- merge_*：目标分支、合并提交、合并方式与人工确认原话，由 done 校验后写入。

方案批准记录格式（脚本写入，人可检查）：
plan_version: 2
plan_sha256: <「## 方案」正文的 sha256>
approved_version: 2
approved_plan_sha256: <必须与 plan_sha256 相同>
approved_by: <批准人>
approved_at: <时间>
approved_note: <用户批准原话>
有效条件：版本相等且两个 sha 相等；方案内容或版本再变化即失效。
-->

## 背景 / 现象

## 验收标准（必须可验证）

- [ ] 写真实命令或可观察步骤；不要写「跑一下测试」「基本完成」
- [ ] 没跑过的检查写「未验证」并说明原因

## 不要做

- 不改与本任务无关的文件
- 不自行合并、push、发版、改 CI
- 不在 worktree 里自行安装依赖或软链主仓库的依赖目录

## 讨论（只在 needs-discussion 时填写）

### 已确认事实（附文件路径或命令证据）

### 待决问题

### 可选方案与影响

### 建议方案（明确标为建议，不是用户决定）

### 当前代码改动（有 / 无；已提交与未提交各多少）

### 用户下一步（需要补充或批准什么）

## 方案

<!--
讨论结束后把完整方案写在这里。复杂需求可以先沟通，制定好方案后整段贴到本小节。
版本号与内容指纹由 `ai-workflow.sh plan-seal` 记录；
用户明确说「批准版本 N」后，由 `ai-workflow.sh approve` 写入批准记录。
-->

## 验证记录（命令 / 执行目录 / 退出码 / 结果；未验证的写明）

## 人工审查与合并记录（脚本追加，人不改）
