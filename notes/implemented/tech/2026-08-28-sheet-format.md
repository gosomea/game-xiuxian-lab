# Note: Sheet 文件格式选型（.tscn vs .tres）

Status: implemented

## 问题

Sheet（一组 Capability + Component 的挂载包）是丹药、阵法、境界表单等「临时能力包」的统一机制（见 [capabilities-architecture](../tech/2026-08-28-capabilities-architecture.md)）。Godot 提供两种原生序列化格式，选错会影响装配体验与数据权重。

## 决策

Sheet 采用 **`.tscn`（PackedScene）**，按文件名后缀 `_sheet.tscn` 识别，与其所属功能同处一包（见 [src-feature-packaging](2026-08-28-src-feature-packaging.md)）。

- Sheet 本质是「一棵子节点树」（Component 节点 + CapabilityManager + Capability 节点），`.tscn` 是它的原生形态；`.tres` 装节点树需要额外包一层自定义 Resource，语义绕。
- 编辑器内可视化装配：Sheet 文件双击打开即见层级与属性，策划与 Agent 都能检查内容。
- 挂载路径：`load()` 得 PackedScene → `instantiate()` → `add_child()`；卸载 `queue_free()`，并由 `TagRegistry.remove_all_from` 兜底清理该 Sheet 发起的阻塞。
- 嵌套天然支持（父 Sheet 实例化子 Sheet 场景）。

纯数据型修饰（只有数值变化、无行为节点）不建 Sheet，直接用 Component 数值字段表达；这是格式选型的边界，不是例外。

`SheetLoader` 同时提供「从已有节点树包装」的路径，供运行时动态拼装的 Sheet 使用（无文件形态）。

## 备选方案

- **`.tres`（自定义 Resource）**：输在语义不匹配。Resource 是数据，Sheet 是「数据 + 行为节点的装配」；用 Resource 装行为意味着把 Capability 退化为数据表加一个通用解释器，等于在模式内部再造一个模式。纯数值修饰场景已由 Component 数值字段覆盖，不构成采用 `.tres` 的理由。
- **JSON 自定义格式**：输在需自写解析装配器且失去编辑器可视化。词汇表用 JSON 是因为它是跨运行时契约（Python 门禁与 GDScript 双向消费），Sheet 是 Godot 内部装配，两者诉求不同。

## 后果

- 代价：`.tscn` 比 `.tres` 重；多人同时改同一 Sheet 时合并冲突可读性一般，缓解方式是保持 Sheet 粒度小（一人一 Sheet）。
- 收益：装配可视化、嵌套零成本、挂载/卸载路径与 Godot 生命周期一致。
- 验证：`verify_sheets.py` 检查引用存在与嵌套无环，并有负向控制用例（循环引用、悬空引用被拒）。
