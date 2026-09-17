class_name SheetLoader
extends RefCounted

## Sheet 装配器。Sheet = 打包 Capability + Component 的 .tscn
## （见 notes/implemented/tech/2026-08-28-sheet-format.md）。
##
## 用途：丹药临时挂载、阵法进出、境界表单切换——统一走挂载/卸载。


## 从文件挂载 Sheet 到宿主，返回 Sheet 根节点（失败返回 null）。
static func attach(host: Node, sheet_path: String) -> Node:
	var packed := load(sheet_path) as PackedScene
	if packed == null:
		push_error("SheetLoader.attach: 无法加载 Sheet %s" % sheet_path)
		return null
	var sheet := packed.instantiate()
	sheet.set_meta(&"sheet_path", sheet_path)
	host.add_child(sheet)
	return sheet


## 包装已有节点树为 Sheet（运行时动态拼装，无文件形态）。
static func attach_node(host: Node, sheet: Node) -> Node:
	host.add_child(sheet)
	return sheet


## 卸载 Sheet：清理其发起的全部阻塞后释放节点。
static func detach(sheet: Node) -> void:
	if sheet == null:
		return
	for node in _walk(sheet):
		TagRegistry.remove_all_from(node)
	if sheet.get_parent() != null:
		sheet.get_parent().remove_child(sheet)
	sheet.queue_free()


static func _walk(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child in root.get_children():
		result.append_array(_walk(child))
	return result
