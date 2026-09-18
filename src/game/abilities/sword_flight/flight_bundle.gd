class_name FlightBundle
extends RefCounted

## 御剑飞行装配包（S0）：行为（SwordFlight）+ 视觉（flying_sword.glb）作为一个包同时安装/卸载。
##
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md：
## - 能力注册为宿主 CapabilityManager 的直系子，复用宿主唯一 SwordsmanMotionComponent；
## - owner 原则：所有权只用**本实例持有的句柄**记录，不写宿主 meta、不扫描同名节点认领；
##   外部（场景或其它装配者）已放置的 SwordFlight / FlyingSword 一律拒绝，不覆盖、不改名；
## - 借用原则：卸载只移除本实例创建的节点，不碰宿主组件、输入与速度，**不调用 reset_motion()**；
## - 安装配置不可变：一个实例只安装一次；重复安装同配置幂等返回成功，请求不同配置显式报错，
##   由调用方先 uninstall 再 install（不做原地重构事务）；
## - 本次新增失败即回滚本次新增，不删除调用前已存在的任何节点；
## - tag 与 flight_active 由 SwordFlight 自身 _exit_tree 兜底清账
##   （src/core/sheet_loader.gd:29-36 不调用 _on_deactivated，故不能依赖 detach）。

## 御剑视觉资产：装配包自带 visual，与服务同包。
const FLYING_SWORD_SCENE: PackedScene = preload("res://game/abilities/sword_flight/models/flying_sword.glb")
## 宿主 Visual 下的剑节点名（既有场景/测试读取的公开契约）。
const VISUAL_NAME := "FlyingSword"
## 御剑能力节点名（与能力类名一致；管理器按直系子轮询）。
const CAPABILITY_NAME := "SwordFlight"
## 宿主 Visual 节点名。
const VISUAL_ROOT := "Visual"

## 宿主；未安装时为 null。
var _host: Swordsman = null
## 本实例创建的御剑能力节点。
var _capability: Capability = null
## 本实例创建的御剑视觉节点。
var _visual: Node3D = null
## 本实例是否已安装，以及安装时请求的表现配置。
var _installed := false
var _with_visual := false


## 只读预检：返回安装会被拒绝的原因；"" 表示可以安装。不修改任何节点或绑定。
## 供 ActorAssembly 在提交前做整体预检，避免「装了一半才发现冲突」。
static func preflight(host: Swordsman, with_visual: bool) -> String:
	if host == null or not is_instance_valid(host):
		return "FlightBundle.preflight: host 为空或已释放"
	var manager := _manager_of(host)
	if manager == null:
		return "FlightBundle.preflight: 宿主缺少直系 CapabilityManager（装配契约要求直系唯一管理器）"
	# 宿主必须恰好一个 motion 组件；缺组件时能力虽不报错但静默无行为，违反契约。
	if _find_motion(host) == null:
		return "FlightBundle.preflight: 宿主缺少 SwordsmanMotionComponent（能力无共享数据可读写）"
	if _count_managers(host) > 1:
		return "FlightBundle.preflight: 宿主存在多个 CapabilityManager，装配契约要求唯一管理器"
	if _find_capability(manager, CAPABILITY_NAME) != null:
		return "FlightBundle.preflight: 宿主已存在 %s，拒绝认领" % CAPABILITY_NAME
	if not with_visual:
		return ""
	var visual_root := host.get_node_or_null(VISUAL_ROOT) as Node3D
	if visual_root == null:
		return "FlightBundle.preflight: 宿主缺少 %s 节点，无法挂御剑视觉" % VISUAL_ROOT
	if visual_root.get_node_or_null(VISUAL_NAME) as Node3D != null:
		return "FlightBundle.preflight: %s/%s 已被占用，拒绝覆盖（先由拥有者清理）" % [VISUAL_ROOT, VISUAL_NAME]
	if host.flight_visual_node() != null:
		return "FlightBundle.preflight: 宿主已绑定其它御剑视觉，拒绝覆盖绑定"
	if FLYING_SWORD_SCENE == null:
		return "FlightBundle.preflight: flying_sword.glb 资源不可加载"
	return ""


