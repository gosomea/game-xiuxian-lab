# 视觉重建 · 环境与集成接口（环境集成代理）

- 日期：2026-09-18。决策依据 [mountain-realm-visual-rebuild](../../../notes/implemented/art/2026-09-18-mountain-realm-visual-rebuild.md)。
- 本文件只记录**接口与装配事实**；审美结论与最终验收归主代理与使用者。

## 我的写集

| 文件 | 内容 |
|---|---|
| `src/levels/experiments/character_movement/mountain_realm.tscn` | 天空（ProceduralSkyMaterial）、Environment（环境光 / 雾 / tonemap）、Sun、Camera |
| `src/levels/experiments/character_movement/mountain_realm.gd` | 相机默认值、庭院附加层装配、默认镜头取证钩子 |
| `docs/experiments/mountain-visual-integration.md` | 本文件 |

其他代理的产物我只读不写：地形 `mountain_realm.glb` / `mountain_realm_collision.glb`；庭院 `mountain_realm_courtyards.glb` / `mountain_realm_courtyards_collision.json`；角色 `cultivator.glb` 与表现脚本。原 `mountain_realm_layout.json` 75 盒与三能力契约不动。

## 相机（本轮已改，QA 可读常量）

- 默认近景：`CAMERA_SIZE = 30.0`（原 48），滚轮下限 `7.0`，上限 `240.0`，偏移 `Vector3(15, 19, 16.5)`。
- 只改镜头数值，未改角色尺寸、速度、重力、物理胶囊。
- 屏幕相对方向不变：相机地面基仍由场景每帧写入角色，断言仍为 `_camera.unproject_position` 位移方向。
- QA 从脚本常量读 `CAMERA_SIZE`（`_scene_constant`），因此改默认值不需要改测试。

## 曝光与色彩管理（本轮返工重点）

症状：v2 默认镜头整块地面近乎纯白、树瓦成亮斑。**根因不是旧 GLB**——实测材质反照率正常
（Granite mid `0.215`、Pine needles `0.10`、Jade tiles `0.078`），问题在光照预算过大：
glTF 的 `baseColorFactor` 是**线性**值，「Ivory paving `0.78`」本身即约 230/255 的显示亮度，
再叠加 sun 0.62 + 天空环境光 0.28 + 曝光 0.88 后必然顶到 255 被剪切。

处理（逐项实测 bisect，见 `src/tests/mountain_visual_playtest.gd` 的 `--diag`/`--sun`/`--ambient-energy`/`--exposure`/`--sky-energy` 开关）：

| 项 | 返工前 | 返工后 | 理由 |
|---|---|---|---|
| `light_energy`（Sun） | 0.62 | **0.40** | 主光不再是白化源 |
| `ambient_light_energy` | 0.28 | **0.10** | 天空环境光贡献降到补充量 |
| `tonemap_exposure` | 0.88 | **0.55** | 在浅色石材反照率之上留出中间调余量 |
| `sky_energy_multiplier` | 1.0 | **0.5** | 天空仍读得出蓝，但不把世界洗白 |
| `fog_sky_affect` | 0.35 | **0.15** | 保留地平线雾，减少对天空的叠加 |

实测（真实默认镜头 1280×800，采样地面/屋顶/天空/角色四区）：**纯白剪切 0.0%**，
均值由 `(242,248,247)` 降到 `(179,191,184)`；地面可见铺砖分格与阴影，树为深绿、瓦为青绿、修士为靛袍。
高空俯瞰天空为可读的浅蓝渐变，非纸白。

复现命令：

```
Godot --path src --script res://tests/mountain_visual_playtest.gd -- --capture-prefix=<前缀>
```

## 天空 / 光照 / 雾（`gl_compatibility` 实测有效）

- 背景：`background_mode = 2`（Sky），`ProceduralSkyMaterial` 顶色 `(0.427,0.616,0.827)`，地平线 `(0.847,0.890,0.925)`，地平线以下用灰绿地面色，`sky_curve = 0.15`，`sky_energy_multiplier = 0.5`。不再是纸白背景。
- 环境光：`ambient_light_source = 3`（Sky），energy `0.10`（见上表）。
- 雾：启用了 Godot 的 **depth fog**（`fog_enabled` + `fog_density = 0.0025`、`fog_aerial_perspective = 0.4`、`fog_sky_affect = 0.15`、高度雾 `fog_height = 10` / `fog_height_density = 0.02`）。**未使用体积雾**（Forward+ 特性），未改全局 renderer。
- 日晒：`Sun` 角度 `(-48, -38, 0)`，`light_energy = 0.40`，暖白 `(1.0, 0.953, 0.867)`，阴影开启，`directional_shadow_max_distance = 260`。
- Tonemap：Filmic，`tonemap_exposure = 0.55`。

