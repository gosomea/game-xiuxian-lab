# ActorAssembly / FlightBundle / swordsman 只读交叉审计（2026-09-18）

范围：只读审计，未修改任何被审文件、未 commit。审的是 actor 装配侧的契约符合性（非本包作者）。
已排除重复项：惰性 `_resolve_nodes`（已撤销）、immutable config 旧方案、外来 cap 认领（均已在实现中处理）。

## 结论

**实锤 0 项**（阻塞级 0）。四项重点（四能力子集、生命周期所有权、失败事务性、唯一 manager/component/物理提交）均满足已批准契约；Resource 别名处理正确；飞剑 visual 的父子与几何契约一致。

## 已核实（只读证据）

| 检查点 | 证据 |
|---|---|
| 四个真实子集 | `test_actor_assembly.gd` 的 `run()` 覆盖 Move / Move+Jump / Move+Flight / all，含真实物理行为断言（`_test_behavior_move_only` / `_test_behavior_move_jump` / `_test_behavior_move_flight` / `_test_behavior_all`：真实移动、空格不跳、F 不飞） |
| 能力只装到直系 manager | `actor_assembly.gd` 的 `_add_owned()`（`manager.add_child`）与 `flight_bundle.gd` 的 `install()`；预检 `flight_bundle.gd` 的 `_manager_of()` 要求 `child.get_parent() == host` |
| 唯一 manager / 唯一 motion 组件 | `flight_bundle.gd` 的 `preflight()` 用 `_count_managers()` 拒绝多 manager；`_find_motion()` 对组件做唯一性查找（找到多个即返回 null，预检因此拒绝） |
| 唯一物理提交 | `swordsman.gd` 的 `_physics_process()` 中一次 `move_and_slide()`；装配侧不写 velocity、不 tick 物理 |
| 失败事务性 | `actor_assembly.gd` 的 `install()` 先全量预检再 `_commit()`，失败调 `_rollback()` 只回滚本次新增；`flight_bundle.gd` 的 `install()` 在视觉实例化失败时 `uninstall()`；测试 `test_flight_bundle.gd` 断言「拒绝补视觉后原能力保留且无 tag 残留」 |
| 所有权 / 借用 | `actor_assembly.gd` 的 `uninstall()` / `_remove_node()` 与 `flight_bundle.gd` 的 `uninstall()` 只移除本实例句柄；`test_flight_bundle.gd` 断言卸载不碰借用组件的输入/速度；测试套件另有「卸载不调用 `reset_motion()`」 |
| 离树兜底 | `actor_assembly.gd` 的 `_exit_tree()` 经 `_host_node()` 缓存句柄清理；`sword_flight.gd` 的 `_exit_tree()` 负责 tag 清账（不依赖 `sheet_loader.detach`） |
| Resource 别名 | `actor_assembly.gd` 的 `install()` 安装时 `duplicate()` 快照、`installed_config()` 返回副本；`test_actor_assembly.gd` 有 `_test_config_snapshot_is_isolated`；场景未就地改共享 Resource（无外部 mutation 命中） |
| 飞剑 visual 契约 | `flight_bundle.gd` 的 `install()` 实例化后挂到 `host/Visual`、名字 `FlyingSword`、经 `bind_flight_visual()` 由 actor 统一显隐（`swordsman.gd` 的 `_physics_process()` 与 `bind_flight_visual()`）；`swordsman.tscn` 的 `Visual` 实例共享 `cultivator_visual.tscn`；motion_stage 预览读同一 GLB（`motion_preview_display.gd` 的 `_bind_sword()`），不复制资源 |
| 共享视觉一致性 | 迁移中的场景已删除手动绑剑并由 FlightBundle 单点装配；本轮实测删除的具体路径：`src/levels/experiments/character_movement/mountain_realm.gd`、`src/levels/experiments/character_movement/state_transition_lab.gd`（两者的旧 `_bind_flight_visual()` 与 `FLYING_SWORD_SCENE` 常量已移除）；`sword_flight_course.gd` 在本次工作区中同样已不再手动实例化御剑视觉。其余场景是否仍手工绑剑本轮未逐一核对，不作断言 |

## 未验证 / 非阻塞

- **`test_actor_assembly.gd` 与 `test_flight_bundle.gd` 未注册进任何 SUITES**：`src/tests/test_runner.gd` 的 SUITES 与 `camera_rig` 包 runner 均不含它们。
  - **我本轮的运行证据不完整、不作为通过结论**：我搭的临时 runner 调用 `suite.run(context)` 时**没有 `await`**，`test_actor_assembly.gd` 的 `run()` 是含 `await` 的协程，因此只执行到同步头部就返回，得到的 `ActorAssembly 26/0` 只是头部用例，**不代表完整套件通过**（`test_flight_bundle.gd` 无 `await`，其 83/0 不受此影响）。
  - **完整结果以作者场景模式的 await 验证为准**：`ActorAssembly 126 + FlightBundle 83 = 209`（场景模式 runner 中 await 整个 `run()`）。该完整运行由作者完成，我未复现。
  - 阻塞级别：非阻塞，**完整运行待主 runner 整合**（把两者加入一个会 `await suite.run()` 的场景模式 runner）；我不再重复运行。
- 飞剑的**屏幕可见尺寸与朝向**未做逐场景截图核对（本轮为只读代码审计）；`motion_preview_display.gd` 的剑可见性由作者在修，未介入。
- 未在群山 / 御剑航线实机验证高空 `focus_clamp_y_enabled` 迁移（属相机包迁移项，已在该包报告）。