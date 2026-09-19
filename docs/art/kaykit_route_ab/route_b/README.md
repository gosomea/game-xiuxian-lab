# route_b · Mixamo 上传输入（人工 marker 前准备）

一句话：**从已入库的 KayKit `Rogue_Hooded` 上游 GLB，生成可交给 Mixamo Auto-Rigger 的干净静态单网格 T-pose 输入；本阶段到上传/marker 之前停止。**

依据：[KayKit 同模型双路线 A/B note](../../../../notes/proposed/art/2026-09-19-character-model-animation-route-comparison.md) §2「路线 B」、§7 阶段 2；流程纪律见 [mcp-mixamo skill](../../../../skills/mcp-mixamo/SKILL.md)。

> **当前状态：尚未上传、尚未拖 marker。** Mixamo 的全部环节（浏览器会话、上传、人工拖放标记、下载动画）**均未执行**。本目录只产出「上传输入」与「Blender 源工程」。
> marker 拖放**必须人工完成**——既有流程硬约束，脚本与代理都不得代劳。

---

## 1. 输入（只读，未改动）

| 字段 | 值 |
|---|---|
| 路径 | `../upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb` |
| bytes | 3,597,652 |
| sha256 | `93e6e25213009952276d9cf34f5d96a243767334c66f280db0433ddfabb91545` |
| 上游 commit | `672074b73ba276876a19e8816ecdc5241817ab47`（KayKit Adventurers 1.0，CC0） |
| 许可 | CC0 1.0；原件见 `../upstream/kaykit-adventurers-1.0-672074b/LICENSE.txt` |

脚本启动时会**先校验该 sha256**，不匹配立即失败退出（保护固定上游件）。

## 2. 输出（逐文件 bytes；精确 sha256 以 manifest 为准）

| 文件 | 用途 | bytes |
|---|---|---:|
| `rogue_hooded_static.fbx` | **Mixamo 上传输入（首选）** | 171,804 |
| `rogue_hooded_static.obj` | Mixamo 上传输入（备选） | 374,148 |
| `rogue_hooded_static.mtl` | OBJ 材质，含 `map_Kd` | 251 |
| `rogue_hooded_static_texture.png` | 1024x1024 RGBA 贴图 | 39,711 |
| `rogue_hooded_route_b_source.blend` | Blender 源工程（含**保留的披风**） | 238,976 |
| `rogue_hooded_tpose_front.png` | **真 T-pose** 正面预览 1024² | 565,069 |
| `rogue_hooded_tpose_3q.png` | **真 T-pose** 3/4 预览 1024² | 564,525 |
| `prepare_manifest.json` | 机器可读清单（本轮输出哈希的真相来源） | 6,059 |

Blender 的 FBX、`.blend` 与 PNG 写出会携带会话级二进制元数据，因此重复生成时文件 sha256 可能变化；几何、动作清理断言、二次导入结果及本轮精确哈希由 `prepare_manifest.json` 记录。OBJ、MTL 与源贴图在本机复跑中保持逐字节一致。

> **命名冲突提示**：`../previews/rogue_hooded_rest_3q_front.png` 是既有**中性静止**预览（双臂下垂），**未删除、未覆盖**。本目录新增的两张 `*_tpose_*.png` 才是**真 T-pose** 证据。二者用途不同，不得互相替代。

## 3. 上传输入契约（全部由脚本断言）

| 契约 | 实测值 | 判定 |
|---|---|---|
| mesh 数 | **1** | 通过 |
| armature 数（物体 / datablock） | **0 / 0** | 通过 |
| animation（action / NLA） | **0 / 0** | 通过 |
| 姿势 | **T-pose**，`upperarm.l` 与水平夹角 **0.000°** | 通过 |
| 单位 | 米制，高 **2.2513 m** | 通过 |
| 足底 | min z = **-0.000027**（约等于 0） | 通过 |
| 朝向 | 面朝 **-Y**（头部前突 y = -0.589） | 通过 |
| 顶点 / 三角形 | **3,196 / 3,921** | 通过 |
| UV | `UVMap` x1 | 通过 |
| 材质 / 贴图 | `rogue_texture` x1 / 内嵌 PNG 1024² | 通过 |
| 武器 / 道具 | **0**（移除 5 件 / 共 2,030 tris） | 通过 |
| 披风 | **不在上传网格内**（见 §5） | 通过 |
| X 轴居中 | 中心约 0（正负 0.05） | 通过 |

**二次导入验证**（不信任导出返回值，用空 Blender 重新导入）：

