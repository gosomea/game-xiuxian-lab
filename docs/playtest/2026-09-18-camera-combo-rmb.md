# 镜头组合环绕与 RMB 归属验收（2026-09-18 第二轮）

Status: 已验收（自动部分）；编辑器嵌入 Game 视图人工验收**未做**

> 决策真源：[可组合实验室装配与镜头契约](../../notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md) §2/§4、
> [角色移动可组合实验室统一决策](../../notes/implemented/gameplay/2026-09-18-character-movement-composable-labs.md) §2 与 S1-b。
> 本轮把 note 里「src/ 实现与证据未落地」的口径落地为可复现证据；本文不覆盖旧的
> [可组合移动实验最终报告](2026-09-18-composable-movement-labs.md) 与旧镜头截图。

## 1. 本轮交付的行为

| 行为 | 落点 | 边界 |
|---|---|---|
| `orbit` 的 RMB 世界区域按下 | `CameraRig.handle_rmb_input()`（`_input` 早期路径） | UI 未占用时**同一输入事件内**进入捕获，不依赖下一物理帧 |
| 非 `orbit` 的 RMB press / release | 同函数 + `CameraRigConfig.consume_unowned_rmb` | 只消费事件；**不捕获、不写 `Input.set_mouse_mode`、不写 `look_delta` / `drag_active`** |
| 默认关闭 | `consume_unowned_rmb = false` | 未开启时保持放行：独立场景不被镜头包抢按键 |
| 交互 GUI 上方右键 | `_gui_wants_mouse()`（`get_viewport().gui_get_hovered_control()`） | 悬停控件可见且 `mouse_filter != IGNORE` 时不处理，GUI 优先 |
| 释放与恢复 | `release_capture()` / `handle_captured_input()` | release / Esc / 失焦 / 离树 / 切模式五条路径都释放并恢复进入前的 `mouse_mode` |
| 组合环绕可发现 | `camera_lab.gd` / `movement_garden.gd` 默认 `orbit` + `ORBIT_HINT` | 常显与详情键表完整写出 WASD / Q-E / 滚轮 / 右键四组输入 |

Q/E 语义未改：`quarter_turn` 离散 90°、`orbit` 连续偏航，其余模式放行。

## 2. 修掉的既存缺陷（根因）

审计未提交 diff 时发现两个**在 HEAD 就已存在、但被 SCRIPT ERROR 掩盖成绿**的缺陷：

1. **`camera_lab_playtest.gd` 读不存在的 API**：`_rig.zoom_min` / `_rig.zoom_max` 在 `CameraRig` 上不存在（`CameraRig` 只暴露 `zoom_size()`；边界在组件 `CameraRigComponent.size_min/size_max`）。HEAD 下这行抛 SCRIPT ERROR 后用例不再执行，因此旧计数看似全绿。
   **修复**：从组件公开边界读取（`(_rig.component() as CameraRigComponent).size_min/size_max`），并给连续缩放循环补上每步一次物理帧——缩放请求由模式在物理帧消费，HEAD 的循环从未真正推进一步就断言。
2. **`character_movement_playtest.gd` 在错误场景调用 `select_module()`**：`_run_hub_gate()` 断言的是顶层实验目录（`LabHub`）的公开 API，但用例跑到那里时 `current_scene` 仍是 `movement_garden`（该方法在 `lab_hub.gd:78`，庭院没有），于是 `Nonexistent function` 被吞。
   **修复**：用例先真实 `change_scene_to_file("res://levels/lab_hub.tscn")` 回到顶层目录再断言；`_run_hub_gate()` 改为 `await`。这是**测试误用**，不是场景 API 回归。

同轮还修掉两处因本轮默认模式变更而失效的断言（不是放宽标准，是把断言的物理量换对）：

- `character_movement_playtest.gd`「D 产生屏幕向右位移」：庭院默认已从 `fixed_follow` 改为 `orbit`（软跟随目标），角色在屏幕上保持居中，固定像素位移不再成立。改为断言世界位移沿**已发布的相机地面基**（`dot > 0.95`）。
- `camera_lab_playtest.gd` 的 `_prepare()` / R 复位：模式切换有 `transition_time` 混合，断言实际渲染姿态前必须等混合收敛（新增有界 `_settle_blend()`），否则读到中间帧。

## 3. 自动证据

命令（Godot 4.6.stable，`--headless`）：

```bash
# 包内直跑（相机包五个套件）
godot --headless --path src res://game/systems/camera_rig/test_camera_rig_runner.tscn

# 主运行测试入口
godot --headless --path src tests/test_runner.tscn

# 两个场景级 playtest
godot --headless --path src --script res://tests/camera_lab_playtest.gd
godot --headless --path src --script res://tests/character_movement_playtest.gd

# 门禁（含运行时测试）
python3 tools/verify/run_all.py --with-tests

# 空白与冲突标记
git diff --check
```

结果（本轮提交前实测）：

