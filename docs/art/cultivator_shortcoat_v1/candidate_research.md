# 移动友好国风角色候选调研（2026-09-19）

## 结论

本轮没有找到一个能同时满足“青玉纸白风格、基础移动结构安全、可合法完整入 Git、无需大改”的现成角色。最合适的工程路线不是再赌一个长袍成品，而是：

1. 当前先用本目录的原创短装 T-pose 验证自动绑骨与动作变形；
2. 若自动绑骨质量不足，改用 Quaternius CC0 通用人形作为成熟拓扑/骨架底座，再在 Blender 重做同一套短装外观；
3. 视觉接近但授权或服装结构不合适的网上模型，只保留为参考，不下载入库。

## 筛选条件

硬门槛：6.5–7 头身、标准人形/T-pose、手肘膝踝清晰、双腿有负空间、无长袍/披风/过腕大袖、可在 Git 中保存全部源资产与派生资产、可用于商业项目。软门槛：交领/腰封/发髻、靛青月白暖金、水墨或手绘低模材质。

## 候选比较

| 候选 | 优点 | 淘汰/保留原因 | 结论 |
|---|---|---|---|
| Quaternius Universal Base Characters | 官方 CC0；约 13k tris；动画友好拓扑；Humanoid rig；FBX/glTF；商业可用 | 免费标准版是通用西式人体，不能直接满足国风外观；完整整包约 122 MB | **技术底座备选**，自产白样绑骨失败时优先用 |
| 3D Hanfu Hero | 中国/汉服语汇，32.8k tris，页面称含 walk/run/idle 与 PBR | 付费 Fab 商店资产；长汉服仍遮挡胯腿；未确认把源资产完整提交到公开/共享 Git 的再分发边界 | 仅视觉参考 |
| Chinese Empress Low-Poly Watercolour Character | 手绘水彩低模，约 10k tris，最接近“水墨意象” | 女性长裙轮廓，不适合作为基础移动男修；页面未给出本轮可采用的开放授权证据 | 仅材质参考 |
| Low Poly Rigged Samurai Character + Sword | 4.2k tris、已绑骨 | CC BY-NC；日式武士；非商业限制不合项目长期使用 | 淘汰 |
| OpenGameArt Stylized Low Poly Character | CC-BY 4.0、T-pose、Mixamo rig、可改造 | 通用西式底模，外观重做量与自己建短装相近 | 第二底模备选 |
| Sketchfab Low Poly Male / Male Base 等 | 若干 CC-BY、已绑骨或可绑骨、面数低 | 角色质量与权重不可统一保证；仍需完整重做国风外层，并增加署名/来源管理 | 不优先 |
| KayKit Rogue_Hooded（上一轮） | CC0、原生骨架与动作完整，管线已跑通 | 披肩/袍片/袖形在移动中不成立，西幻轮廓离原方向远 | 保留作管线对照，不再作为玩家角色 |

## 参考链接

- Quaternius Universal Base Characters（官方，CC0）：<https://quaternius.com/packs/universalbasecharacters.html>
- Quaternius 免费下载页：<https://quaternius.itch.io/universal-base-characters/purchase>
- Quaternius Universal Animation Library（CC0）：<https://quaternius.itch.io/universal-animation-library>
- 3D Hanfu Hero：<https://sketchfab.com/3d-models/3d-hanfu-hero-8fa0155c8dd042a28bf84119a0ce9712>
- 3D Hanfu Hero / Fab：<https://www.fab.com/listings/57c88b81-d682-43e9-b23b-8726658803da>
- Chinese Empress：<https://sketchfab.com/3d-models/chinese-empress-low-poly-watercolour-character-34a6ea421fcf4328a6580ad735e93ccb>
- Low Poly Rigged Samurai：<https://sketchfab.com/3d-models/low-poly-rigged-samurai-character-sword-fc6edbae7cc04d53ade72d2237774edd>
- OpenGameArt Stylized Low Poly Character：<https://opengameart.org/content/stylized-low-poly-character>
- Sketchfab Low Poly Male：<https://sketchfab.com/3d-models/low-poly-male-7d601a034c1c45e68151bddf386e48b3>

所有链接均在 2026-09-19 查阅；本轮没有从这些页面下载任何第三方模型。

