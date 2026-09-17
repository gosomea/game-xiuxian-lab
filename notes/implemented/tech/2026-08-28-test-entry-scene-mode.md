# Note: 测试入口用主场景模式而非 -s 脚本模式

Status: implemented

## 问题

无头测试需要真实场景树：能力代码用 `get_tree().get_nodes_in_group()` 做空间查询，节点必须 `is_inside_tree()`。

初版入口为 `godot --headless -s tests/run_all.gd`（`extends SceneTree`）。实测该模式下节点无法入树——最小诊断结果：

```
root is null: false
container inside_tree: false      # root.add_child(container) 之后
child inside_tree: false
child get_tree null: true
```

`root` 对象存在但自定义 SceneTree 替换默认 MainLoop 后，root Window 的树绑定未完成，`add_child` 的整棵子树 `is_inside_tree()` 恒为 false。表现是「测试通过但能力静默失效」：不依赖场景树的断言（静态设施、子节点遍历）全绿，依赖分组查询的断言全红——比直接崩溃更危险的失败模式。

改用 `_initialize()` 替代 `_init()` 无效，问题不在时机而在自定义 MainLoop 本身。

## 决策

测试入口为**主场景模式**：`godot --headless --path . tests/test_runner.tscn`。

- `tests/test_runner.tscn` 根节点挂 `tests/test_runner.gd`（`extends Node`）。
- 在 `_ready()` 中依次执行各 suite，节点挂到 runner 自身之下，因此真实入树。
- 结束时用 `get_tree().quit(exit_code)` 传递退出码，供门禁与 CI 消费。

配套：`tests/test_context.gd` 的 `begin_case()` 在每个用例首行清场景并重置静态设施；`harness.gd` 的 `track()` 把节点挂到测试根。

## 备选方案

- **`-s` 脚本模式（`extends SceneTree`）**：输在无法提供场景树，已由上述诊断证明。该模式适合纯逻辑脚本（不触及节点），不适合需要分组查询、信号、`_process` 的运行时测试。
- **`_initialize()` 代替 `_init()` 继续用脚本模式**：输在同一根因，实测无效。
- **能力代码改为不依赖 `get_tree()`**（把候选实体列表由外部注入）：输在扭曲生产代码以适配测试工具。分组查询是 Godot 惯用法，测试基建应当支持它，而不是让运行时为测试让步。
- **引入 GUT**：输在时机与依赖。GUT 会解决入口问题，但引入外部依赖；当前测试规模（3 个 suite）不足以支付该成本，启用条件已在 [gate-tiers](../process/2026-08-28-gate-tiers.md) 记录为 Tier 2。

## 后果

- 代价：测试入口多一个 `.tscn` 文件；退出码经 `get_tree().quit()` 传递，需保证 `_ready()` 中不提前 return 导致进程挂起。
- 收益：测试与生产走同一场景树语义，分组查询、信号、节点生命周期均可测；消除「不入树导致断言假绿」这一整类失效。
- 相关更正：[static-globals-over-autoload](2026-08-28-static-globals-over-autoload.md) 中「测试改为场景模式启动」曾被记为输给复杂度的备选，其理由已由本 note 的实测证据取代；该 note 的核心决策（静态类）不受影响并继续成立。
