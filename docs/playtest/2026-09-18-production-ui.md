# 生产 UI 真实配置复核（2026-09-18）

范围：按 **project.godot 的生产 stretch 配置**复核七场 UI；不改 `project.godot`，不改任何场景 runtime，
不改已有 tests/notes。新增脚本：`src/tests/composable_lab_ui_playtest.gd`（standalone 验收，主 runner 未改）。

## 口径（与 1:1 画布压力图严格区分）

- 生产配置保持 **canvas_items + 基准 1280x800 + keep 等比**，只设 `root.size`，不为凑 PNG 尺寸而改缩放设置。
- 四个量分开记录：请求窗口 `root.size` / 逻辑画布 `get_visible_rect()` / PNG 实际像素 `get_texture()` / 黑边 letterbox。
- **HUD 控件矩形与 `Camera3D.unproject_position()` 同属逻辑画布坐标系**，直接比较，不跨坐标系换算。
- 覆盖率 = **逻辑画布占比**（等比缩放下等于物理像素占比），不用窗口像素除逻辑矩形。
- **统计范围 = LabHud 常显矩形 + 场景自有真实可见面板**（`TimelinePanel` / `LedgerPanel` / `PreviewPanel`，
  按名查找、`is_visible_in_tree()` 判定、去重包含关系），分列「LabHud」与「总量」。
- 角色/相机缺失、角色在相机后方或出画布一律**判失败**，不打印 NOTE 跳过（避免假绿）。

## 最终运行（第 3 次，`--no-capture`，pressure 修完后）

```
Godot --path src --script res://tests/composable_lab_ui_playtest.gd -- --no-capture
```

**结果：0 失败。** 精确断言计数：

| 模式 | PASS | FAIL | 说明 |
|---|---|---|---|
| `--no-capture`（最终矩阵复核） | **325** | **0** | 版面/面积/按钮/遮盖/详情断言 |
| capture（含落盘校验，上一轮） | **347** | **0** | 325 + 22 条「保存 PNG 成功」 |

另有 21 条 `METRIC`（7 场景 × 3 档四项读数）与 22 条 `UI` 面积读数（21 档常规 + 1 条预览态）。
stdout/stderr 扫描：`SCRIPT ERROR` / `freed instance` / `ERROR:` **均为 0 条**（actor 作者的退出期报错在本轮未出现）。

每档断言：全部常显 UI 在逻辑画布内（不裁切）、LabHud 与总量分别 ≤ 15%、可见按钮无空文字、
主要角色在相机前方且不被 UI 遮、详情默认折叠且 F1 开闭不抢控件。

| requested window | logical canvas | scale | PNG actual | letterbox |
|---|---|---|---|---|
| 960x640 | 1280x800 | 0.750 | 960x600 | 上下各 20 px |
| 1280x720 | 1280x800 | 0.900 | 1152x720 | 左右各 64 px |
| 1920x1080 | 1280x800 | 1.350 | 1728x1080 | 左右各 96 px |

## 实际全 UI 总覆盖率（逻辑画布占比）

三档窗口下逻辑画布恒为 1280x800，故同一场景三档数值一致（每档均已断言全在画布内）。

| 场景 | LabHud | 计入的可见面板 | **总量** | 15% 上限 |
|---|---|---|---|---|
| camera_lab | 7.04% | 无 | **7.04%** | 通过 |
| motion_stage（实时） | 5.80% | 无 | **5.80%** | 通过 |
| motion_stage（960 预览态） | 5.80% | PreviewPanel | **14.93%** | 通过（最接近上限） |
| ground_contact_course | 4.50% | 无 | **4.50%** | 通过 |
| sword_flight_course | 4.88% | 无 | **4.88%** | 通过 |
| state_transition_lab | 5.30% | TimelinePanel | **13.24%** | 压力场例外；实测仍低于 15% |
| movement_garden | 5.29% | 无 | **5.29%** | 通过 |
| mountain_realm | 4.42% | 无 | **4.42%** | 通过 |

**压力场修后状态（作者已修完、父级看 v2 通过）**：`TimelinePanel` 保持常显并已计入（浅底），
`LedgerPanel` 现随 LabHud 详情折叠（`state_transition_lab.gd` 的 `_apply_details_visibility()` 经
`details_ui_changed` 驱动，默认收起、H / F1 展开），因此**不计入常显总量**；核心指标摘要与时间线常显。
最接近上限的是 motion_stage 预览态 14.93%。

## 截图文件清单（精确计数）

**`docs/playtest/` 与本次验收相关的 PNG 共 47 张**，分三组，全部保留、无覆盖、无删除：

| 组 | 数量 | 命名 | 性质 |
|---|---|---|---|
| 生产配置 v1 | **22** | `production-ui-<scene>-window<W>x<H>-png<PW>x<PH>.png` | 生产 canvas_items 证据（本报告主证据） |
| 生产配置 v2 | **22** | `production-ui-v2-<scene>-window<W>x<H>-png<PW>x<PH>.png` | 见下方「v2 组说明」 |
| 旧 1:1 画布 | **3** | `2026-09-18-camera-lab-ui-{960x640,1280x720,1920x1080}.png` | **布局压力证据**（一次性 `--ui-size` 关闭 content scale） |

七场 × 三档 = 21 张 / 组，另有 `*-motion_stage-preview-window960x640-png960x600.png`（预览控件取证）。

### v2 组说明（此前报告措辞矛盾，在此更正）

上一轮我做过一次 capture 模式复核，它确实在临时目录 `/tmp/ui-verify/` 生成了 22 张 PNG；
当时我写「未产生新 PNG」指的是**未在仓库新生成文件**，措辞不严、易误读为「没有生成任何图」，**特此更正**。
按本仓「探索与验收资产必须入库、不得静默删除」的要求，这 22 张已另存为 `production-ui-v2-*` 保留。
经 SHA-256 逐一比对：**22/22 与 v1 字节完全相同、0 张不同**（同一配置的重复运行结果），
因此它们是**重复运行的可复现性证据，不是新的版面结论**；v2 不用于支撑任何新结论，主证据仍是 v1。

## 未验证

- 未测其他 DPI / 系统缩放（本轮覆盖 canvas scale 0.750 / 0.900 / 1.350，均为等比缩放）。
- 未做非等比窗口与超宽比例（本轮窗口档为 3:2、16:9、16:9 三种请求尺寸）。
- 未做人眼观感评分（字重、对比度偏好），只覆盖可机械断言的版面与可读性下限。
- 本套检查**不检查前景/背景对比度**；压力场浅底修正是人工审图确认的，不由本脚本机械保证。