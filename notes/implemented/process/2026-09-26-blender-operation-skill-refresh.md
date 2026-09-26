# Note: 更新 Blender 操作 Skill 与 Codex 连接入口

Status: implemented

## 问题

本机 Blender 为 5.2.1 LTS，用户目录已安装社区版 Blender MCP 插件，插件协议版本 4 与仓库收录的 `blender-mcp 1.8.7` 一致。仓库的 `mcp-blender` Skill 仍把通用资产目录写成旧模板路径，也没有覆盖目前人物资产需要的骨架、动作与导出检查。当前 Codex 配置尚未注册 Blender MCP；插件安装不等于当前会话已连接。

## 决策

继续使用仓库收录的社区版 `blender-mcp 1.8.7`，为 Codex 注册该确定版本的入口；不在本轮替换插件或迁移到工具接口不同的 Blender Lab MCP。更新 `mcp-blender` Skill，让它先确认客户端工具、插件状态与监听服务，再选择实时 MCP 或 Blender 命令行执行。为人物资产补充骨架、动作与 GLB 验证步骤，资产路径按本仓 `src/assets/` 和 `docs/art/` 的实际布局描述，并遵守根 `AGENTS.md` 的探索资产保留规则。

本轮连接验证先做只读检查；不为测试修改现有 `.blend` 或覆盖探索资产。当前 Codex 会话启动后不会动态加载新注册的 MCP 工具。手工 MCP 客户端可验证服务与 Blender 的实时连接，新会话再验证 Codex 工具发现。

## 备选方案

- 直接切换 Blender Lab 官方 MCP：当前项目的 Skill 与门禁仍按社区版 25 个工具编写，直接切换会使工具名和验证路径失效；本轮不采用。
- 只更新 Skill、不注册 Codex：当前 Codex 会话无法发现 Blender 工具，无法完成用户要求的试用；本轮不采用。
- 为 `get_addon_status` 错误立即修改 vendored 上游：场景读取已证明连接可用，修复旧版遥测模块超出本次操作 Skill 更新的必要范围；先记录故障，不采用。

## 后果

验证 Skill 结构、项目门禁、Codex MCP 配置与 Blender 插件协议。首次 `get_addon_status` 只读调用暴露社区版 1.8.7 缺少 `blender_mcp.config` 的错误；它不代表连接失败。启动 Blender 端监听后，用要求的 `user_prompt` 调用 `get_scene_info` 并成功读取默认场景的 Cube、Light、Camera，证明实际连接可用。本轮不改 vendored 上游源码，Skill 记录状态工具故障时的只读验证路径。
