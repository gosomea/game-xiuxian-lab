# 人物动作工作台预览控件真实点击验收（2026-09-19）

范围：**一次可见窗口的真实点击决定性证据**——点击「跑动」动作按钮后自动进入播放、按钮与顶部状态行同步、随后播放按钮可暂停。
其余按钮（单步 / 循环 / 倍率 / A-B 过渡）已有自动回归覆盖，本文件只引用，不重复点击取证。

本次不改 `src/`、`notes/`、`README`；只新增本报告与 4 张新 PNG。

> 提交范围补充（2026-09-19 最终集成）：本报告验收的 `motion_stage.gd` 改动（`_on_action_selected` 自动开播）
> 与 `motion_stage_playtest.gd` 的 clicks 批次、本报告、4 张 PNG 在同一提交内落地；
> owning note 的「尚未落地」事实已同步更新为已实现。

## 1. 被验修复

工作区未提交改动 `src/levels/experiments/character_movement/motion_stage.gd` 的 `_on_action_selected()`：

```gdscript
var changed: bool = bool(_preview.call("select_action", action_id))
if changed:
    var state: MotionPreviewState = _preview.state()
    state.playing = true
```

即「动作真正切换了才自动开播」；重复点同一动作是幂等切换，不会把用户刚做的显式暂停改回播放。
状态机 `MotionPreviewState.select()` 本身仍保持「选择不自动播放」的既有语义。

## 2. 运行环境与命令

| 项 | 值 |
|---|---|
| Godot | `4.6.stable.official.89cea1439`（`/Applications/Godot.app/Contents/MacOS/Godot`） |
| 渲染 | Metal 3.2 / Forward+，Apple M4 Pro |
| 窗口 | **可见窗口**，`--resolution 1280x800`，viewport 1280×800 |
| 场景 | `res://levels/experiments/character_movement/motion_stage.tscn` | 
| 启动模式 | 预览模式（程序动作预览），初始为「待机 · 已暂停」 |

```sh
# 在 /tmp 副本中运行（仓库 src/ 只读引用，未改动）
cp -R src /tmp/pw/project
/Applications/Godot.app/Contents/MacOS/Godot --path /tmp/pw/project \
  --resolution 1280x800 dsh_playtest.tscn
```

## 3. 点击方式与限制（据实声明）

- **未使用 OS 级鼠标注入。** 本机 macOS 未授予 Accessibility 权限：`cliclick` 移动光标报
  `Accessibility privileges not enabled. Many actions may fail.`，且实测 `cliclick m:x,y` 后
  光标读数不变（`cliclick p` 前后均为 `477,745`），故 `cliclick`/`CGEventPost` 路径不可用。
- 因此点击经 **可见窗口的 `get_viewport().push_input()` 真实 GUI 事件管线**：先送
  `InputEventMouseMotion` 建立 hover，再送左键 `InputEventMouseButton` press/release。
- 全程**不使用** `pressed.emit()`、**不直接调用** `_toggle_preview_playing`/`_on_action_selected` 等 handler、
  **不直接写** 预览 state 字段；状态一律经场景公开读数 `preview_snapshot()` 与 HUD 文案回读。
- 坐标取控件 `get_global_rect().get_center()`，与窗口布局一致（见下表）。

### 点击坐标与命中证据

| 控件 | 逻辑坐标（中心） | 命中回读 |
|---|---|---|
| `Action_run` | (966.0, 662.0) | `hovered=Action_run` |
| `PlayButton` | (810.0, 690.0) | `hovered=PlayButton` |

预览面板 `PreviewPanel.mouse_filter = 2`（`MOUSE_FILTER_IGNORE`）。**Godot 4.6 实测语义：父级 IGNORE
不阻断子控件的命中测试**——上表 hover 命中到按钮即为证据；按钮默认 `STOP`，仍正常参与 GUI 命中与点击。

## 4. 状态证据（逐帧回读）

原始日志 `/tmp/pw/playtest.log`（运行时生成，不入库）：