| 命令 | 结果 |
|---|---|
| `test_camera_rig_runner.tscn` | 通过 160 / 失败 0；`SCRIPT ERROR = 0` |
| `tests/test_runner.tscn` | 通过 953 / 失败 0（本轮后复测见提交报告） |
| `camera_lab_playtest.gd` | 失败 0（152 PASS） |
| `character_movement_playtest.gd` | 失败 0（58 PASS） |
| `python3 tools/verify/run_all.py --with-tests` | 门禁全部通过（Tier <= 0）+ 负向控制 27/27 + 运行时测试通过 |
| `git diff --check` | 无空白 / 冲突标记 |
| 独立窗口截图序列（`--capture-prefix`，非无头） | 失败 0（66 PASS），14 张 `2026-09-18-camera-combo-rmb-window-*.png` |

§4 五条契约的对应断言：

1. **早期捕获**：`test_camera_rig_executor._test_orbit_early_capture_and_release`（事件内 `is_captured()` 为真）+ `camera_lab_playtest._run_combo_input_path`。
2. **非 orbit fallback**：`_test_unowned_rmb_fallback_consumes_without_capture_or_mouse_mode` + `camera_lab_playtest._run_rmb_fallback`。
3. **不改 mouse mode**：上述两处读 `Input.get_mouse_mode()` 前后相等；只有 orbit 捕获路径可写且必须恢复。
4. **组合输入集成**：`camera_lab_playtest._run_combo_input_path` 在同一 orbit 帧序列里跑 Q/E 连续偏航 + RMB 拖动 yaw/pitch + 滚轮缩放 + WASD 沿新的地面基。
5. **退出恢复**：`test_camera_rig_executor`（release 恢复 `mouse_mode`）、`camera_lab_playtest._run_capture_lifecycle`（Esc / RMB / 失焦）、`rig._exit_tree`、切模式路径。

被删去的脆弱断言（避免镜像实现）：

- 四组输入的逐关键词 `for` 循环（同一条文案事实的 4 次镜像）→ 合并为单次全含判定；
- 组合路径里与 `_run_screen_relative` 重复的 `right_axis/forward_axis` 一致性断言；
- 庭院里与 `test_camera_rig_executor` / `camera_lab_playtest` 重复的 fallback 全矩阵，保留一条场景级冒烟；
- 组合模式里重复的「1/3 键切模式」块（`_run_switch_purity` 已按键遍历全部四模式）。

## 4. 嵌入 Game 视图边界（未验收）

决策要求「独立窗口 + 编辑器嵌入 Game 视图」双形态各验一次。**独立窗口一侧已完成**（真实窗口 + 真实截图，见下）；**编辑器嵌入 Game 视图一侧未做**。

独立窗口实测（`--capture-prefix` 指向仓内 `docs/playtest/`，非无头）：

```bash
godot --path src --script res://tests/camera_lab_playtest.gd \
  -- --capture-prefix=<repo>/docs/playtest/2026-09-18-camera-combo-rmb-window
```

结果：失败 0（66 PASS），产出 14 张真实窗口截图（`2026-09-18-camera-combo-rmb-window-*.png`，含四预设移动、四模式对比、`orbit-rmb-captured` 捕获态、遮挡 / 开阔、缩放远近等）。该序列同时验证了窗口模式下 `Input.get_mouse_mode() == MOUSE_MODE_CAPTURED` 与释放后恢复（无头 dummy 不实现的部分）。

仍未覆盖：

- 「世界区域右键不泄漏为编辑器 / Game 视图的上下文操作」「UI 上方右键不被镜头包劫持」必须在 Godot 编辑器嵌入视图里人工操作确认；本轮**未生成**嵌入视图截图，不得据本文声称双形态通过。

**仍需主代理执行的人工审计**：

1. 在 Godot 编辑器里运行 `camera_lab.tscn` 与 `movement_garden.tscn`（嵌入 Game 视图），确认世界区域右键不弹出编辑器 / 视图上下文菜单；点击 HUD 按钮上方右键确认 GUI 优先、镜头不动。
2. 独立窗口跑一遍：orbit 按住右键拖动改 yaw/pitch、Q/E 连续旋转、滚轮缩放、WASD 沿旋转后地面基；切到 `fixed_follow` 后右键不捕获、光标不消失。
3. 捕获态按 Esc / 失焦 / 切模式，确认光标恢复且无残留捕获。

## 5. 资产审计

本轮**新增 14 张验收预览图** `docs/playtest/2026-09-18-camera-combo-rmb-window-*.png`（真实窗口截图，非临时日志），随本提交一起入库；无新模型 / 贴图 / 音频 / 场景。
`git status --ignored` 复核：`src/.godot/`（引擎导入缓存）、`tools/**/__pycache__/`（Python 缓存）为可再生缓存，不属交付资产；
`mcp/blender-mcp/test_process_bbox_validation.py` 由第三方 vendored 目录自身的 `.gitignore`（`/test_*.py`）排除，是上游 MCP 集成内容、非本项目探索资产。