## 安装御剑行为（with_visual 时连同 flying_sword.glb 视觉）。返回错误信息，"" 表示成功。
func install(host: Swordsman, with_visual: bool) -> String:
	if _installed:
		# 宿主身份必须一致：同一实例不能改挂到另一个 host（先 uninstall 再装）。
		if host == null or not is_instance_valid(host) or host != _host:
			return "FlightBundle.install: 已安装在另一个（或失效的）host；请先 uninstall"
		# 配置不可变：同配置幂等成功；请求新增视觉则明确拒绝，且**不删除已有能力**。
		if with_visual == _with_visual:
			return ""
		return "FlightBundle.install: 已安装（flight_visual=%s）；请先 uninstall 再按新配置 install" % _with_visual
	var preflight_error := preflight(host, with_visual)
	if preflight_error != "":
		return preflight_error
	var manager := _manager_of(host)
	var visual_root := host.get_node_or_null(VISUAL_ROOT) as Node3D
	# 预检通过后提交：逐步创建，失败只回滚本次新增。
	var capability := SwordFlight.new()
	capability.name = CAPABILITY_NAME
	manager.add_child(capability)
	_capability = capability
	_host = host
	if with_visual:
		var instance := FLYING_SWORD_SCENE.instantiate()
		if not (instance is Node3D):
			uninstall()
			return "FlightBundle.install: flying_sword.glb 根节点不是 Node3D"
		var sword := instance as Node3D
		sword.name = VISUAL_NAME
		visual_root.add_child(sword)
		_visual = sword
		host.bind_flight_visual(sword)
	_installed = true
	_with_visual = with_visual
	return ""


## 卸载本实例安装的行为与视觉；不动宿主组件、输入、速度。返回错误信息，"" 表示成功。
## 幂等：未安装、宿主已释放或重复调用均为 no-op，不调用已释放对象。
func uninstall() -> String:
	var host_alive := _host != null and is_instance_valid(_host)
	if host_alive and _visual != null and is_instance_valid(_visual):
		_host.unbind_flight_visual(_visual)
	if _capability != null and is_instance_valid(_capability):
		if _capability.get_parent() != null:
			_capability.get_parent().remove_child(_capability)
		_capability.queue_free()
	if _visual != null and is_instance_valid(_visual):
		if _visual.get_parent() != null:
			_visual.get_parent().remove_child(_visual)
		_visual.queue_free()
	_capability = null
	_visual = null
	_host = null
	_installed = false
	_with_visual = false
	return ""


## 是否已由本实例安装。
func is_installed() -> bool:
	return _installed


## 本实例创建的能力节点；未安装或已释放返回 null。
func installed_capability() -> Capability:
	return _capability if _capability != null and is_instance_valid(_capability) else null


## 本实例创建的视觉节点；未安装、未请求视觉或已释放返回 null。
func installed_visual() -> Node3D:
	return _visual if _visual != null and is_instance_valid(_visual) else null


static func _manager_of(host: Swordsman) -> CapabilityManager:
	# 按类型找直系子；同时要求它的父确实是该 host（契约要求，而非名字恰好一致）。
	for child in host.get_children():
		if child is CapabilityManager and child.get_parent() == host:
			return child as CapabilityManager
	return null


## 宿主直系 CapabilityManager 的数量（装配契约要求恰好一个）。
static func _count_managers(host: Swordsman) -> int:
	var count := 0
	for child in host.get_children():
		if child is CapabilityManager and child.get_parent() == host:
			count += 1
	return count


## 宿主直系 / 名下唯一的运动组件。按类型查找并做唯一性要求。
static func _find_motion(host: Swordsman) -> SwordsmanMotionComponent:
	var found: SwordsmanMotionComponent = null
	for node in host.find_children("*", "Node", true, false):
		if node is SwordsmanMotionComponent:
			if found != null:
				return null
			found = node as SwordsmanMotionComponent
	return found


static func _find_capability(manager: CapabilityManager, capability_class: StringName) -> Capability:
	for child in manager.get_children():
		if child is Capability:
			var script: Script = child.get_script()
			if script != null and script.get_global_name() == capability_class:
				return child as Capability
	return null
