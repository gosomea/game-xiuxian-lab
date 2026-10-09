# Note: 控制人物资产带来的仓库体积增长

Status: implemented

## 问题

人物每个动作版本都保存完整网格、三张内嵌贴图和动作，单版 GLB 约 62.84 MB、Blender 源约 57 MB。贴图相同不代表包含它们的不同二进制可以按内容去重。2026-10-09 本地曾有 8.62 GiB 松散对象，继续全量另存会增加 Git 历史与克隆成本。

旧探索资产必须保留，已有历史不改写。自动备份不是独立建模方案，不能用它代替 `.blend` 源文件的提交。

## 决策

2026-10-10 使用者随后授权历史大文件迁移；下列前向追踪的初始范围由[历史 LFS 迁移](2026-10-10-historical-lfs-migration.md)接替，独立动作管线继续有效。

使用者于 2026-10-09 授权实施，2026-10-10 落地。本仓采用后续资产 LFS 与共享人物加独立动作库：

1. **LFS 只影响后续新资产或内容发生变化的旧资产。** 本机安装 Git LFS，在仓库执行 `git lfs install --local`，配置 clean/smudge 与 pre-push hook。新 `.blend`、`.glb`、`.obj` 走 LFS；大于 5,000,000 bytes 的 PNG 按路径登记。`tools/assets/lfs_legacy_blobs.json` 固定记录采用前 `81726d3` 中的 85 个普通 blob。未修改的旧文件有明确属性例外；旧文件变更后，同步器撤销例外并转为 LFS，不迁移历史，也不重暂存所有旧文件。
2. **属性同步必须先于暂存。** `python3 tools/assets/sync_lfs_attributes.py` 根据工作树内容生成 `.gitattributes`；随后 `git add` 资产与属性文件。`verify-lfs-assets` 是 Tier 0：检查属性新鲜度、已暂存资产确实是 LFS 指针、新增 `.blend1` 未被提交；负向控制覆盖大 PNG 漏登记、普通 GLB blob、旧资产修改后仍豁免、自动备份误提交。
3. **共享人物文件保留在原处。** `cultivator_upright_motion_20261009.glb` 和对应 `.blend` 继续提供该版本的网格、UV、材质、三张贴图、22 骨 rest 与蒙皮。完整旧动作也保留用于回归比较；它们不是每次动作编辑都重写的输出。若网格、蒙皮或 rest 改变，要另存共享模型版本，不能把变更伪装成纯动作更新。
4. **新运行时版本只导出动作。** `models/motions/cultivator_upright_motion_20261010.glb` 无网格、材质、贴图或图片，原生导入为 Godot `AnimationLibrary`。共享视觉仍实例化完整共享模型，由表现层将独立库挂到原 AnimationPlayer 的空命名空间。节点路径、七段 clip、循环方式与操作均保留。首次拆分直接复制 GLB 动画字节，不重采样。
5. **新可编辑源也拆分。** `docs/art/cultivator_motion_library_20261010/cultivator_upright_motion_20261010.blend` 保留本地 Armature、Action 和蒙皮对象，网格数据及材质通过仓库内相对库链接引用原 `.blend`；本地图片数为 0。动作可在可见模型上编辑。Blender 导出器只选择骨架，校验 22 骨 rest/层级与共享模型匹配，并保留 skin 声明让 Godot 识别相同骨骼轨道。
6. **`.blend1` 是临时自动备份。** 新备份被忽略且门禁拒绝误提交；已有五个小备份继续跟踪，不删除。可编辑 `.blend`、动作导出、源资产与交付资产仍全部入 Git。资产保留通则已同步这一分类。

7. **量具保留对共享蒙皮的验证。** 四个 Blender 动作量具兼容 `--blend` 输入，直接在轻量源链接的真实网格上量鞋底、摆臂、姿态与步态。旧完整 GLB 的 `--glb` 命令继续可用。运行时测试另行验证独立库的轨道和重导出姿态，避免把源验证当作运行时验证。

本地打包已在 2026-10-09 完成：`git fsck` 退出码 0；`git gc` 将松散对象 8.62 GiB/0 pack 变为 2 pack/3.88 GiB。Codex 检查点引用保留。这不缩小既有远端历史。

复现与验收见[资产台账](../../../docs/art/cultivator_motion_library_20261010/asset_ledger.md)和[运行记录](../../../docs/playtest/2026-10-10-asset-growth/report.md)。Godot 的独立动作库能力依据[官方导入文档](https://docs.godotengine.org/en/4.6/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html#using-animation-libraries)。

## 备选方案

- 迁移历史到 LFS：需要改写历史与强推，不在实施范围。
- 删除旧 Blender/GLB 或忽略交付资产：破坏探索资产保留，不采用。
- 立即重暂存所有旧资产：造成大量无必要转换与 LFS 上传；保留普通 blob 例外。
- 只改运行时 GLB，动作源仍完整另存：约 57 MB 的源文件重复仍存在；改为相对链接的可编辑源。
- 新动作版本再复制完整共享模型：没有新增网格需求；复用现役文件，避免本轮先新增另一套大文件。
- 删除现有 `.blend1`：体积可忽略且不影响后续方案，继续保留。

## 后果

本轮动作 GLB 为 149,996 bytes，可编辑源为 364,315 bytes；重导出验证 GLB 为 151,448 bytes。三份新二进制合计约 0.67 MB，由 LFS 跟踪。后续动作版本继续共享几何与贴图，旧资产不删除。源和导出需要携带其共享库依赖，不能单独把轻量 `.blend` 复制到仓库之外使用。

LFS 客户端是新克隆的依赖：先安装并 `git lfs pull`，再导入 Godot；指针不能作为模型使用。GitHub 的剩余账号配额尚未确认：`gh api /users/gosomea/settings/billing/usage` 返回 404 并提示缺少 `user` scope。没有扩展凭据权限、修改预算、购买配额或上传 LFS 对象。本次仅本地配置、验证与提交；远端上传须在后续授权 push 时检查账号用量，依据[GitHub LFS 账单说明](https://docs.github.com/en/billing/concepts/product-billing/git-lfs)。
