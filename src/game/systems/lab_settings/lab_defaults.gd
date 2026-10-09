class_name LabDefaults
extends RefCounted

## 实验室用户默认：静态设施、稀疏覆盖、弱引用订阅，不持有场景生命周期。
const DEFAULT_PATH := "user://lab_defaults.json"
static var storage_path := DEFAULT_PATH
static var load_error := ""
static var apply_error := ""
static var revision := 0
static var _loaded := false
static var _profile: Dictionary = {"schema_version": 1, "components": {}, "camera": {}, "abilities": {}}
static var _saved: Dictionary = {}
static var _subscribers: Array[WeakRef] = []
static var _component_bases: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_saved = _profile.duplicate(true)
	if not FileAccess.file_exists(storage_path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(storage_path)) != OK:
		load_error = "保存的设置无法读取，已使用场景默认值"
		return
	var problem := validate(parser.data)
	if not problem.is_empty():
		load_error = "保存的设置无效：" + problem
		return
	_profile = parser.data.duplicate(true)
	_saved = _profile.duplicate(true)


static func snapshot() -> Dictionary:
	ensure_loaded()
	return _profile.duplicate(true)


static func is_dirty() -> bool:
	ensure_loaded()
	return _profile != _saved


static func subscribe(host: Node) -> void:
	ensure_loaded()
	for reference in _subscribers:
		if reference.get_ref() == host:
			return
	_subscribers.append(weakref(host))


static func apply_component(component: Component) -> void:
	ensure_loaded()
	var component_class := str(component.get_script().get_global_name())
	var parameters: Array = LabParameterSchema.component_groups().get(component_class, [])
	var id := component.get_instance_id()
	if not _component_bases.has(id):
		var base: Dictionary = {}
		for parameter in parameters:
			base[parameter["key"]] = LabParameterSchema.encode(component.get(parameter["key"]))
		_component_bases[id] = {"ref": weakref(component), "values": base}
	var values: Dictionary = _component_bases[id]["values"].duplicate(true)
	values.merge(_profile["components"].get(component_class, {}), true)
	for parameter in parameters:
		component.set(parameter["key"], LabParameterSchema.decode(parameter, values[parameter["key"]]))


static func camera_config(base: CameraRigConfig) -> CameraRigConfig:
	ensure_loaded()
	var result := base.duplicate() as CameraRigConfig
	for field in _profile["camera"]:
		var parameter := LabParameterSchema.find(LabParameterSchema.camera_parameters(), field)
		result.set(field, LabParameterSchema.decode(parameter, _profile["camera"][field]))
	# 未覆盖的场景构图可以收敛到用户选择的缩放范围。
	result.size = clampf(result.size, result.size_min, result.size_max)
	result.distance = clampf(result.distance, result.distance_min, result.distance_max)
	if _profile["camera"].has("start_mode") and not _profile["camera"].has("mode_choices"):
		result.mode_choices = PackedStringArray(LabParameterSchema.MODE_CHOICES)
	return result


static func ability_enabled(key: String, fallback: bool) -> bool:
	ensure_loaded()
	return bool(_profile["abilities"].get(key, fallback))


static func set_component_value(component_class: String, field: String, value: Variant) -> String:
	ensure_loaded()
	var candidate := _profile.duplicate(true)
	if not candidate["components"].has(component_class):
		candidate["components"][component_class] = {}
	candidate["components"][component_class][field] = LabParameterSchema.encode(value)
	return _replace(candidate)


static func set_camera_value(field: String, value: Variant) -> String:
	ensure_loaded()
	var candidate := _profile.duplicate(true)
	candidate["camera"][field] = LabParameterSchema.encode(value)
	# 切换默认视角会自动保留它为可用项；卸下默认视角时改用剩余的第一项。
	if field == "start_mode" and candidate["camera"].has("mode_choices"):
		if value not in candidate["camera"]["mode_choices"]:
			candidate["camera"]["mode_choices"].append(value)
	elif field == "mode_choices" and value is Array and not value.is_empty():
		var current: String = candidate["camera"].get("start_mode", "fixed_follow")
		if current not in value:
			candidate["camera"]["start_mode"] = value[0]
	return _replace(candidate)


