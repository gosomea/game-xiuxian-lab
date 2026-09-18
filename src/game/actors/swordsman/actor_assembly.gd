class_name ActorAssembly
extends Node

## 角色装配节点（S0，装配 root）：按显式 ActorAssemblyConfig 在同一 actor 下装配
## Move / Jump / Flight 的子集；flight 由 FlightBundle 行为+视觉一起装。
##
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md：
## - 能力注册为宿主 CapabilityManager 的直系子，复用宿主唯一 SwordsmanMotionComponent；
##   本节点不新建 manager、不复制 Component；
## - owner 原则：只用本实例持有的句柄记录所有权，不写宿主 meta、不扫描同名节点认领；
##   外部已存在的同名能力/视觉一律拒绝，既不覆盖也不删除；
## - 借用原则：卸载只清本实例创建的行为与表现，不碰其它能力的输入与速度，**不调用 reset_motion()**；
## - 安装原子性：先把全部依赖与冲突预检完，再提交；提交中失败只回滚本次新增；
## - 安装配置不可变：重复安装同配置幂等成功；请求不同配置显式报错，要求先 uninstall
##   （S0 不做原地重构事务，避免半提交状态）；
## - 配置非法或资源失败时返回错误、原样上报，不静默吞掉。
##
## 代表调用链（headless 可用）：
##   var assembly := ActorAssembly.new()
##   actor.add_child(assembly)
##   var config := ActorAssemblyConfig.new()
##   var error := assembly.install(config)   # "" 表示成功
##   ...
##   error = assembly.uninstall()

## 场景装配配置：由 swordsman.tscn 提供默认值，Swordsman._ready() 调用 install_configured()。
## 不在本节点的 _ready() 里自动安装——子节点 _ready 早于父节点 @onready 赋值，
## 那时 actor 的组件引用尚未就绪，装不了能力（实测：子 _ready 中父 @onready 变量仍为 null）。
@export var config: ActorAssemblyConfig = null

## 本实例创建的能力节点（move/jump），卸载时逐个移除。
var _owned: Array[Node] = []
## 本实例创建的御剑装配包；未安装为 null。
var _flight_bundle: FlightBundle = null
## 已安装配置的**副本**；null 表示当前未安装。副本保证外部修改原 Resource 不会静默改变装配。
var _installed: ActorAssemblyConfig = null
## 安装时的宿主句柄。用于本节点被移出树后仍能清理（此时 get_parent() 可能已不可靠）。
var _host_cache: Swordsman = null

## 装配可纳入配置的三项行为脚本。
const MOVE_SCRIPT := preload("res://game/actors/swordsman/swordsman_movement.gd")
const JUMP_SCRIPT := preload("res://game/abilities/jump/jump.gd")

const MOVE_NAME := "SwordsmanMovement"
const JUMP_NAME := "Jump"


## 按场景提供的 config 安装（Swordsman._ready() 调用）。返回错误信息，"" 表示成功。
func install_configured() -> String:
	if config == null:
		return "ActorAssembly.install_configured: 未设置 config"
	return install(config)


## 安装配置描述的子集。返回错误信息，"" 表示成功。
## 幂等：与当前安装配置匹配时直接返回 ""；不同配置要求先 uninstall。
func install(requested: ActorAssemblyConfig) -> String:
	var host := _host_node()
	if host == null:
		return "ActorAssembly.install: 直系父节点不是 Swordsman"
	if requested == null:
		return "ActorAssembly.install: config 为空"
	var invalid := requested.validate()
	if invalid != "":
		return "ActorAssembly.install: 配置非法（%s）" % invalid
	if _installed != null:
		if _installed.matches(requested):
			return ""
		return "ActorAssembly.install: 已按其它配置安装；请先 uninstall 再 install"
	# 预检：全部依赖与冲突确认后才提交，安装失败不会留下半装配。
	var manager := _manager()
	if manager == null:
		return "ActorAssembly.install: 宿主缺少直系 CapabilityManager"
	if requested.move_enabled:
		var move_conflict := _conflict(manager, MOVE_NAME)
		if move_conflict != "":
			return move_conflict
	if requested.jump_enabled:
		var jump_conflict := _conflict(manager, JUMP_NAME)
		if jump_conflict != "":
			return jump_conflict
	if requested.flight_enabled:
		var flight_conflict := FlightBundle.preflight(host, requested.flight_visual)
		if flight_conflict != "":
			return flight_conflict
	# 提交：逐步创建；任一步失败只回滚本次新增。
	var error := _commit(manager, requested)
	if error != "":
		_rollback()
		return error
	_host_cache = host
	_installed = requested.duplicate() as ActorAssemblyConfig
	return ""


