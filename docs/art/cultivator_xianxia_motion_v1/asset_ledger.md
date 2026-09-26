# 修仙移动动作 v1 资产台账

## 现役范围

- 人物外形、纹理、22 骨骨架和蒙皮继续使用 `src/game/actors/swordsman/models/cultivator_tripo_v9.glb` 的静态生产数据；这是使用者允许暂时保留的人物。
- `tools/art/build_cultivator_xianxia_motion_v1.py` 导入后立即清除旧 GLB 的全部七段 Action，从骨架绑定姿态制作新的 `idle`、`idle_guarded`、`walk`、`run`、`jump`、`sword_ride`、`meditate`。旧动画没有任何采样帧进入新 Action。`build_manifest.json` 登记被移除的旧 Action 名与采样帧数 0。
- Blender 源：`cultivator_xianxia_motion_v1.blend`；Godot 导出：`src/game/actors/swordsman/models/cultivator_xianxia_motion_v1.glb`。Blender 自动备份 `.blend1` 保存上一轮试验状态，也进入 Git。
- 现役装配：`src/game/actors/swordsman/cultivator_xianxia_motion_v1_visual.tscn`，由共享 `swordsman.tscn` 和动作预览共同引用。旧 v9 场景不改动。

## 动作语言

| clip | 现役表达 | 制作边界 |
| --- | --- | --- |
| `idle` | 垂袖静立、轻呼吸 | 中轴与双脚保持稳定 |
| `idle_guarded` | 收臂负手 | 双手在背后交汇，默认静止状态 |
| `walk` | 行云步 | 交替支撑，上身稳定，手臂只作小幅变化 |
| `run` | 轻身急步 | 扩大步幅与步频，双手仍收于背后，不作西式冲刺摆臂 |
| `jump` | 屈膝起势、单膝提起、收势落地 | 根的起始贴地偏移固定，腾空高度交给角色物理 |
| `sword_ride` | 错步立于剑上，负手稳定 | 剑和物理飞行仍由原能力包装配 |
| `meditate` | 站桩吐纳、双手聚于腹前 | 22 骨无手指骨，本轮不强做盘腿结印；公开 clip 名保留以兼容工作台 |

## 测量与检查

- `build_manifest.json`：步行足间距 0.6936 m、周期 31 帧，估算自然速度 1.3424 m/s；疾行足间距 0.9141 m、周期 23 帧，估算自然速度 2.3845 m/s。视觉场景的两档播放参考使用这两个数。它们是基于足骨极值的估算值，仍须靠实机观察微调滑步。
- `ground_contact.json`：七段 clip 的网格最低点均落在 2 cm 贴地容差内。`jump` 只检查起始帧，不应将腾空脚持续拉回地面。
- `renders/upright/`：负手静立相对踝铅垂线偏移 0.1277 m，约 4.77°。`renders/motion/` 保存正面、侧面、步态极值、跃起与御剑、吐纳的真实蒙皮渲染。

## 已停用探索版本

- `cultivator_ink_v1`：完全程序建模，近景面部、袖与鞋呈玩偶感；源、导出与七张渲染保留。
- `cultivator_ink_v2`：保留旧网格并重打部分关键帧，但起手仍取旧 Action 的静态姿态；不满足“原动画全部重做”；源、导出、测量与渲染保留。
- `cultivator_paper_v1`、`cultivator_paper_2d_probe`：在使用者澄清之前探索的重做人物路线；用户明确只要求重做动画，所以二者不接运行时，但其源文件、导出和原画均保留。

## 尚待判断

本轮只重新制作动作。场景环境与人物材质尚未统一到参考图的水墨线描画风；使用者已允许人物暂时保留，不能据此声称最终画风完成。
