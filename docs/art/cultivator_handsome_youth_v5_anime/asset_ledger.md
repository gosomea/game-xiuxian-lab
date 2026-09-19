# 英俊少年修士 v5（Generic Anime Male）资产台账

日期：2026-09-19

## 来源与许可

- 原作者：jonshipman；资产名：Generic Anime Male。
- Sketchfab UID：`f119e8cddf8c4bca9666a885975f9245`。
- 资产页：https://sketchfab.com/3d-models/generic-anime-male-f119e8cddf8c4bca9666a885975f9245
- 作者页：https://sketchfab.com/jonshipman
- 许可：CC-BY 4.0，https://creativecommons.org/licenses/by/4.0/
- 下载来源：作者在资产页描述中直接提供的 Google Drive 链接；下载日期 2026-09-19。
- 未改原件：`source/generic_anime_male_original.blend`；SHA-256 `a58cb67a0451b9198692e75385259dd8c72c914ea4c49e44e205ce34d986cc2a`。
- 官方 v3 API 核验值：15,020 tris、7,811 verts、4 materials、4 textures、可下载；描述为 `Base anime male with Mixamo bones`。

## 本轮改造

连续 body 直接作为无裂缝的月白内衫和深蓝裤靴；独立青蓝短外衫由左右 V 形前开片、背片与完整短袖构成，具有肩线、袖窿和收腰，长度止于自然腰下。左右交领分别建模，右片以额外 3 mm 外偏明确压住左片。腰下仅保留前左、前右、后左、后右四片短摆，根部接入外衫/腰封、正中和侧面留动作开口。所有旧腕环、肩环和单根斜蓝带均已删除。

头发由贴头皮壳、束发根、两束不遮眼前发和五束从同一束发点扇出的弧形后发组成。五束目前仍绑定 Head，但保留独立曲面和拓扑；下一真实动作阶段增加 2–3 段辅助发骨链，当前 manifest 明确记录未完成。

## 工程状态

源文件有 168 骨（含 Mixamo 变形骨与作者控制骨），所有四个角色子网格均有 Armature modifier 和权重；打包图像块数量见 manifest。Blender 正面经眼、鼻、胸与脚尖核验为 `-Y`；GLB 导出用独立 180° 根适配到 Godot `-Z`。

iteration 01、surface-shell debug、iteration 02 与 Reviewer 55/100 的 iteration 03 均完整保留；当前主输出为 iteration 04 返工稿。除 T pose 彩色/灰模四视图外，已输出自然垂臂 idle 正面/三分之四/背面、2.5D size18/size6 与 only-added-clothing 灰模。未上传 Mixamo、未跑真实 walk/run/jump，也未通过复审；技术审计不得冒充审美通过。
