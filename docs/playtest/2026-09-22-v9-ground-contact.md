# 实机验收：v9 人物逐 clip 贴地（2026-09-22）

## 报告的缺陷

使用者复查现役人物 `cultivator_tripo_v9` 后反馈：**「这个角色依然是斜着的，不是踩着地面的。」**

这条反馈需要拆成两个独立问题，因为上一轮（Phase 8）已经处理过「斜」，而复查说明它没解决：

| 问题 | 上一轮是否处理过 | 本轮结论 |
|---|---|---|
| 躯干（髋→头）偏离竖直 | 处理过，12.81° → 1.71° | **现已正常**，实测 1.70–2.03° |
| 角色整体是否踩在地面上 | **没有量具，从未测过** | **实测浮空 4–7 cm**，本轮修复 |
| 骨盆是否站在双脚上 | **没有量具，从未测过** | 前移 0.154 m（v7 为 0.051 m），**已量、未修** |

## 证据一：贴地（本轮修复）

### 数字（权威口径 = 蒙皮网格最低顶点）

`tools/art/measure_glb_ground_contact.py`，逐 clip、逐帧：

| clip | 修正前 | 修正后 |
|---|---|---|
| `idle` | +0.0673 m | −0.0000 m |
| `walk` | +0.0410 m | −0.0000 m |
| `run` | +0.0168 m | −0.0000 m |
| `idle_guarded` | +0.0726 m | −0.0000 m |
| `meditate` | +0.0725 m | +0.0000 m |
| `sword_ride` | +0.0726 m | −0.0000 m |
| `jump`（腾空，不参与标定） | +0.0793 m | +0.0793 m |

对照基线：同仓另一个已被使用者接受的 `cultivator_neutral_youth_v7` 四个 clip 都在
**+0.0072 ~ +0.0175 m**。修正前 v9 的 6/7 个 clip 明显超出这个量级。

### 画面

- `v9-ground-contact-before.png` / `v9-ground-contact-after.png`
  —— 同一场景、同一 clip（`idle_guarded`）、同一机位，**Blender 侧 z=0 平面 + 脚部近景 +
  真铅垂参考条**。修正前两只靴子整体悬在参考线之上且**没有接触阴影**；修正后鞋底压在
  参考线上、靴下出现接触阴影。
- `v9-ground-contact-before-after.png` —— 上两者的并排。
- `v9-ground-contact-v7-control.png` —— 被接受控件的同机位对照。
- `v9-ground-before-iso.png` / `v9-ground-after-iso.png`、
  `v9-ground-before-feet.png` / `v9-ground-after-feet.png`
  —— **实机（Godot `jade_paper_sample.tscn`，3/4 斜侧机位）**的前后对照。
  实机远景下 7 cm 的差别很细微，判读请以 Blender 脚部近景为准；实机图的作用是证明
  修正在真实场景里生效、而不是只修了离线渲染的那一份。
  `src/tests/v9_ground_contact_shot.gd` 是拍这两组的脚本。

使用者原始报告截图里的直接证据：脚底**完全没有接触阴影**（阴影只落在身后地面），
且两只靴子的**整个鞋底**都看得见——真人站在地面上不可能同时满足这两点。

### 回归保护

- 运行时断言：`src/tests/test_cultivator_v9_ground_contact.gd`（22 条，含负向控制）。
  阈值 0.08 m 取在两组**实测**骨骼级读数之间（正确 0.0555 / 回归 0.1046）。
- 量具：`measure_glb_ground_contact.py`（顶点级，权威）、`measure_glb_foot_bones.py`
  （骨骼级，给测试定阈值）、`apply_per_clip_ground_offset.py`（逐 clip 施加，默认 dry-run）。

## 证据二：站姿（说明为什么「斜」的观感仍在）

`tools/art/render_upright_check.py` 在真实铅垂参考条旁渲染（`--anchor ankle`）：

| 资产 | 头相对踝的水平偏离 |
|---|---|
| v9（修正后） | 0.2209 m / 8.30° |
| v7（被接受的控件） | 0.2508 m / 10.33° |

**v9 比被接受的控件更接近铅垂线**，因此这个角度不是缺陷量：它主要由站姿的解剖学自然
偏移构成（髋在踝后方、脊柱有生理曲度）。以骨盆为参考系（`--anchor pelvis`）v9 为 3.12°、
v7 为 1.86°，量级正常。

`tools/art/measure_glb_balance.py` 给出的骨盆相对双脚位移：v9 **0.1544 m / 10.22°**，
v7 **0.0507 m / 3.12°**。这是本轮唯一的可疑残余，也是「看起来还是有点后仰」最可能的原因，
但**没有修**——理由与被击败的方案一起记在
[贴地 note](../../../notes/implemented/art/2026-09-22-per-clip-ground-contact.md)：
该值缺少等价的对照基线，而把未确认的目标值烘进姿态正是上一轮手作姿态出错的方式。

## 未完成

- 骨盆前移 0.154 m 的矫正目标未确定（需要第二个人物作对照，或使用者目视确认目标姿态）。
- 编辑器嵌入 Game 视图的人工验收仍未做（长期遗留项，非本轮引入）。
- `meditate` 贴地后盘腿姿态的观感未做目视确认。

## 复现命令

```bash
# 贴地（权威口径，改资产后必跑）
blender --background --factory-startup \
  --python tools/art/measure_glb_ground_contact.py -- \
  --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb

# 施加逐 clip 修正（先 dry-run，确认后再 --apply）
python3 tools/art/apply_per_clip_ground_offset.py \
  --glb src/game/actors/swordsman/models/cultivator_tripo_v9.glb \
  --report <ground_contact_report.json>

# 改完 GLB 必须重导，否则测试读到上一版
godot --headless --path src --import
godot --headless --path src tests/test_runner.tscn
```
