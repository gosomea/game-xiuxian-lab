# 资产增长方案验收 · 2026-10-10

依据：[实施决策](../../../notes/implemented/process/2026-10-09-repository-binary-growth.md)、[轻量资产台账](../../art/cultivator_motion_library_20261010/asset_ledger.md)。使用 CLI 与独立 Godot 窗口验收；未使用编辑器 MCP。

主工作区同时进行移动全局工作台开发。本记录在基于 `17f53fb` 的独立工作区，仅应用本轮资产方案后验证，不代表另一会话尚未提交的功能已验收。

## 结果

| 验收点 | 判定与证据 |
|---|---|
| 后续二进制进入 LFS | PASS：3 份新源/导出在 Git 暂存区均为标准 LFS 指针；未修改的 85 个旧普通 blob 保留。新备份不提交。门禁见 [checks.txt](checks.txt) |
| LFS 门禁真实拒绝非法输入 | PASS：大 PNG 漏登记、GLB 普通 blob、修改旧文件仍豁免、新 `.blend1` 暂存，四项均被拒绝；总负向控制 31/31 |
| 完整旧人物依赖保持 | PASS：旧 GLB、共享 Blender 与贴图内容未改；历史未迁移，资产未删除 |
| 纯动作导出 | PASS：现役 GLB 149,996 bytes，无 meshes/materials/textures/images；七段动作的关键帧、轨道路径、类型、插值和时间与完整 GLB 逐项相等 |
| 可见模型上的轻量源编辑 | PASS：源 364,315 bytes，本地 22 骨/七 Action/0 图片，仓库内相对链接网格与材质；站立真实蒙皮鞋底与原源等价 |
| Blender 重导出 | PASS：验证 GLB 151,448 bytes；骨骼 rest、层级与 Armature 祖先变换一致；七段动作 × 六相位 × 22 骨位置/旋转等价。额外验证改变 Armature 平移会被契约检出 |
| 真实蒙皮量具 | PASS：摆臂、朝向、姿态、逐 clip 鞋底与步态四份 JSON 的 problems 均为空。步态 121 样本，鞋底 −0.003090 至 +0.003528 m，循环接缝角度/位移为 0 |
| Godot 原生导入与运行时 | PASS：全新导入退出 0；全部测试 2023 通过 / 0 失败，含独立库 257 项；原始运行日志无 SCRIPT ERROR/ERROR/FAIL，见 [import.txt](import.txt)、[runtime.txt](runtime.txt) |
| Tier 0 与负向控制 | PASS：全部门禁通过，导出器祖先变换检查与大小写后缀登记修正后再次验证，见 [static.txt](static.txt) |
| 移动真实窗口 | PASS：38/38；八方向、步行 2.0、疾跑 4.2、跳跃、御剑 22 与升降 12 m/s；五张截图均保存，见 [motion.txt](motion.txt) |
| 剑法真实窗口 | PASS（复跑）：24/24；三招、出招右臂、飞剑在外不能御剑、飞回、齐射命中、御剑出剑气及请求释放。首轮远处木桩命中断言失败（23/24），未修改代码重跑通过；两次日志均保留，见 [sword-first.txt](sword-first.txt)、[sword.txt](sword.txt)。首轮原因未确定 |

LFS 正向临时仓库验证还覆盖：保留旧普通 blob、修改旧文件后转 LFS、含空格/方括号的大 PNG、小 PNG 继续普通 Git、大写 `.GLB` 后缀、本地指针生成/对象校验/工作树还原；没有远端上传。

## 命令

```sh
Godot --headless --path src --import
python3 tools/verify/run_all.py --with-tests
Godot --path src --script res://tests/motion_balance_playtest.gd -- --capture-prefix=/absolute/repo/docs/playtest/2026-10-10-asset-growth/motion
Godot --path src --script res://tests/sword_workbench_playtest.gd -- --capture-prefix=/absolute/repo/docs/playtest/2026-10-10-asset-growth/sword
```

Blender 源生成、拆分、重导出与四个量具的完整命令见资产台账。

## 窗口证据

已查看站立、步行、疾跑、跳跃、御剑、飞剑、蓄阵与御剑剑气截图：人物材质完整、骨骼动作正常，飞剑和阵列可见。截图只记录对应瞬间，不替代逐帧量具或主观手感验收。

- [站立](motion-idle.png)、[步行](motion-walk.png)、[疾跑](motion-run.png)、[跳跃](motion-jump.png)、[御剑](motion-flight.png)
- [悬剑](sword-idle.png)、[剑气](sword-qi.png)、[飞剑](sword-strike.png)、[蓄阵](sword-array_hold.png)、[齐射](sword-array_volley.png)、[御剑剑气](sword-flight_qi.png)

## 边界

这次控制后续增长，既有 pack 仍约 3.88 GiB。源与导出依赖共享人物文件，分发时须保留库路径。GitHub 剩余 LFS 配额未确认：账单 API 返回 404 并提示缺少 `user` scope；未扩展权限、修改预算、购买配额或上传对象。本轮只做本地提交，下一次获授权 push 时检查账号用量。