| 格式 | mesh | armature | action | verts | tris | 高度 | UV | 材质 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| FBX | 1 | 0 | 0 | 3,196 | 3,921 | 2.2513 | 1 | 1 |
| OBJ | 1 | 0 | 0 | 3,196 | 3,921 | 2.2513 | 1 | 1 |

**无 Blender 的独立交叉核对**：FBX 二进制内 `Deformer=0` / `Skin=0` / `AnimationStack=0` / `AnimCurve=0` / `LimbNode=0`；OBJ 为 `v=3196 vt=1578 vn=2996 f=3921`，`mtllib` 与 `usemtl` 齐备。
FBX **已内嵌贴图**（内嵌 PNG 16,670 bytes，即上游原贴图）；OBJ 走 `map_Kd` 外链旁挂 PNG。

## 4. 执行命令

```sh
cd <repo root>
blender --background --factory-startup \
  --python mcp/mixamo/kaykit_route_b_prepare.py -- \
  --input docs/art/kaykit_route_ab/upstream/kaykit-adventurers-1.0-672074b/Rogue_Hooded.glb \
  --output-dir docs/art/kaykit_route_ab/route_b
```

- Blender 版本：**5.2.1 LTS**（`/Applications/Blender.app/Contents/MacOS/Blender`）。
- 脚本用 `argparse`，路径全部相对仓库或由参数给出，**不硬编码用户目录**；`--role` 仅接受固定值 `rogue_hooded`（几何断言与 marker 说明都绑定该上游件），`--skip-previews` 可跳过渲染。manifest 会记录这两个参数。
- **可重复运行**：同一输入下重跑会得到相同的结构断言和二次导入结果；不要把 Blender 二进制输出的跨会话 sha256 稳定性当作契约。
- 脚本**不覆盖上游 GLB**（只读打开），且不产生 `.blend1` 备份（已显式关闭版本备份）。

## 5. 披风回加步骤（绑骨完成后）

披风**故意不上传**：它是 84 tris 的**刚性片**（上游 `Rogue_Cape`，无 `JOINTS_0` / `WEIGHTS_0`），
留在上传网格里会干扰 marker 判读与自动权重。但它**没有被丢弃**——保存在 `.blend` 中。

- 对象名：`Rogue_Cape_PRESERVED`；集合：`cape_preserved`；84 tris；世界 z = [0.094, 1.236]。
- 自定义属性（随 .blend 保存）：`route_b_rebind_bone = "chest"`、`route_b_rebind_mode = "bone parent / rigid (no skinning weights)"`、`route_b_in_upload_mesh = False`。这里的 `chest` 是 **KayKit 上游骨名**；回加到 Mixamo 骨架时必须人工映射到实际胸骨/脊柱骨名，manifest 也单独记录了这个边界。
- 脚本会在解除蒙皮/父子关系前后比较披风的世界包围盒，最大允许漂移 `1e-6 m`；包围盒与实测漂移写入 manifest，避免披风虽然“还在”但已经错位。

**回加步骤**（Mixamo 绑骨结果回到 Blender 后）：

1. 打开 Mixamo 下载的带 skin 的 FBX（`phase2` 产出的 walk 那条），完成既有 `phase3` 的 cm 转 m 缩放与动作重命名。
2. 把 `rogue_hooded_route_b_source.blend` 里的 `Rogue_Cape_PRESERVED` **追加**（`File > Append`）到该工程。
3. 将披风 **bone-parent 到 Mixamo 骨架的 `chest`**（或按实际骨架命名的等效胸骨），
   `parent_type = BONE`、`parent_bone = "chest"`，**不刷任何蒙皮权重**（保持整片刚体跟随）。
4. 需要更柔的表现时再考虑加次级骨链——**本轮不做**，本轮只准备输入。

> 注意：披风是按**上游 41 骨 T-pose** 的 chest 位置建模的；Mixamo 骨架的 `chest` 朝向与命名不同，
> 回加后需目视校准一次披风的相对位置与朝向，**不要假设直接套用即可对齐**。

## 6. 人工 marker 六点与风险

Mixamo Auto-Rigger 需要 **6 个 marker**（界面分 3 步 Next）。下表是上传后**必须由人**在 Edge 窗口里拖放的点：