## 庭院附加层装配（我的接入逻辑）

- 路径：视觉 `mountain_realm_courtyards.glb`（**preload 硬依赖**），碰撞 `mountain_realm_courtyards_collision.json`（`schema = peak_courtyards_collision/1`，装配期断言）。
- 庭院是正式必要产物：缺视觉即脚本加载失败，schema 不符即装配失败。**不再保留「两个都缺仍照常」的静默降级**——那会留下隐形旧碰撞或缺院子的场景。
- 节点路径：视觉 `World/CourtyardVisual`；碰撞 `World/CourtyardCollision/<box name>`。
- **原 `World/BoxCollision` 仍恰好 75 个布局盒**，既有集成断言（数量与逐盒路径）不受附加层影响；跨容器重名则在装配期直接失败。
- 庭院 GLB 以世界坐标原点生成（实测 `jump_step` 位于 `(-35.5, 12.275, 30.0)`，与 layout 一致），场景不再做二次偏移。

## 取证与性能采样（已与生产场景隔离）

截图与性能采样**不在生产场景内**，全部位于独立测试脚本 `src/tests/mountain_visual_playtest.gd`
（环境集成代理所有）。生产 `mountain_realm.gd` / `mountain_realm.tscn` 只含环境、装配、输入与表现。

```
/Applications/Godot.app/Contents/MacOS/Godot --path src \
  --script res://tests/mountain_visual_playtest.gd -- --capture-prefix=<绝对前缀> [--diag=…]
```

- 以真实默认镜头（不改 `size`、不移动角色）取证并打印 `PERF default_size=… avg_fps=… avg_frame_ms=…`；
- `--diag` 与数值覆盖（`--sun` / `--ambient-energy` / `--exposure` / `--sky-energy`）仅在运行期生效，不写回场景文件；

## 当前状态与依赖（2026-09-18 收尾）

- 全部依赖已就绪并冻结：地形 heightfield `mountain_realm.glb` / 五壳 `mountain_realm_collision.glb`、庭院 `mountain_realm_courtyards.glb`（17 材质合并节点）+ 33 盒附加碰撞、人物 `cultivator.glb` 与纯表现层脚本。地形接口见 [terrain-interface](../../art/mountain_realm/terrain-interface.md)。
- 本场景脚本最终形态：天空 / 雾 / 日晒 / 相机 / 庭院附加层 / HUD / 输入；`_build_visual()` 只把名为 `Terrain` 的主高度场网格关投影（断言恰好 1 个），松树与灌木保持投影。
- 已知冲突已解决：附加碰撞放在独立容器 `World/CourtyardCollision`，`World/BoxCollision` 仍恰好 75 盒。
- **本轮视觉重建的最终运行结论与截图以 QA 报告 [2026-09-18-mountain-visual-rebuild.md](../../../docs/playtest/2026-09-18-mountain-visual-rebuild.md) 为唯一当前结论**；本节以下为过程记录。

## 过程记录（数值返工期，资产为临时旧版）

以下为 2026-09-18 曝光返工阶段的过程证据，当时地形 / 建筑 / 人物仍是旧临时资产；
它们只证明天空、雾、光照、相机与庭院接入生效，**不代表最终画面**，保留用于追溯返工理由：

| 文件 | 说明 |
|---|---|
| `v1-courtyard-default-spawn.png` | 庭院接入后的默认镜头（旧地形） |
| `v3-final-default.png` | 曝光返工后的默认镜头（零剪切，中间调） |
| `v3-mountain-overview.png` | 曝光返工后的高空俯瞰：浅蓝天空与地平线雾 |
| `diag-lights-off.png`、`step-c1-c1.png` | 诊断与 bisect 过程图 |
| `v2-lit-default-spawn.png`、`v2-mountain-overview.png` | 返工前的对照（偏白，保留作证据） |
| `capture-default.log`、`capture-v2.log`、`import.log` | 原始日志 |

（当时的集成断言 `--batch=assembly,collision,landing_summit` 通过；最终矩阵以 QA 报告为准。）

## 最终视觉缺陷修复（2026-09-18，冻结资产 d8317dc6 / ebc6e143 / 建筑 971984a5 / 角色 70fc5eb6）

### 1. 山体碎黑斑 —— 已定位为 shadow acne，按授权方案消除

同视角诊断对（`--shot=summit`，仅运行期开关）：

