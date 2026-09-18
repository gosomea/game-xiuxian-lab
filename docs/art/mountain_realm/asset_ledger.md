# 资产台账 · mountain_realm

## 一句话

群山宗门美术资产：**AI 代理编写脚本 + 本地 Blender 5.2.1 LTS 程序建模**生成的原创几何，
无下载素材、无素材库、无贴图、未调用图像/3D 生成服务、无骨骼与动画。
唯一外部依赖是 Blender 自带 Python（`bpy` / `bmesh` / `mathutils`）。
不读取旧修仙项目；旧 `movement_garden` 仅复用**素材语言**（配色与构件做法），未导入其资产。

## 条目

| 字段 | 值 |
|---|---|
| 资产名 | `mountain_realm`（群山、宗门建筑、庭院、植被、远山云层）与 `flying_sword`（御剑） |
| 来源 | AI 代理编写脚本 + 本地 Blender 5.2.1 LTS（2026-08-25 构建）程序建模；无第三方素材 |
| 生成脚本 | `tools/art/generate_mountain_realm.py`（阶段 `layout` / `terrain` / `collision` / `sword` / `preview`） |
| 源文件 | `docs/art/mountain_realm/mountain_realm.blend`、`docs/art/mountain_realm/flying_sword.blend` |
| 运行输出 | `src/levels/experiments/character_movement/mountain_realm.glb`、`..._collision.glb`、`..._layout.json`、`src/game/abilities/sword_flight/models/flying_sword.glb` |
| 预览 | `docs/art/mountain_realm/mountain_realm_preview.png`（Cycles 20 采样 + 降噪，1000×640，非运行时素材） |
| 生成日期 | 2026-09-18 |
| 第三方素材 / 许可依赖 | 无（几何与材质均为本仓原创；仅依赖 Blender 自带 Python） |
| 授权记录 | 本仓根目录暂无 LICENSE 文件；对外分发前由使用者补充授权声明 |
| 生成方式声明 | AI 代理编写脚本，Blender 程序建模；未调用图像/3D 生成服务。不在此做平台政策结论 |
| 导出器 | Khronos glTF Blender I/O（Blender 5.2.1 自带） |
| 可复现性 | 脚本内随机量只使用固定种子 `random.Random(1709)` 与 `stable_seed()`（字符码累加，不用受 PYTHONHASHSEED 影响的内置 `hash()`），同一 Blender 版本可复现 |

## 复现命令（仓库根，逐阶段独立进程）

```sh
python3 tools/art/generate_mountain_realm.py layout
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_mountain_realm.py -- collision
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_mountain_realm.py -- terrain
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_mountain_realm.py -- sword
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python tools/art/generate_mountain_realm.py -- preview
```

非 macOS 把可执行文件换成 PATH 中的小写 `blender`。全程 `--background --factory-startup`，
不操作用户已打开的 `.blend`。重跑会覆盖 GLB 与 .blend。

## 数值（2026-09-18 读数）

Godot 侧 Y-up；GLB 直接解析 JSON chunk 读回。

| 产物 | 网格 | 三角形 | 材质 | 图片/动画/骨骼 | 字节 | sha256 |
|---|---|---|---|---|---|---|
| `mountain_realm.glb` | 257 | 50300 | 2+顶点色 | 0/0/0 | 1752104 | `d8317dc6a3139fc99cde7557b5e6b90f2b0409f8702d07f97c0e93e93cf60964` |
| `mountain_realm_collision.glb` | 5 | 45216 | 0 | 0/0/0 | 2339808 | `ebc6e143145f337e707dfeab249de3dfe4665ed0d88df6c72ea1844d39800711` |
| `mountain_realm_layout.json` | — | — | — | — | 23206 | `24cab19f76efe2ab48c330ff6e2eb73c056079077f3dd9a9bf1f1b8e9c03e9c` |
| `flying_sword.glb` | 10 | 486 | 3 | 0/0/0 | 42988 | `3497f1c4739350f8c5f4ab80b3a116930c7b7642f71458938b58a3ad0781f11f` |
| `mountain_realm.blend` | — | — | — | — | 1089900 | `7dd28bfbdc44ed3707692b89b986bb70e7ab115e2869294eaf3d7e9db24af2e0` |
| `flying_sword.blend` | — | — | — | — | 105221 | `b5a6a8e165f82dd052d0ceb265e4aa9d53f22f3aa92ec228e8d361ab5059ad50` |
| `mountain_realm_preview.png` | — | — | — | — | 1076736 | `80446ef9e3bdb11ca56fb8130002ea8464ce2bfe44b2853f5227f402e4e54d2c` |

## 碰撞与视觉的几何关系（已机器校验）

- **山体：视觉与碰撞共用同一批顶点**。逐峰比较两份 GLB 的位置数据（排序后逐顶点比对），
  五峰从小到大全部 `sorted_identical=True`，因此**可接近岩面偏差为 0**，
  而非契约 v1 设想的多边形代理误差。主峰 `MainPeakCol` 由 2 个闭合体组成（0→30 山肩 + 30→36 高台），
  北峰 `NorthPeakCol` 3 个（主壳 + 西北岩肩 + 北侧脊）；两者都保证月台与 30→36 台阶上方不被封盖。