```text
CLICK Action_run   at=966.0,662.0 hovered=Action_run
02 after run click | action=run  playing=true  t= 0.050 | 程序动作预览 · 跑动 · 播放中 | 局部时钟 t=0.05/1.20s（4%） · 倍率 1.00x · A-B 过渡中
03 run advancing   | action=run  playing=true  t= 0.170 | 程序动作预览 · 跑动 · 播放中 | 局部时钟 t=0.17/1.20s（14%） · 倍率 1.00x · A-B 过渡中
CLICK PlayButton   at=810.0,690.0 hovered=PlayButton
04 paused by play  | action=run  playing=false t= 0.201 | 程序动作预览 · 跑动 · 已暂停 | 局部时钟 t=0.20/1.20s（17%） · 倍率 1.00x · A-B 过渡中
05 still paused    | action=run  playing=false t= 0.201 | 程序动作预览 · 跑动 · 已暂停 | 局部时钟 t=0.20/1.20s（17%）
PAUSE_FROZEN t_pause=0.20134 t_40f_later=0.20134 frozen=true
```

决定性链条：

1. **01 初始**：`action=idle`、`playing=false`、顶部「程序动作预览 · 待机 · 已暂停」、`t=0.000`。
2. **点击「跑动」**：`action=run` 且 **`playing=false → true`**，顶部变为
   **「程序动作预览 · 跑动 · 播放中」**；`t=0.050` 起步。这正是用户截图「跑动 · 已暂停」缺的那一步。
3. **姿态与时钟确实在推进**：`t 0.050 → 0.170`，姿态读数同步变化
   （`arm_left=-0.0024 → -0.1130`），不是只换了标签。
4. **点击播放按钮可暂停**：`playing=true → false`，顶部回到「跑动 · 已暂停」；
   再等 40 帧后 `t` 逐位不变（`0.20134 → 0.20134`，`frozen=true`），证明暂停真实生效而非仅改文案。

## 5. 截图

均为 1280×800 真实渲染帧，经 `get_viewport().get_texture().get_image()` 落盘（`err=0`）。

| 文件 | 内容 |
|---|---|
| `2026-09-19-motion-preview-click-01-idle-paused.png` | 初始：待机 · 已暂停，播放按钮显示「播放」 |
| `2026-09-19-motion-preview-click-02-run-playing.png` | **点击「跑动」后：顶部「跑动 · 播放中」，播放按钮变「暂停」，跑动按钮高亮** |
| `2026-09-19-motion-preview-click-03-run-advanced.png` | 时钟推进到 t=0.17，姿态继续变化 |
| `2026-09-19-motion-preview-click-04-paused.png` | 点击播放按钮后：顶部回到「跑动 · 已暂停」，按钮回到「播放」 |

截图 02 与 04 对照可直接读出：顶部状态行、播放按钮文案、跑动按钮选中态三处同时随真实点击改变。

## 6. 其他按钮（引用既有自动回归，本次不重复点击）

单步 / 循环 / 倍率 / A-B 过渡的真实点击回归已由
`src/tests/motion_stage_playtest.gd` 的 `clicks` 批次覆盖（经 `Viewport.push_input()`，
断言 `local_time` 推进、`looping` 切换、`rate` 生效、`transition` 重放）。本报告不复制该矩阵。

## 7. 限制

- **点击注入非 OS 级**：受本机 Accessibility 未授权所限，采用可见窗口真实 GUI 事件管线；
  它验证了 Godot 的命中测试与控件信号链，但不覆盖「OS 光标 → 窗口」这一段系统路径。
  若需 OS 级取证，需先授予辅助功能权限后重跑同一脚本。
- 本次为**单次决定性验收**，非稳定性/压力测试；帧率相关的推进量只做单调性判定。
- 动作仍是程序近似，**无骨骼 clip**（与预览面板文案一致）。
- 运行时中间产物在 `/tmp`（探针脚本与原始日志不入库）；入库的只有本报告与 4 张截图。

## 8. 结论

点新动作自动开始播放这一修复在可见窗口下成立：**点「跑动」→ 顶部由「已暂停」变「播放中」→
角色姿态与局部时钟推进 → 播放按钮可暂停且时钟冻结**。用户先前「按钮点了没作用」的感知
（截图显示「跑动 · 已暂停」）由此闭环。
