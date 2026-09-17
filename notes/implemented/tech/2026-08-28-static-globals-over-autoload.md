# Note: 全局设施用静态类而非 autoload

Status: implemented

## 问题

TagRegistry（Tag 阻塞登记）与 TimeKeeper（时停请求登记）是跨实体的全局设施。初版实现为 Godot autoload 单例，随后在实现无头测试入口时发现：以 SceneTree 脚本模式（`-s`）启动时**不创建 autoload 节点**，测试脚本编译期即报 `Identifier not found: TagRegistry`。

这不是测试写法问题，而是设施可达性问题：任何不经过完整场景启动的消费者（无头脚本、门禁辅助脚本、未来的批处理工具）都拿不到 autoload。

## 决策

TagRegistry 与 TimeKeeper 实现为**静态类**：`class_name X extends RefCounted`，状态存 `static var`，接口为 `static func`。调用形式（`TagRegistry.add_block(...)`）保持不变，因此已落地的能力代码与 notes 描述无需改写。

`project.godot` 不再声明这两个 autoload。

配套约束：

- 静态状态在整个进程生命周期内存活，测试之间必须显式重置——`TagRegistry.clear_all()` / `TimeKeeper.clear_all()` 由测试上下文的 cleanup 统一调用。
- TimeKeeper 仍是 `Engine.time_scale` 的唯一写入者，禁止其他代码直接改（约束未变）。

## 备选方案

- **保留 autoload，测试改为场景模式启动**：不构成对静态类的替代。测试入口最终确实改为场景模式（见 [test-entry-scene-mode](2026-08-28-test-entry-scene-mode.md)），但那解决的是「节点入树」问题；静态类解决的是「非场景入口也能访问全局设施」，两者独立成立。即使在场景模式下，静态类仍让门禁辅助脚本与批处理工具免于依赖 autoload 生命周期。
- **保留 autoload，测试中手动实例化并注入 SceneTree root**：输在测试与生产路径分叉。手动注入的单例与真实 autoload 的生命周期不同，测试通过不代表生产可用——违反「测试要走 shipped 入口路径」。
- **把阻塞状态存在各实体的 Component 上，取消全局登记表**：输在 instigator 语义。阻塞是「谁阻塞了谁」的二元关系，跨实体查询（某 instigator 退场时清理其全部阻塞）需要全局索引；分散存储会让退场清账退化为全场扫描。

## 后果

- 代价：静态状态不随场景切换自动清零，切场景时需显式 `clear_all()`（写入 src/AGENTS.md 编写纪律）；静态类无法用 Godot 的 autoload 检视面板观察。
- 收益：任何入口（无头脚本、场景运行、编辑器工具）都能使用这两个设施，测试与生产走同一份代码路径；消除「设施在某些启动模式下静默缺席」这一整类失效。
- 验证：`tests/test_core.gd` 覆盖 instigator 隔离、退场清账、时停叠加，通过无头脚本入口执行。
