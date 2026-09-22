# Phase 8 失败的中间矫正迭代（保留，勿删）

以下目录是「把躯干矫正做成独立 FBX 往返工具」时的失败重跑，每个约 198 MB：

| 目录 | 失败原因 |
|---|---|
| `20260921-ship7-upright/` | 导出器写入 Armature 平移轨道，下游地面位移二次叠加 → 浮空 1.09 m |
| `20260921-ship7-upright2/` | 加了物体级曲线清理，但导出器仍重新写上 |
| `20260921-ship7-upright3/` | 改成清空物体动画，连骨骼动作一起清掉 → 构建报 `import produced no action` |
| `20260921-ship7-upright4/` | 只清物体级曲线、保住骨骼动作；数值已正确，但仍需 FBX 往返，最终改为构建期矫正后不再使用 |

`lean_fix/` 是同期的单 clip 试作（idle / idle_guarded）与铅垂线校验导出。

**为什么不删**：探索资产保留规则要求保留被替换的源与导出资产。这四批的失败模式已记入
`docs/art/cultivator_tripo_v9/asset_ledger.md` 的 Phase 8，数值记入各自的 `lean_summary.json`。
它们不是当前资产链的一部分，**不要**在构建时引用。

最终资产链是 `20260921-ship7/`（源）+ 构建期内存矫正 → `exports/cultivator_tripo_v9_runtime_v6.glb`。
