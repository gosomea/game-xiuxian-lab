# 风格探索候选 · 2026-09-19

**状态：五图均未整套采纳；方向已由使用者认可，见 [青玉纸白方向 note](../../../../notes/proposed/art/2026-09-19-jade-paper-art-direction.md)。**
本目录只保存用于讨论「修仙题材视觉基调」的五张参考图，不构成任何运行时资产。

- **每张都是同一比较框架的三联画**，左 / 中 / 右分别对应：**人物** · **庭院** · **御剑远景**。
- 五张图**题材相同，但镜头、几何与细节量不受控**：它们不是同一模型、同一机位、同一光照下的严格 A/B，
  观感差异里混着构图与渲染条件的差异，不能逐像素对照，也不能当作实时性能证据。
- 生成日期：**2026-09-19**。生成来源为 **OpenAI image generation**（文生图）。
- 首次归档于 2026-09-19：当时只新增本目录的 6 个文件（5 张 PNG + 本 README），未改动任何已有资产、未新增运行时代码、未触碰 `src/`。

> ⚠️ **这些图只是视觉目标参考。** 它们是概念插画，**不是可运行的 3D 资产**：
> **PNG 本身可以正常作为图片导入 Godot**（引擎支持 PNG 导入），但图里**不含可玩/可用的 3D 网格、材质与骨骼数据**，
> 也没有动画，不满足本仓既有的轴向、共面与碰撞契约。
> 原句与逐对象规格见 [青玉纸白方向 note](../../../../notes/proposed/art/2026-09-19-jade-paper-art-direction.md)（仍是 proposed，资产与运行时均未实施）；
> 图不参与验收，**使用者视觉确认前不得宣称通过**。
> 现有运行时资产（`mountain_realm.glb`、`mountain_realm_courtyards.glb`、`cultivator.glb`、`flying_sword.glb` 等）
> 一律保留、未被本目录替换或覆盖。

## 参考边界（哪张图只取什么）

方向文字来自使用者的确认原句，是**本次风格依据**；图只提供参考，**不得把五张图的优点加总成一套做法**。
逐对象造型规格、色卡与交接方案见 [2026-09-19-jade-paper-art-direction.md](../../../../notes/proposed/art/2026-09-19-jade-paper-art-direction.md)。

| 板 | 实际是什么 | 只取什么 | 明确不取 |
|---|---|---|---|
| A | 偏**半写实与华丽细节**；不是「达成目标样张」，与「精致低模」并不一致 | 国风造型气质、配色方向 | 细节密度、半写实质感 |
| B | 建筑与角色**同样超出简单程序低模** | 形体简化与块面语言的克制感 | 把它当本轮完成度预算 |
| C | 有渐变与光效层次，**并非绝无过渡**；是整套二次元方案 | 只取**动作轮廓**的可读性 | 整套赛璐璐上色与描边体系 |
| D | **并非景物全靠墨线**，人物仍是水墨写实 | 只取**远景层次与留白意象** | 全屏纸纹、纸白覆盖画面 |
| E | 图面有大气透视观感，但**不能据此断言使用了体积雾**等技术手段 | 只取**材质差异** | 把视觉现象当技术方案、写实化美术 |

**飞行图绝大多数是俯身手持剑，不采纳。** 实际御剑表现必须是：**剑在脚下、剑体可辨、足与剑相接**；
C 的拖尾光效可作轮廓参考，但同样不构成脚下关系。

## 候选清单

| 文件 | 中文名称 | 核心差异（相对其它候选） |
|---|---|---|
| `style-a-jade-paper-animation.png` | **青玉纸白动画** | 明快通透的青玉瓦 + 暖金点缀，云海日照充足；人物为动画式厚涂，衣褶与发丝偏简化；细节量偏**半写实**，非纯低模 |
| `style-b-refined-low-poly.png` | **精修低模** | 世界保留可见的**多面体块面**（树冠、山体、石作）；人物与建筑细节量仍高于纯程序低模 |
| `style-c-anime-cel-shaded.png` | **动画上色（动作轮廓参考）** | 平涂色块 + 描边为主，同时带光效渐变与高饱和天空；**整套方案不采纳**，只参考动作轮廓 |
| `style-d-ink-wash-hybrid.png` | **水墨混合（远景参考）** | 纸色底 + 墨色山影、留白与淡彩；**只取远景层次**，不做全屏纸纹 |
| `style-e-stylized-semi-realistic.png` | **风格化半写实（材质参考）** | 暖光与大气透视、细节最多；**只取材质差异**，不据此断言任何渲染技术 |

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
| 生成来源 | 记录生成来源事实（OpenAI image generation）；**不作许可结论** |
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
- **镜头与几何不受控**：五张图不能当作同模型同机位的对照，也不能用于推导面数、贴图或性能预算。
- 图中元素（建筑构件、服装纹样、光效、云海）**不代表任何已实现或已计划的美术规格**；不得据此反推尺寸、材质名或资产结构。
- 图面观感**不能证明**任何具体渲染技术（如体积雾、描边、纸纹）已被采用为方案。
- 方向已由使用者认可、采纳边界见 [方向 note](../../../../notes/proposed/art/2026-09-19-jade-paper-art-direction.md)；这些图**不参与验收**，落地与验收由使用者另找他人执行。

登记人：资产归档代理；日期 2026-09-19（2026-09-19 按主审审计修正描述与参考边界）。
