# 2026-09-27 全新移动动作接入与旧版清理

## 实机路径

默认 `Swordsman`、人物动作工作台、移动庭院和青玉纸样板共用 `cultivator_motion_20260927_visual.tscn`。在窗口模式运行 `motion_stage_playtest.gd`，真实输入触发普通步行、御剑和落地，截图分别为 `motion-stage-run.png`（脚本历史命名，画面实际为 1.55 m/s 步行）、`motion-stage-flight.png`、`motion-stage-landing.png`。`garden-character-closeup.png` 与 `garden-character-near.png` 是移动庭院实际画面。全部截图为 Godot 1280×800 渲染读回，不是 Blender 摆拍。

`xianxia_motion_playtest.gd` 读取正式角色 `AnimationPlayer` 与表现层快照：`idle`、`walk`、`run`、`sword_ride`、`jump` 均由真实输入达到，步行 1.55 m/s、疾行 2.25 m/s，Shift 进入与退出疾行各在 4 帧内。窗口模式额外保存 `motion-idle.png`、`motion-walk.png`、`motion-run.png`、`motion-flight.png`、`motion-jump.png` 五张同源截图。`character_movement_playtest.gd` 对庭院的屏幕相对移动、停步、碰撞、镜头与导航全部通过。

## 机械检查

- Blender 导出七段新 Action，构建清单记录旧 Action 采样帧数为 0。
- `measure_glb_ground_contact.py` 对七段逐帧量蒙皮网格最低顶点：六段接地状态偏差在 3 mm 内；跳跃片段脚底最高离地约 0.14 m。
- Godot `--headless --path src tests/test_runner.tscn`：1226 通过、0 失败。
- `python3 tools/verify/run_all.py`：Tier 0 全部通过，27/27 负向控制通过。
- 窗口 `motion_stage_playtest.gd --shot=run,flight,landing`：截图成功，失败 0；窗口 `character_movement_playtest.gd --capture-prefix=...`：四张庭院截图成功，失败 0。

## 删除与保留

[retired_assets.json](retired_assets.json) 列出从当前树删除的 444 个被跟踪文件，覆盖人物建模 v1–v6、废弃动作试验及其专属比较场景和脚本。另外清理 8 个无引用 `.blend1` 备份（其中 1 个在废弃版本目录，7 个在其它目录），并移除旧测试的 `.gd.uid`。v7–v9 人物与其运行时资产继续保留。v7 构建使用的第三方原始 `.blend` 已移至 `docs/art/cultivator_neutral_youth_v7/source/`，保留同一字节内容并更新构建路径。删除不改写 Git 历史。

## 仍需肉眼评估

现役 v9 的材质、造型和各移动场景还没有达到用户提供的江南水墨 2.5D 参考画风。本轮解决动画源、姿态基线、速度映射与旧资产清理；动作节奏和修仙气质需要在游戏实际视角试玩后继续微调。22 骨缺少手指骨，静修无法做清晰结印手型。
