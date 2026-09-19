# Playtest · 青玉纸白样板第二轮（扩景 + 人物替换）

- 日期：2026-09-19
- 场景：`res://levels/experiments/character_movement/jade_paper_sample.tscn`
- 方式：Godot 4.6 `--write-movie` 真实渲染截帧（gl_compatibility，1280×800，第 60 帧），run 日志 0 error
- 证据：[2026-09-19-jade-paper-sample-round2.png](2026-09-19-jade-paper-sample-round2.png)

## 本轮新增

- 山门牌坊（北侧）、石灯笼 ×2（台阶两翼）、竹丛 ×4（西侧成组）、草簇 ×12（聚散）、
  水塘（低饱和青蓝 + 暗色基座 + 石岸岩 + 护环不可趟水）、三板石桥、北侧远山剪影带。
- **人物替换**：混元生成 → Blender 按衣装结构切割为 13 命名分件（+肩垫 ×2 遮肩缝），
  `cultivator_visual.tscn` 换引用 `cultivator_jade.glb`（34,013 tris，Decimate 后），
  分件刚体动画契约完整保留（`test_actor_assembly` / motion 系测试全绿）。

## 验证

- `tools/verify/run_all.py --with-tests` 全绿（959 通过 / 0 失败）。
- 旧 `cultivator.glb` sha256 不变（另存策略）。

## 已踩坑（机制层结论回写台账）

- 正交视野 35 m 外一切被雾吞没、近距高墙（混元远山 45 m）会填满整帧；
  远山甜点 = 台基正后方 25–45 m、6–10 m 矮山包剪影（多轮标定）。
- 混元人物切割：bisect 前必须全选顶点、切后 separate(LOOSE)、只切跨越切面的碎片
  （否则碎片 2^N 爆炸超时）；join 必须按去偶基名分组（Blender 重名自动加 .001）；
  踝切线要低于靴筒顶。

## 未验证

- 交互手感 / 御剑动作视频（方向 note 验收 §2）留待实机试玩；审美结论归使用者。