static func set_ability(key: String, enabled: bool) -> String:
	ensure_loaded()
	var candidate := _profile.duplicate(true)
	candidate["abilities"][key] = enabled
	return _replace(candidate)


static func _replace(candidate: Dictionary) -> String:
	var problem := validate(candidate)
	if not problem.is_empty():
		return problem
	_profile = candidate
	revision += 1
	_publish()
	return apply_error


static func save() -> String:
	ensure_loaded()
	if not apply_error.is_empty():
		return "设置应用失败，请先解决装配冲突：" + apply_error
	var temporary := storage_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "无法保存设置（%s）" % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(_profile, "\t") + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "设置写入失败：" + error_string(write_error)
	var error := DirAccess.rename_absolute(temporary, storage_path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return "设置替换失败：" + error_string(error)
	_saved = _profile.duplicate(true)
	load_error = ""
	return ""


static func revert() -> void:
	ensure_loaded()
	_profile = _saved.duplicate(true)
	revision += 1
	_publish()


static func restore_original() -> void:
	ensure_loaded()
	_profile = {"schema_version": 1, "components": {}, "camera": {}, "abilities": {}}
	revision += 1
	_publish()


static func validate(value: Variant) -> String:
	if not value is Dictionary or value.get("schema_version") != 1:
		return "设置版本无效"
	for section in ["components", "camera", "abilities"]:
		if not value.get(section) is Dictionary:
			return "设置缺少 " + section
	var groups := LabParameterSchema.component_groups()
	for component_class in value["components"]:
		if not groups.has(component_class) or not value["components"][component_class] is Dictionary:
			return "未知组件参数组"
		var problem := _validate_fields(groups[component_class], value["components"][component_class])
		if not problem.is_empty():
			return problem
	var camera_problem := _validate_fields(LabParameterSchema.camera_parameters(), value["camera"])
	if not camera_problem.is_empty():
		return camera_problem
	var camera := CameraRigConfig.new()
	for field in value["camera"]:
		camera.set(field, LabParameterSchema.decode(LabParameterSchema.find(
			LabParameterSchema.camera_parameters(), field), value["camera"][field]))
	if camera.near >= camera.far or camera.size_min > camera.size_max \
		or camera.distance_min > camera.distance_max or camera.pitch_min_degrees > camera.pitch_max_degrees:
		return "镜头上下限顺序不正确"
	if not camera.mode_choices.has(camera.start_mode) and value["camera"].has("mode_choices"):
		return "可用镜头模式必须包含默认模式"
	for key in value["abilities"]:
		if key not in ["move", "jump", "flight", "camera"] or not value["abilities"][key] is bool:
			return "能力开关无效"
	return ""


static func _validate_fields(parameters: Array, values: Dictionary) -> String:
	for field in values:
		var parameter := LabParameterSchema.find(parameters, field)
		var problem := LabParameterSchema.validate_value(parameter, values[field])
		if not problem.is_empty():
			return "%s：%s" % [parameter.get("label", field), problem]
	return ""


static func _publish() -> void:
	apply_error = ""
	var alive: Array[WeakRef] = []
	for reference in _subscribers:
		var host: Object = reference.get_ref()
		if host == null:
			continue
		alive.append(reference)
		if host.has_method("apply_lab_defaults"):
			var problem: String = host.call("apply_lab_defaults")
			if not problem.is_empty():
				apply_error += ("\n" if not apply_error.is_empty() else "") + problem
	_subscribers = alive
	for id in _component_bases.keys():
		var component: Object = _component_bases[id]["ref"].get_ref()
		if component == null:
			_component_bases.erase(id)
		else:
			apply_component(component as Component)


## 自动验收只使用隔离路径；清理内存不写真实用户设置。
static func configure_storage(path: String) -> void:
	storage_path = path
	_loaded = false
	load_error = ""
	apply_error = ""
	_profile = {"schema_version": 1, "components": {}, "camera": {}, "abilities": {}}
	_saved = {}
	_subscribers.clear()
	_component_bases.clear()
	revision += 1


static func reset_test_state() -> void:
	configure_storage("user://lab_defaults_test_%s.json" % OS.get_process_id())
	_loaded = true
	_saved = _profile.duplicate(true)
