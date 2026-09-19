# v7 中性动画底座 · 验收记录（2026-09-19）

> 依据 `notes/proposed/art/2026-09-19-neutral-youth-animation-base-v7.md`。
> 自动证据一次生成：`tools/art/build_cultivator_neutral_youth_v7.py`。

## 一、自动验证（已通过）

| 项 | 命令 | 结果 |
|---|---|---|
| 门禁 + 负向控制 | `python3 tools/verify/run_all.py --with-tests` | 全绿；负向控制 27/27 |
| 运行时测试 | `godot --headless --path src tests/test_runner.tscn` | **1080 通过 / 0 失败** |
| 样板接线回归 | `test_jade_paper_rigged_animation.gd` | 23 通过，已断言装入 v7 且不含旧青玉长袍 |
| GLB 结构 | builder 内 `verify_glb()` | skin 65 joints；clips = idle/walk/run/jump |
| 动作迁移精度 | builder 内 `verify_action()` | 整数帧端点误差 2e-6 m |

## 二、实机渲染（真实运行，非编辑器预览）

```sh
godot --path src --resolution 1280x800 \
  res://levels/experiments/character_movement/jade_paper_sample.tscn \
  --write-movie /tmp/v7game.png --quit-after 90
```

- 退出码 0；日志无 error / script error / 资源加载失败。
- 截图 `docs/playtest/2026-09-19-neutral-youth-v7-sample.png`：青玉纸白样板中人物
  已换成 v7 中性底座，HUD 状态为「步行 · 高度 0.0 m」，深靛遮挡层与青玉场景可区分。
- 首次验收曾发现 GLB 内嵌中性遮挡贴图只留下 `.import` 边车，清理导入缓存后会
  报 `invalid UID ... using text path instead`。builder 现会把同一 PNG 显式保存到
  Godot 期望的稳定源码路径；重新导入与启动后该警告已消失。

## 三、正脸与脚尖证据

自动截图中人物很小，**脸与脚尖以 Blender 源侧特写为准**（同一 GLB 源，非替代品）：

- `docs/art/cultivator_neutral_youth_v7/renders/v7_rig_head.png` — 正脸、可见眼鼻口耳。
- `docs/art/cultivator_neutral_youth_v7/renders/v7_rig_feet.png` — 双脚脚尖、脚趾完整，
  踝部遮挡层与源皮肤过渡带可见。
- `v7_rig_front/back/side/three_quarter.png` — 四视图；正面为 -Y（导出后 Godot +Z）。
- `v7_pose_{idle,walk,run,jump}_f*.png` — 四动作真实播放姿态。

## 四、明确未达标 / 需人工试玩

- **审美结论归使用者。** 自动通过 ≠ 视觉验收通过。
- 未做头发（note 允许）：底座头部为光头，属临时状态；无硬板发片。
- 遮挡层只服务动作与比例验证，**不代表最终角色美术**。
- 滑步、跳跃节奏、御剑姿态的实机手感未做人工确认；
  `cultivator_skeleton_presentation.gd` 的 `walk_stride_meters=1.6` /
  `run_stride_meters=3.2` 仍沿用旧值，换身体比例后可能需要微调。
- 中性遮挡层在颈、踝两条过渡带处有可见锯齿（逐面着色 + 平滑过渡所致），
  属可接受的底座临时状态。