| # | marker | 风险 | 人工判断边界 |
|---|---|---|---|
| 1 | **下巴（Chin）** | 中 | 兜帽环绕面部，**必须拖到皮肤下巴**，不要落在兜帽边缘或领口 |
| 2 | **左腕** | 低 | 护腕外露，常规 |
| 3 | **右腕** | 低 | 同上 |
| 4 | **胯部（Groin）** | **高** | **本轮唯一高风险点**：外衣下摆与腿根在竖直方向有重叠（衣摆底约 0.363 / 腿顶约 0.525，重叠约 **0.162 m**），正面看胯部被下摆遮挡。**必须绕到侧方或背面寻找双腿之间的真实几何间隙**，不要照正面衣摆中心拖 |
| 5 | **左踝** | 低 | **必须低于靴筒顶**（既有实测坑：切在靴筒上会缺 Foot 分件） |
| 6 | **右踝** | 低 | 同上 |

**其它人工边界**：
- **手指**：本模型**无手指骨**，手掌是一体化低模几何。Mixamo 生成的 hand 骨链没有对应手指几何可权重，**不要期待握拳或张手等手指动画**——手掌会整体刚性跟随 `hand` 骨（观感正常）。
- **marker 不可自动化**：`mcp/mixamo/screens/upload.py` 明确写 "Marker placement required — not supported"；禁止 select/click 盲拖。
- **不并发**：`main.py` / `mcp_server.py` / 驱动脚本共用同一 browser profile，同时跑会互踩。
- **Mixamo 只保留最后使用的角色**：绑完**立即下载 skin 并本地保存**。

## 7. 本阶段做了什么（可复核的动作清单）

导入后按序执行，每步都有断言：

1. 校验上游 GLB sha256；
2. 导入 GLB（只读）；
3. **清 active action + 全部 76 条 NLA + pose `matrix_basis`**，并 purge 全部 action。
   上游 GLB 导入 Blender 会**自动挂 `1H_Melee_Attack_Chop`** + 76 条 NLA；不清理就会导出攻击姿势，Mixamo 会因 "character is posed" 拒绝。实测清除后 `upperarm.l` 与水平夹角 **0.000°**（真 rest T-pose）。
4. 分件识别：6 个蒙皮人体件（body / head / 双臂 / 双腿）、5 个武器道具、1 个披风、1 个导入器自建 `Icosphere`（骨骼显示体，不在 GLB 内）；
5. 断言三角形：人体 **3,921** + 披风 **84** = **4,005**（与台账「7 mesh / 4,005 tris」一致）；武器 **2,030**；
6. 披风移入 `cape_preserved` 集合、解除蒙皮、记录待绑骨（§5）；
7. 移除 5 武器 + Icosphere，6 个蒙皮件去 ARMATURE modifier、清 vertex groups，再 **join 成单网格**；同时 purge 掉残留的 `Rig` armature datablock（删除 armature **物体**不会删 datablock，留着会被重新导出）；
8. 几何断言：足底约 0、米制高度、X 居中、面朝 -Y；
9. 导出 FBX（内嵌贴图），写贴图并绑定，再导出 OBJ + MTL（含 `map_Kd`）；
10. 渲染真 T-pose 正面 / 3/4 预览（渲染时隐藏披风，只拍上传网格）；
11. 保存 `.blend`；
12. **二次导入** FBX 与 OBJ 到空场景，复核结构（§3）后写 `prepare_manifest.json`。

## 8. 未验证 / 未做（不得当作已完成）

- **未上传 Mixamo**、**未启动浏览器**、**未拖 marker**、**未下载任何动画**。
- 未运行 `mixamo_driver_phase1/2/3.py`；**`phase3` 通用脚本本轮零改动**。
- 未接 Godot：`src/` 零改动；未做导入测试、朝向或材质转换、draw call 实测。
- 未验证 Mixamo 是否真能对这些输入完成 auto-rig（**这取决于人工 marker 结果**）。
- 未验证 Mixamo 骨架的 `chest` 与披风的相对变换（§5 需人工校准）。
- 披风**回加**动作本身未执行（属绑骨之后）。
- 本阶段不涉及路线 A 的任何文件。

## 9. 与旧资产的关系

本目录**全部为新文件**，零删除、零覆盖、零改名，依据[探索资产保留](../../../../notes/implemented/process/2026-09-18-exploration-asset-retention.md)：

| 既有资产 | 状态 |
|---|---|
| `../upstream/kaykit-adventurers-1.0-672074b/*` | **未改动**，sha256 与入库时一致 |
| `../previews/rogue_hooded_rest_3q_front.png` | **未改动**（499,652 bytes），中性静止预览仍在 |
| `cultivator.glb` / `cultivator_jade.glb` / `cultivator_rigged.glb`（基线 C） | **零改动** |
| `mcp/mixamo/mixamo_driver_phase{1,2,3}.py` | **零改动** |

台账 `../asset_ledger.md` 由另一 agent 负责，本目录**不修改**该文件。