| 图 | 结论 |
|---|---|
| `z-shadow-on-summit.png` | 保持阴影：山坡出现大片碎块/条纹（未修前，树/灌木也被一并关阴影） |
| `z-shadow-off-no-shadow.png` | 关闭 Sun 阴影：碎斑完全消失 |

提高 `shadow_normal_bias` / 收紧阴影距离只能减轻，无法稳定消除。最终采用授权兜底：
**仅主高度场节点 `Terrain` 的 `cast_shadow = OFF`，该节点仍接收阴影**。
`_build_visual()` 只按精确节点名 `Terrain` 关闭，并断言该节点恰好 1 个；
同 GLB 内的松树与灌木保持默认投射（此前按"全部网格"关闭会让树看起来悬浮）。
建筑与角色同样照常投射，接地感保留。
限制（记录在案）：山体自身不再向谷地投远大阴影，远景层次靠雾与明暗面区分。

修复后 `final-summit`：碎斑 0，极暗像素 0.00%，铺地/坡面/屋顶均值分别为 152/166/183 亮度，层次可读。

### 2. 浅色石材过曝 —— 已在场景侧做局部材质校正

根因同前：glTF `baseColorFactor` 是线性值，Ivory paving `0.78` 本身已近显示白。
处理：`_tone_down_bright_materials()` 在**庭院实例内** `duplicate()` 材质并按
`BRIGHT_ALBEDO_SCALE = 0.55` 压暗反照率，命中键 `ivory / plaster / limestone / step stone`。
**不改美术 GLB、不改源材质、不影响旧庭院**。主峰铺地由纯白降至亮度 152，仍保留石材质感与分格。

### 3. 天空上下硬线 —— 已消除

原因：程序天空地平线以下的 `ground_bottom_color` 与地平线色差异过大，形成一条横贯画面的分界。
处理：`ground_bottom_color` 改为接近 `sky_horizon_color` 的浅蓝灰、`ground_curve` 放缓，
雾色与地平线同族，远景由雾自然衔接。

实测同一张 vista 的纯天空列（右侧无地形处）自 y=0 到 y=180 为
`(192,201,203) → (186,195,196)`，**单调平滑、无跳变**。

### 4. 构图无效的根因（测试隔离修正）

`_apply_shot` 原先只设置一次生产相机，而 `mountain_realm._physics_process` 每帧
`_follow_camera` 又把同一相机写回角色位置，因此多次改参数得到的仍是同一角度。
修正：vista 使用**独立 `Camera3D` + `make_current()`**，捕获后断言实际 `pos/size` 与请求一致
（输出 `CAMERA assert size_ok=true pos_ok=true`，且 `current=VistaCamera`）。
生产相机与跟随逻辑未改；测试脚本已清理为 `default / vista / summit` 三种模式。

### 5. 角色分件表现 —— 实际两帧变换已验证

`--verify=rig`（真实按键行走，非仅检查脚本存在）：

```
RIGCHECK pivots legs=2 arms=2
RIGCHECK t0 leg0=(0.074,0.696,-0.033) leg1=(-0.074,0.696,-0.033)
RIGCHECK t0 arm0=(0.166,1.421,-0.025) arm1=(-0.166,1.421,-0.025)
RIGCHECK delta leg0=0.18459 leg1=0.18459 arm0=0.11944 arm1=0.11944
RIGCHECK opposite=true (leg0=0.1846 leg1=-0.1846)
RIGCHECK RESULT PASS
```

枢轴停在髋 y≈0.696 / 肩 y≈1.421，无离体漂移；两腿反相说明真实步态而非复制同一枢轴。

## 交付三图（`~/.cache/game-xiuxian-lab/visual-rebuild/`）

| 文件 | 内容 |
|---|---|
| `final-default-default.png` | 生产相机 spawn 近景（`CAMERA_SIZE=30`，未改） |
| `final-summit-summit.png` | 主峰宗门庭院（碎斑消失、铺地中间调） |
| `final-vista-vista.png` | 独立取证相机五峰全貌（天空平滑、无地形悬空切边） |
| `z-shadow-on-summit.png` / `z-shadow-off-no-shadow.png` | 阴影诊断对 |

## 范围说明（如实记录，不继续铺大背景）

本场景是**有限地形范围内的展示**，不是无限世界：地形为 180×160 m 的有限网格，
场景边界由 `World/Boundaries` 的实体墙与顶棚约束，越界下沿由 `fall_out_y` 回收。
远景仅由程序天空、深度雾与一块非碰撞的远地面 `DistantFloor` 衔接，**不构成可探索的远景世界**；
更远的山脊/大气层次留待后续细化。相机缩放上限已收紧到 `CAMERA_SIZE_MAX = 170`，
避免拉到露出地形截断面的角度。
