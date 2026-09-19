# Note: 移动角色改用青玉短打修士，不再以袍服角色承载基础移动

Status: proposed

## 问题

当前长袍、大袖与披风角色在基础走、跑、跳时会遮挡或横跨髋、膝、腕等主要变形区。即使自动绑骨和动作导入成功，服装轮廓仍会产生刚体摆动、穿插、左右肢体观感混乱等结构性问题。继续用这类角色调动作，会把“模型不适合移动”和“动作质量不足”混成一个问题。

网上视觉接近的国风低模角色也没有同时满足三项条件：移动结构安全、许可允许把全部源资产提交 Git、无需大改即可接入。项目需要一个低成本、可独立绑骨的短装白样，先回答服装结构是否成立，再决定最终模型生产方式。

## 提案

基础走、跑、跳、御剑不再继续使用大袖袍、长袍片或胸前硬挂披风的角色。新候选延续
[青玉纸白美术方向](2026-09-19-jade-paper-art-direction.md)，但把服装语汇改成适合移动的“短打修士”：

- 约 6.7 头身，动画化低模比例，不走写实写生；
- 靛青主衣、月白交领与内衬、少量淡金腰封，材质温润、低金属、低噪声；
- 合体窄袖，手腕与双手完整露出，不做垂过手腕的袖袍；
- 上衣止于胯部，下摆只保留左右分开的短分片，不超过大腿中段；
- 双腿之间保留明确负空间，膝、踝和脚尖轮廓无遮挡；
- 无披风、无整圈长裙、无焊死到胸口的布片；发髻只承担修仙身份识别，不遮脸；
- 第一阶段先保存静态 T-pose、Blender 源文件、可上传绑骨的单网格 FBX 和预览；不在动作验证前替换现有运行时视觉。

2026-09-19 已按本提案先构建静态白样，产物和读数见[资产台账](../../../docs/art/cultivator_shortcoat_v1/asset_ledger.md)。状态仍为 proposed：静态资产存在不代表动作方案已经通过。

## 备选方案

### 直接使用视觉接近的网上国风成品

`3D Hanfu Hero`、`Chinese Empress Low-Poly Watercolour Character` 等候选在汉服或水彩气质上更接近方向，但服装仍以长汉服、裙摆为主；部分还是付费商店资产，无法在未单独确认再分发边界时满足“所有项目资产必须进入 Git”。因此只作视觉参考，未下载。

### 使用开放授权的通用底模

Quaternius `Universal Base Characters` 是最干净的现成技术底座：官方明确为 CC0、约 13k 三角面、动画友好拓扑、Humanoid rig、提供 glTF/FBX。但免费标准包仍是通用西式人形，本轮不把 122 MB 整包塞入仓库。若自产白样自动绑骨失败，它是下一轮首选底座。

OpenGameArt 与 Sketchfab 也有 CC-BY 通用人形，但需要重做绝大多数外观，直接引入没有显著缩短本轮工作，还会增加署名与来源管理。

### 继续修 KayKit Rogue_Hooded 或现有长袍模型

KayKit 管线已证明原生动作和 Mixamo 路线都可走通，但西幻轮廓、披肩/袍片和袖形不适合作为最终玩家角色。现有自产长袍模型也有网格岛、权重和裙摆结构问题。两者均按探索资产保留规则留存作管线对照，不再作为本轮主线。

## 验收标准

静态阶段：

- 正面可同时读出发髻、交领、腰封、分离短下摆和左右腿负空间；
- T-pose 双手、肘、膝、踝位置可见，自动绑骨 marker 不被衣物遮挡；
- 人体高度约 1.70 m，头身比 6.5–7.0；鞋底落在 z=0；
- Blender 源文件与 GLB/FBX 派生物另存到新目录，并记录 sha256；
- 不接入 `jade_paper_sample`，不改变当前 8 个移动实验的引用。

动作阶段另开后续轮次，至少以 walk/run/jump 实机验证腋下、胯部、膝部、袖口与短下摆；通过后才讨论替换样板场景。

## 风险

- 程序白样是分件后合并的单网格，拓扑连续性不等于最终生产模型；自动权重可能仍在肩、胯和短摆处分配错误。
- 六片短摆即使不横跨双腿，也需要明确权重归属；若全挂 Hips，跑动时仍可能显得僵硬。
- 目前只有静态预览，不能据此声称动作质量通过，也不能据此替换运行时玩家视觉。
- Quaternius 等第三方底座若后续真正入库，仍须重新固定下载版本、保存许可原文、做资产台账和独立提交。

参考来源（2026-09-19 查阅，均未下载）：

- Quaternius Universal Base Characters：<https://quaternius.com/packs/universalbasecharacters.html>
- Sketchfab Chinese Empress：<https://sketchfab.com/3d-models/chinese-empress-low-poly-watercolour-character-34a6ea421fcf4328a6580ad735e93ccb>
- Sketchfab 3D Hanfu Hero / Fab：<https://www.fab.com/listings/57c88b81-d682-43e9-b23b-8726658803da>
- OpenGameArt Stylized Low Poly Character：<https://opengameart.org/content/stylized-low-poly-character>

