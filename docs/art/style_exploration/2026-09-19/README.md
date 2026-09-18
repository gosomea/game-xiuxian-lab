# 风格探索候选 · 2026-09-19

**状态：全部为未选定候选。** 本目录只保存用于讨论「修仙题材视觉基调」的五张参考图，
不代表任何已采纳的方向，也不构成任何运行时资产或生成器输入。

- **每张都是同一比较框架的三联画**，左 / 中 / 右分别对应：**人物** · **庭院** · **御剑远景**。
- 五张图仅风格不同，比较对象一致，便于并列对照。
- 生成日期：**2026-09-19**。由 **OpenAI image generation** 生成；**无第三方素材**、无素材库下载、无外部许可依赖。
- 本轮**只新增本目录的 6 个文件**（5 张 PNG + 本 README）；未改动任何已有资产、未新增运行时代码、未触碰 `src/`。

> ⚠️ **这些图只是视觉目标参考。** 它们是概念插画，**不是可直接运行的资产**：
> 不能导入 Godot、没有网格/材质/贴图/骨骼/动画数据，也不满足本仓既有的轴向、共面与碰撞契约。
> **不得据此声称「风格已定」**；选择与落地都必须另出决策与新版资产。
> 现有运行时资产（`mountain_realm.glb`、`mountain_realm_courtyards.glb`、`cultivator.glb`、`flying_sword.glb` 等）
> 一律保留、未被本目录替换或覆盖。

## 候选清单

| 文件 | 中文名称 | 核心差异（相对其它候选） |
|---|---|---|
| `style-a-jade-paper-animation.png` | **玉青纸白动画风** | 明亮高饱和的青玉瓦 + 朱红/暖金点缀，云海日照充足；人物为动画式厚涂，衣褶与发丝简化；整体最"通亮"，暗部极少 |
| `style-b-refined-low-poly.png` | **精修低多边形** | 世界保持**可见的低多边形块面**（树冠、山体、石作都是明显多面体），人物却是写实向细化；即"低模场景 + 高质人物"的混合 |
| `style-c-anime-cel-shaded.png` | **日式赛璐璐上色** | 平涂色块 + 干净描边，阴影边界清晰、无渐变过渡；天空为高饱和蓝，御剑拖尾等光效为纯亮青色；人物为二次元比例 |
| `style-d-ink-wash-hybrid.png` | **水墨混合** | 宣纸/纸白底 + 墨色山影，大量留白与淡彩晕染；景物边缘靠墨线而非明暗塑形；人物为水墨写实，整体青灰低饱和 |
| `style-e-stylized-semi-realistic.png` | **风格化半写实** | 写实光照与体积雾、暖金逆光与大气透视；瓦面、木构、栏杆细节最多；人物接近影视概念图的写实比例，最"重" |

## PNG 读数

全部为 `PNG`、位深 8、色彩类型 2（真彩 RGB）、**1672×941**（16:9 三联画，每格 ≈557 px 宽）。

| 文件 | 字节 | sha256 |
|---|---|---|
| `style-a-jade-paper-animation.png` | 2828996 | `dbdf674aa1b33db86ed50a558e072b6a88fc7c1e7527810ddc017bb89a169ffe` |
| `style-b-refined-low-poly.png` | 2363063 | `940335a0706f2aa1e6938930ecf512f055d7f1aa3805931e330b34c48eadb3e5` |
| `style-c-anime-cel-shaded.png` | 2825165 | `22199621f23d2db4d2dbbb750cf9064fdaf9a1b17b970fdc86d4070e16d5fcc9` |
| `style-d-ink-wash-hybrid.png` | 2975787 | `8c6567a46ee87ffe5c00ef33aa02dfb476982e2f743540cfc36bb3f5b3f1e894` |
| `style-e-stylized-semi-realistic.png` | 3021261 | `b59620d47511ed3fd4c2632b64a1032cee52912059c1328ad4edffb41ce1c6e1` |

复制后逐字节与原始生成文件相同（上面 5 个 sha256 即原始文件读数）。

## 原始生成文件路径

复制进仓时**未移动、未修改、未删除**原始文件；它们仍留在本机 Codex 生成目录：

| 候选 | 原始路径 |
|---|---|
| A | `/Users/yuqixian/.codex/generated_images/01a0b570-6424-7dc3-9d7a-6e87ee956dd1/exec-461139f3-b4a0-40ee-8fd5-3be36e3aa09a.png` |
| B | `/Users/yuqixian/.codex/generated_images/01a0b570-6424-7dc3-9d7a-6e87ee956dd1/exec-2e720449-8e16-422c-bef3-dca92e56103a.png` |
| C | `/Users/yuqixian/.codex/generated_images/01a0b570-6424-7dc3-9d7a-6e87ee956dd1/exec-3a0d9c59-91cd-4f6d-b661-3e08ba91a963.png` |
| D | `/Users/yuqixian/.codex/generated_images/01a0b570-6424-7dc3-9d7a-6e87ee956dd1/exec-9cf5d82e-2691-47e2-8062-fa588cd8893c.png` |
| E | `/Users/yuqixian/.codex/generated_images/01a0b570-6424-7dc3-9d7a-6e87ee956dd1/exec-91e7723b-0e24-447c-8878-1fe802132bd8.png` |

按根 AGENTS.md「所有项目资产必须进入 Git」，本目录的 5 张 PNG 是入仓副本；
原始目录属于本机外部缓存，**不作为唯一保存位置**，也不在清理时连带删除。

## 来源与许可

| 字段 | 值 |
|---|---|
| 生成方式 | OpenAI image generation（文生图），2026-09-19 |
| 第三方素材 | 无（无下载素材、无素材库、无既有作品的素材迁移） |
| 许可依赖 | 无第三方许可约束；本仓根目录暂无 LICENSE 文件，对外分发前的授权声明由使用者补充 |
| 本目录用途 | 只读参考与讨论，不参与 runtime、不参与 `tools/verify/` 门禁、不参与能力目录 |

## 核对命令（只读）

```sh
# 尺寸 / 字节 / sha256 复核（PNG 头部直接解析，无第三方依赖）
python3 - <<'PY'
import hashlib, struct
from pathlib import Path
for p in sorted(Path('docs/art/style_exploration/2026-09-19').glob('*.png')):
    d = p.read_bytes()
    assert d[:8] == b'\x89PNG\r\n\x1a\n' and d.rstrip().endswith(b'IEND\xaeB\x60\x82'), p
    w, h = struct.unpack('>II', d[16:24])
    print(f'{p.name} {w}x{h} {len(d)} {hashlib.sha256(d).hexdigest()}')
PY
```

## 限制与未验证项

- 图为一次性生成的概念插画，**不可复现为同一张图**；重跑生成不会得到字节相同的产物。
- 图中元素（建筑构件、服装纹样、光效、云海）**不代表任何已实现或已计划的美术规格**；不得据此反推尺寸、材质名或资产结构。
- 五张图均未做技术可行性、性能预算、可建模性或引擎兼容性评估。
- 本轮**不做审美结论**：哪一张（或哪几张的组合）值得继续，需使用者实机与并列对照后判断。

登记人：资产归档代理；日期 2026-09-19。
