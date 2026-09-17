# Note: 本地 Git hooks 方案（lefthook vs .githooks）

Status: implemented

## 问题

门禁需要本地快速卡口（秒级，跑与暂存文件相关的检查），CI 拥有全量矩阵。开发机跨 macOS 与 Windows（M4 Pro 主力机 + RTX 5070 台式机），hooks 方案必须跨平台且安装动作对协作者零心智负担。

## 决策

采用 **lefthook**，配置在仓库根 `lefthook.yml`。

- `pre-commit`：跑与暂存文件相关的快速门禁（词汇表、notes 格式、Component 纯度）。
- `pre-push`：跑 `tools/verify/run_all.py` 全量（当前规模为秒级）。
- 安装：`brew install lefthook`（macOS）/ `winget install evilmartians.lefthook`（Windows），随后 `lefthook install`。onboarding 将其列为 clone 后第二步。
- 哲学与 DSH 一致：本地钩子保持快，测试与全量矩阵归 CI。

**未安装 hooks 的协作者不被挡在门外，CI 是最终裁判**——hooks 属开发体验层，不属协作面本体。这条保证使 lefthook 成为「零依赖原则」的可接受例外。

## 备选方案

- **`.githooks/` + `core.hooksPath`**：零依赖，但 Windows 上依赖 Git Bash 环境假设，且需每位协作者手动设置一次 hooksPath（clone 后第一步即劝退）。跨平台是硬约束，故不采纳。
- **husky（npm）**：引入 Node 工具链依赖，与 Godot + Python 技术栈不符，重。
- **只靠 CI，不要本地 hooks**：输在反馈环长度。Tag 打错这类秒级可发现的错误不该等一轮 CI；单人期推送频率低时反馈环更长。

## 后果

- 代价：引入一个外部工具依赖；lefthook 版本漂移风险低（配置语法稳定），onboarding 中不锁定次版本。
- 收益：本地秒级反馈，跨平台行为一致；跳过安装不阻塞协作。