- 碰撞 GLB 只含这 5 个对象，节点名为 PascalCase：`MainPeakCol` / `NorthPeakCol` / `WestPeakCol` / `EastRidgeCol` / `FrontMesaCol`。
- **平台站立面误差 0**：行走面由 JSON `boxes` 的立方体代理提供，`top_y == center.y + size.y/2` 恒等，
  盒由同一 `center/size` 生成视觉与碰撞，不存在二次拟合。
- 壳顶轮廓下沉 `PLATFORM_INSET = 0.05`：平台盒顶面严格等于契约 `top_y`，壳顶藏在其下，
  避免共面闪烁；壳顶只在平台盒之外可见且低 5 cm。
- 视觉 GLB 与碰撞 GLB 的山体包围盒与契约一致（碰撞 x −88.27..79.84、y 0..35.95、z −70.33..55.14）。

## 关键约束（实现时踩过、已修复）

- **禁止共面叠面**：平台盒顶面、其上的铺地/压顶若严格同高，Cycles 的阴影射线会立即自交，
  渲染出**纯黑块**。现约定：装饰面高出其承载面 2 cm（铺地 `top + 0.02`、`jump_step_cap` 12.54、
  廊台 deck 36.41 面等），`shanmen_terrace` 顶面抬高到 30.02。修复后黑块消失。
- **岩壁折面不得自交**：轮廓半径扰动被夹在基准半轴的 0.62~1.42 区间内，否则相邻顶点交叉会产生
  白色薄片尖刺。
- `bmesh.ops.recalc_face_normals` 统一朝外：`from_pydata` 的环绕方向不保证，朝内时 Cycles 发黑。
- 颜色校正：预览用 `Standard` 视图变换而非 AgX（AgX 把纸白青绿洗成灰白）。
- **松树树冠必须落在树干上半段**：三层锥冠按树高比例排布（单层锥高 0.34h、自下而上错开 0.16h），
  最下层锥底 = 树干中点（`-0.50h`）、最上层锥尖高出树顶约 0.17h，主干上端不得露出树冠；
  早期版本把冠放在树干下段，实机画面看起来像倒置的树。逐棵数值断言见下表读数方式。

## 御剑几何（已按契约校验）

| 项 | 契约 | 实测 |
|---|---|---|
| 全长（局部 Z） | 1.80 m | **1.800**（z −1.120 .. +0.680） |
| 最宽（局部 X） | 0.26 m | **0.260**（剑格） |
| 原点/足底面 | 顶面 y = 0 | **y max = 0.000**（y −0.110 .. 0.000） |
| 剑尖朝向 | 局部 −Z | 最 −Z 顶点 (0, −0.035, −1.12) 为剑尖 |

## 自然地形重建（2026-09-18 本轮）

依据 [visual-rebuild](../../../notes/implemented/art/2026-09-18-mountain-realm-visual-rebuild.md)。
旧版"同心叠饼式"山壳（`PEAK_SHELLS` + `shell_mesh` + `rock_bands`）与地形内嵌的建筑/规则平台/云石
（`build_terrain`、`build_decor`、`gable_roof`、`pave_courtyard`、`box_lookup`、`build_peaks`）
**已从生成器删除**，重跑不会再导回旧美术。现由高度场 `terrain_height()` 单源生成：

- 五峰各自独立峰脊方位（主峰东肩/北脊/西肩，北峰西北+东北，西峰西南斜脊，东岭两端上翘，前丘西肩），
  **无两峰同形**；峰顶最高约 46 m，高于 36 m 平台但完全避开建筑/楼梯/落点。
- 谷地基面 `max(0, …)`，并加盆缘抬升把矩形底板边缘藏进山体。
- 平台矩形内取覆盖点最高台顶为权威值，坡脚噪声不参与，避免相邻山脚盖过矮台。
- 植被：9 棵松按 `pine_trunk_*` 盒同位对齐 + 220 处坡脚灌木（噪声布点，避开净空）。

**关键约束（实测）**：`channel_intrusion_m=0.0`（1,938 个平台采样点）、
`valley_floor_min_y=0.0`、碰撞 `non_up=0`（45,216 三角全朝上）、五节点覆盖整片谷地与山面。

**峰脊最终结论（经三轮返工）**：在 1.5 m 采样网格上，凡把峰脊叠加到**台顶矩形之外**的坡面，
都会因梯度突变渲染成竖直薄鳍/刀片。布尔硬裁切（`blocked` 直接归零）会在保护区边缘留下断面；
改为按边界距离平滑衰减（`exclusion_weight`，ramp 9 m）后断面消失，但坡面叠加仍会出鳍。
**最终按审计建议删除坡面峰脊**：峰脊只保留在台顶矩形**内部**、且受建筑/楼梯/落点净空约束的岩肩起伏；
西峰、东岭、前丘不放峰脊（台顶狭小或需完整保留 spawn 庭院）。这样既无薄鳍，也无孤立石塔。

## 未完成 / 未验证

- 未在 Godot 中导入与实机渲染（本轮边界不跑 Godot，由场景/验收代理独占）；**Godot 端可见性、材质与碰撞安装仍待 QA**。
- 手感与配色审美由使用者实机判断；本台账只给可复现读数与几何证据。
- 山体为程序建模的岩石风格化折面，不是雕刻/CG 扫描级写实；远景为低多边形体块。
- 装饰件（檐角、树冠、竹叶、云带、远山）不参与碰撞，属有意设计。

登记人：Blender 资产交付代理；日期 2026-09-18。坐标契约见 [layout-contract.md](layout-contract.md)。
