# 青石坊市 2D 资产台账

日期：2026-09-26。用途：`res://levels/experiments/eastern_2d/market_square.tscn` 独立实验。三张图均由内置 `image_gen` 文生图生成，原始输出复制入仓；此轮未从旧修仙项目移用素材，也未覆盖仓内已有探索资产。PNG 本身就是原始生成文件，同时作为 Godot 导入源；`.png.import` 是入仓的导入描述，`.godot/` 缓存不是资产。

| 文件 | 规格 | SHA-256 | 场景用途 |
|---|---|---|---|
| `market_square_background_v1.png` | 1586×992，RGB，2,935,584 B | `252923cd1e5e2f18cb10bf33a51fd63c97306cb188fd143880f2e9a52d0a60e9` | 坊市、石铺广场、摊铺与远山完整底图；底部栏杆区域在运行时作为同图 region 前景层复绘 |
| `market_cultivator_four_views_v1.png` | 1774×887，RGBA，1,510,809 B | `8715fd18846f3a29d3006ad525cfba10d72f99f32e4fb3e9d39b96e92bd93b71` | 主角正、背、左、右四向透明精灵；以 Sprite2D region 切换，不另存裁剪版 |
| `market_npcs_v1.png` | 1774×887，RGBA，1,588,817 B | `83cc3fab1b690ddec8439b722db294a9f07d63ecf9cfbf13d2b50601867d3be1` | 药师、玉器摊主、路过剑修三位静态角色 |

## 生成路径与提示词

生成任务：`/Users/yuqixian/.codex/generated_images/01a0de51-4401-76e1-a5ab-60fdd759f0c4/`。其中 `exec-5d793010-da51-466d-934d-247478c8e737.png` 对应背景，`exec-1eed9e31-394f-465f-96ed-75791d7d7e53.png` 对应主角，`exec-8e35bb86-35b6-4649-ae36-18ddd9e83a06.png` 对应路人。仓内副本是项目的持久来源，不依赖上述本机生成目录。

背景最终提示词：

> Paint an original compact Eastern anime style cultivation market square (修仙坊市), suitable for placing a separate player character sprite on top in Godot. Landscape 16:10 composition. A wide, clean pale stone-paved central square occupies roughly the lower-middle 55% of the image. Elegant wood-and-plaster shopfronts, tea stall, fabric awnings, jade and herb vendor counters, warm lanterns and a tiled gate surround it. Coherent 3/4 top-down oblique, almost orthographic projection. Premium hand-painted Chinese fantasy anime game art, clean dark ink contours, simplified cel-like color blocks and subtle painterly variation. Late afternoon; ivory stone, jade teal, muted pine green, ink navy, warm wood and sparing golden amber. No people, player, text, UI, logos or obstructing props in the central walking space.

主角最终提示词：

> One consistent original young male xianxia cultivator in four separate, equally spaced full-body standing sprites, horizontal order: facing down-screen, up-screen, screen-left, screen-right. Same ink-navy and teal cross-collar short robe, tied bun, ribbon, jade waist ornament and dark boots in every view. Premium hand-painted Chinese fantasy anime 2D sprite art, clean ink outlines, simplified cel shading, 3/4 top-down oblique camera elevated about 55 degrees, warm upper-left afternoon light. All feet on one baseline, generous transparent gutters, genuine alpha background. No panels, text, scenery or extra characters.

路人最终提示词：

> Three distinct, equally spaced full-body transparent NPC cutouts in one horizontal row: a middle-aged herbalist in sage-green, a woman jade trader in warm umber and cream, and a traveling swordswoman in muted slate-blue. Calm standing poses, diagonally toward foreground. Same hand-painted Eastern anime game world as the market, dark ink contours, simplified painterly cel shading, 3/4 top-down oblique camera around 55 degrees, warm upper-left light. Equal approximate height and common foot baseline, genuine transparent alpha; no text, panels, ground or scenery.

## 使用边界

背景是单张概念式场景画，不提供逐对象可编辑的建筑分层。角色四方向为独立静态绘像，行走时只做轻微起伏与倾斜，不是完整逐帧行走动画。未来若重做建筑分层或帧动画，应另存 v2 文件并保留本轮三张 PNG。
