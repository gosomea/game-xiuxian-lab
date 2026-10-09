class_name SwordCastBundle
extends RefCounted

## 剑法装配包：把 SwordCastComponent、调用方给出的出招能力与 SwordCastPresentation
## 装到既有 Swordsman 上。
##
## 依据 notes/implemented/tech/2026-09-18-composable-lab-assembly-contract.md 的 owner / borrow 原则：
## 能力注册为宿主 CapabilityManager 的直系子；只记录并卸载本实例创建的节点；已存在同名
## 组件、能力或表现一律拒绝；安装中途失败回滚本次新增；不调用 reset_motion()。
## 能力脚本由场景传入，本包不 preload 任何 Capability，避免共享契约反向依赖招式包。

const COMPONENT_NAME := "SwordCastComponent"
const PRESENTATION_NAME := "SwordCastPresentation"

var _host: Swordsman = null
var _component: SwordCastComponent = null
var _owned: Array[Node] = []


## 安装；返回错误信息，"" 表示成功。一个实例只安装一次。
func install(host: Swordsman, capability_scripts: Array[Script]) -> String:
	if _host != null:
		return "SwordCastBundle.install: 已安装，请先 uninstall"
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return "SwordCastBundle.install: 宿主为空或不在场景树中"
	var manager := host.capability_manager()
	if manager == null or manager.get_parent() != host:
		return "SwordCastBundle.install: 宿主缺少直系 CapabilityManager"
	if host.get_node_or_null(COMPONENT_NAME) != null or host.get_node_or_null(PRESENTATION_NAME) != null:
		return "SwordCastBundle.install: 宿主已有剑法组件或表现，拒绝认领"
	var names: Array[String] = []
	for script in capability_scripts:
		var global_name := str(script.get_global_name()) if script != null else ""
		if global_name.is_empty():
			return "SwordCastBundle.install: 能力脚本缺少 class_name"
		if manager.get_node_or_null(global_name) != null:
			return "SwordCastBundle.install: 宿主已存在 %s，拒绝重复装配" % global_name
		names.append(global_name)
	_host = host
	_component = SwordCastComponent.new()
	_component.name = COMPONENT_NAME
	_own(host, _component)
	LabDefaults.apply_component(_component)
	for index in range(capability_scripts.size()):
		var capability := capability_scripts[index].new() as Capability
		if capability == null:
			uninstall()
			return "SwordCastBundle.install: %s 不是 Capability" % names[index]
		capability.name = names[index]
		_own(manager, capability)
	var presentation := SwordCastPresentation.new()
	presentation.name = PRESENTATION_NAME
	_own(host, presentation)
	presentation.bind(host, _component)
	return ""


## 卸载本实例创建的节点（逆序）；不触碰宿主其它组件、能力、输入与速度。
func uninstall() -> void:
	for index in range(_owned.size() - 1, -1, -1):
		var node := _owned[index]
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_owned.clear()
	_component = null
	_host = null


func component() -> SwordCastComponent:
	return _component


func is_installed() -> bool:
	return _host != null


func _own(parent: Node, node: Node) -> void:
	parent.add_child(node)
	_owned.append(node)
