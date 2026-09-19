# mixamo — Mixamo 动画自动化 MCP

Adobe Mixamo（角色自动绑骨 + 动画库）的 Playwright 自动化，暴露为 MCP 工具。
本仓自研（fork 自使用者 projects/mixamo-mcp 原型），非 vendored 第三方。

## 工具（8 个）

| 组 | 工具 |
|---|---|
| 状态 | `status`（登录态/角色/当前动画/参数） |
| 动画库 | `list_animations` / `select_animation` / `set_param`（inplace/mirror/overdrive/arm-space/trim） |
| 角色 | `upload_character`（FBX/OBJ/ZIP → Auto-Rigger） |
| 下载 | `download_animation`（fbx_unity 等 6 格式，skin 可选，S3 拦截下载防 Edge 崩） |
| 绑骨流程 | `confirm_review` / `close_upload_modal` |

## 硬性限制

- **标记点拖放不支持自动化**：Auto-Rigger 的下巴/手腕/胯部/脚踝标记必须由人在
  有头 Edge 窗口手动拖放（screens/upload.py 明确标注）。用 `mixamo_driver_phase1.py`
  的人机协作模式：脚本上传+轮询，人工完成 3 步标记。
- **不要与 main.py / mcp_server.py 并发**：共用 browser_profile 登录态。
- 登录态在 `browser_profile/`（gitignore）；失效时跑 `login_once.py` 重新登录。

## 安装

```sh
cd mcp/mixamo
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# WorkBuddy 全局注册（~/.workbuddy/mcp.json）：
#   command: <repo>/mcp/mixamo/.venv/bin/python
#   args:    [<repo>/mcp/mixamo/mcp_server.py]
```

Edge 通道自动启用（系统装了 Edge 就用 msedge；Playwright 自带 Chromium 在本环境连不上 mixamo.com）。

## 驱动脚本（推荐入口，比裸工具更稳）

| 脚本 | 作用 |
|---|---|
| `mixamo_driver_phase1.py <fbx\|obj>` | 上传 + 人工标记 + 绑骨（轮询到完成） |
| `mixamo_driver_phase2.py` | 下载动画集（walk 带 skin / idle / run / jump，逐动画独立会话） |
| `mixamo_driver_phase3.py`（Blender 内跑） | 组装蒙皮角色 + 4 动作 + 袍子权重锁定 → GLB |

坑清单见 `skills/mcp-mixamo/SKILL.md`。
