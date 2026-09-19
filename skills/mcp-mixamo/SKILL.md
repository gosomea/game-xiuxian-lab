---
name: mcp-mixamo
description: Use when the character needs a Mixamo skeleton/auto-rig or animation clips — 用 mixamo MCP 把自产角色上传自动绑骨、按需下载动画库动作（walk/run/idle/jump 等）、组装成带 AnimationPlayer 的 GLB 进 Godot。不用于权重绘制级修型（走 Blender 手工）、不用于非人形角色。
---

# mcp-mixamo

mixamo MCP 提供 8 个工具但不含流程纪律。本文件补上：完整管线（上传→人工标记→绑骨→下载→组装）、
每步的验证方式、以及实测踩坑。真相来源：`mcp/mixamo/README.md`、
`docs/art/jade_paper_sample/asset_ledger.md`、`mcp/mixamo/mixamo_driver_phase{1,2,3}.py`（推荐入口）。

## 硬性前置（不满足则停止并告知用户）

1. **标记点拖放必须人工完成**：Auto-Rigger 的下巴/双腕/胯部/脚踝标记，自动化不支持
   （screens/upload.py 明确标注）。跑 `mixamo_driver_phase1.py`（人机协作：脚本上传轮询，
   人在有头 Edge 窗口拖标记 + 3 步 Next），不要试图用 select/click 盲拖。
2. **登录态**：`browser_profile/` 持久化；`status` 返回未登录时跑 `login_once.py`。
3. **不并发**：main.py / mcp_server.py / 驱动脚本共用同一 profile，同时跑会互踩。
4. **上传格式**：单网格 FBX/OBJ（多部件先在 Blender join）；带 UV；米制、足底 z=0、面朝 -Y。

## 推荐流程（驱动脚本，已内置全部坑的规避）

```sh
cd mcp/mixamo
# 1. 上传 + 人工标记 + 绑骨（脚本轮询，人在 Edge 完成标记）
venv 或 python3 mixamo_driver_phase1.py <character.obj|fbx>
# 2. 下载动画集：Walking(带skin) / Idle / Running / Jump Up，inplace=on，fbx_unity 30fps
mixamo_driver_phase2.py
# 3. Blender 组装（cm→m 缩放、动作重命名、袍子权重锁定）→ cultivator_rigged.glb
blender --background --factory-startup --python mixamo_driver_phase3.py
```

裸工具入口：`status` 永远先看（登录态/角色名/T-pose/下载参数）；`list_animations(query)` →
`select_animation(id)` → `set_param` → `download_animation`。

## 权重修正（长袍角色必做）

Mixamo 自动权重会把下摆刷到腿骨 → 动画时衣服撕扯。phase3 的权重锁定：
按原始分件岛分类，袍子（裙/摆缘/前襟）只保留 `Hips`（外袍刚体挂髋等效，即
"人物与衣服分开生成"思路的零成本实现）；露腿区保留腿链；袖子跟手臂；空权重回填首骨。

## 踩坑清单（全部实测）

- **Mixamo FBX 是 cm**：导入后骨架 scale 0.01。只把 armature ×100 并 apply；
  网格局部数据已是米，一起 ×100 会变 172m。
- **bisect 三律**：切前 `select_all`、切后 `separate(LOOSE)`（bisect 不分离）、
  只切包围盒跨越切面的碎片（否则碎片 2^N 爆炸超时）。
- **join 按去偶基名分组**：Blender 重名自动 `.001`，按原名分组每组只剩 1 个。
- **踝切线低于靴筒顶**：切不开 → Foot 分件缺失 → 宿主表现层断言失败。
- **Edge 下载崩 context**：S3 跨域附件导航杀死浏览器 → 拦截预签名 URL + urllib 下载，
  且每个动画独立浏览器会话（一次下载后 context 已死）。
- **动画变体选错**：search 结果有 Fight Idle 等变体 → 按精确名/前缀匹配 + 黑名单
  （fight/sword/gun）过滤。
- **inplace 复选框延迟出现**：select 后轮询最长 20s 再 set。
- **导出参数**：Blender 5.2 glTF 无 `export_animation` 布尔，用 `export_animation_mode="ACTIONS"`。

## 验证

- 绑骨：`status` → `character` 变为目标名、`animation: none (T-pose)`。
- 资产：Godot `--headless` 探针——AnimationPlayer 存在、clips 齐、play("walk") 后
  `current_animation_position` 前进。
- 台账：job_id、三角形/骨骼/动作/字节/sha256 入 `docs/art/**/asset_ledger.md`。
