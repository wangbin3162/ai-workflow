<!-- ai-workflow:config-v1 — init 预填当前分支；AI/用户可编辑 -->
# 项目配置

- 基准分支（`BASE_REF`）：{{CURRENT_BRANCH}}

  <!-- init 读取当前分支预填。如果当前不是开发基准（例如 feature 分支），改成 dev/main 等。
       空 = 领取任务时使用主 checkout 当前 HEAD；不要假设项目都用 main。 -->

- 测试 / 构建命令：

  TODO: 填真实可执行的命令。初始化会话应阅读项目的 AGENTS.md / README / docs / CI，
  实际验证后填写；不要编造命令。

- worktree 依赖安装：

  TODO: 填安装命令；无第三方依赖写「无」。

- 备注：

  TODO: 其他与任务执行有关的约定（例如不能跑的命令、必须使用的包管理器）。