## 卸载本实例安装的全部行为与表现。返回错误信息，"" 表示成功。
## 不触碰组件字段、其它能力的输入与宿主速度；不调用 reset_motion()。
func uninstall() -> String:
	if _host_node() == null:
		return "ActorAssembly.uninstall: 直系父节点不是 Swordsman"
	if _flight_bundle != null:
		_flight_bundle.uninstall()
		_flight_bundle = null
	_prune_owned()
	for node in _owned.duplicate():
		_remove_node(node)
	_owned.clear()
	_installed = null
	return ""


## 节点被移出场景树时清理本装配：装配根被删（host 仍存活）不得留下孤儿能力/视觉。
## 依赖缓存的宿主句柄而非 get_parent()；uninstall() 自身幂等，因此显式卸载后这里自动为 no-op。
func _exit_tree() -> void:
	_prune_owned()
	if _installed != null or _flight_bundle != null or not _owned.is_empty():
		uninstall()


## 当前是否已按某配置安装完成。
func is_installed() -> bool:
	return _installed != null


## 当前生效配置的**副本**；未安装返回 null。调用方修改返回值不会影响装配状态。
func installed_config() -> ActorAssemblyConfig:
	if _installed == null:
		return null
	return _installed.duplicate() as ActorAssemblyConfig


## 当前装配的能力类名（读宿主管理器直系子），供验收脚本断言。
func capability_names() -> PackedStringArray:
	var manager := _manager()
	var names := PackedStringArray()
	if manager == null:
		return names
	for child in manager.get_children():
		if child is Capability:
			var script: Script = child.get_script()
			names.append(str(script.get_global_name()) if script != null else str(child.name))
	return names


func _commit(manager: CapabilityManager, config: ActorAssemblyConfig) -> String:
	if config.move_enabled:
		var move_error := _add_owned(manager, MOVE_NAME, MOVE_SCRIPT)
		if move_error != "":
			return move_error
	if config.jump_enabled:
		var jump_error := _add_owned(manager, JUMP_NAME, JUMP_SCRIPT)
		if jump_error != "":
			return jump_error
	if config.flight_enabled:
		var host := _host_node()
		var bundle := FlightBundle.new()
		var flight_error := bundle.install(host, config.flight_visual)
		if flight_error != "":
			return flight_error
		_flight_bundle = bundle
	return ""


## 如果管理器下已经有同名能力，返回拒绝信息；否则 ""。
func _conflict(manager: CapabilityManager, capability_class: String) -> String:
	for child in manager.get_children():
		if child is Capability:
			var child_script: Script = child.get_script()
			if child_script != null and child_script.get_global_name() == capability_class:
				return "ActorAssembly.install: 宿主已存在 %s，拒绝重复装配或认领" % capability_class
	return ""


func _add_owned(manager: CapabilityManager, capability_class: String, script: Script) -> String:
	var capability: Capability = script.new() as Capability
	if capability == null:
		return "ActorAssembly.install: %s 脚本无法实例化为 Capability" % capability_class
	capability.name = capability_class
	manager.add_child(capability)
	_owned.append(capability)
	return ""


## 只回滚本实例本次新增的节点；不删除安装前已存在的任何节点。
func _rollback() -> void:
	_prune_owned()
	for node in _owned.duplicate():
		_remove_node(node)
	_owned.clear()
	if _flight_bundle != null:
		_flight_bundle.uninstall()
		_flight_bundle = null
	_installed = null


## 丢弃已被外部释放的 owned 句柄（例如集成场景自行 remove_child + queue_free 本装配拥有的能力）。
##
## 必须在调用 _remove_node(node: Node) **之前**做：typed 参数的运行时类型校验发生在函数体之前，
## 函数内的 is_instance_valid 拦不住「previously freed」——实测报
## "Invalid type in function '_remove_node' ... argument 1 (previously freed)"。
## 只丢弃本实例登记过的句柄，不扫描节点树、不认领外部节点。
func _prune_owned() -> void:
	var alive: Array[Node] = []
	for node in _owned:
		if is_instance_valid(node):
			alive.append(node)
	_owned = alive


func _remove_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


## 宿主解析：优先当前直系父；节点已离树时回退到安装时缓存的句柄（均须 still valid）。
func _host_node() -> Swordsman:
	var parent_host := get_parent() as Swordsman
	if parent_host != null and is_instance_valid(parent_host):
		return parent_host
	if _host_cache != null and is_instance_valid(_host_cache):
		return _host_cache
	return null


func _manager() -> CapabilityManager:
	var host := _host_node()
	if host == null:
		return null
	var manager := host.get_node_or_null("CapabilityManager") as CapabilityManager
	if manager == null or manager.get_parent() != host:
		return null
	return manager
