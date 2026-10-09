class_name LabParameterSchema
extends RefCounted

## 从公共词汇登记的纯数据组件发现导出参数；瞬态字段不进入设置。
const VOCABULARY_PATH := "res://data/vocabulary/index.json"
const MODE_CHOICES := ["fixed_follow", "quarter_turn", "orbit", "overview"]
const PRESET_CHOICES := ["hard", "smooth", "deadzone", "lookahead"]
const CAMERA_FIRST := ["start_mode", "projection", "size", "distance", "fov", "follow_preset",
	"mode_choices", "enable_mode_selection_keys"]
const GROUP_LABELS := {
	"SwordsmanMotionComponent": "移动与御剑", "SwordCastComponent": "剑法参数",
	"SwordTargetComponent": "木桩参数", "CameraRigConfig": "镜头参数",
}
const LABELS := {
	"move_speed": "步行速度 · m/s", "sprint_speed": "疾跑速度 · m/s",
	"sprint_enabled": "允许疾跑", "air_move_speed": "空中水平速度 · m/s（0 跟随地面）",
	"jump_speed": "起跳速度 · m/s", "gravity": "重力 · m/s²",
	"flight_speed": "御剑水平速度 · m/s", "flight_lift_speed": "御剑上升速度 · m/s",
	"flight_sink_speed": "御剑下降速度 · m/s", "flight_launch_speed": "起飞速度 · m/s",
	"flight_launch_time": "起飞时长 · s", "projection": "投影方式", "start_mode": "默认镜头模式",
	"follow_preset": "固定跟随方式", "size": "正交视野 · m", "size_min": "最小正交视野 · m",
	"size_max": "最大正交视野 · m", "zoom_step": "正交缩放步长 · m", "fov": "视场角 · °",
	"distance": "镜头距离 · m", "distance_min": "最小镜头距离 · m", "distance_max": "最大镜头距离 · m",
	"distance_step": "距离缩放步长 · m", "near": "近裁剪距离 · m", "far": "远裁剪距离 · m",
	"yaw_degrees": "初始方位角 · °", "pitch_degrees": "初始俯角 · °",
	"pitch_min_degrees": "最小俯角 · °", "pitch_max_degrees": "最大俯角 · °",
	"yaw_speed_degrees": "旋转速度 · °/s", "turn_step_degrees": "四向转角 · °",
	"smooth_time": "跟随平滑时间 · s", "transition_time": "视角切换时间 · s",
	"deadzone_half_width": "跟随死区半宽 · m", "deadzone_half_height": "跟随死区半高 · m",
	"lookahead_time": "前视提前量 · s", "lookahead_max": "前视距离上限 · m",
	"lookahead_smooth_time": "前视平滑时间 · s", "pan_speed": "全景平移倍率",
	"pan_distance_max": "全景平移上限 · m", "recenter_time": "全景回中时间 · s",
	"height_reference_y": "高度参考面 · m", "height_distance_bias": "高度距离增益",
	"height_bias_max": "高度距离增益上限 · m", "speed_distance_bias": "速度距离增益",
	"speed_bias_max": "速度距离增益上限 · m", "focus_offset": "取景偏移 · m",
	"focus_clamp_enabled": "限制地面取景范围", "focus_clamp_y_enabled": "限制取景高度",
	"focus_clamp_min": "取景范围下界 · m", "focus_clamp_max": "取景范围上界 · m",
	"enable_mode_selection_keys": "允许数字键切换镜头", "enable_preset_key": "允许 Tab 切换跟随",
	"enable_zoom_keys": "允许 Z/X 缩放", "enable_zoom_wheel": "允许滚轮缩放",
	"enable_yaw_keys": "允许 Q/E 与右键旋转", "consume_unowned_rmb": "镜头区域接管右键",
	"fov_is_configurable": "允许调整视场角", "mode_choices": "可用镜头模式",
	"sword_rest_offset": "本命剑悬浮偏移 · m", "pose_time": "出招姿势时长 · s",
	"qi_speed": "剑气速度 · m/s", "qi_range": "剑气射程 · m", "qi_radius": "剑气命中半宽 · m",
	"qi_height": "剑气高度 · m", "qi_cooldown": "剑气冷却 · s",
	"strike_speed": "飞剑出击速度 · m/s", "strike_range": "飞剑射程 · m",
	"strike_return_speed": "飞剑回程速度 · m/s", "strike_radius": "飞剑命中半径 · m",
	"array_max": "剑阵剑数上限", "array_spawn_interval": "剑阵蓄剑间隔 · s",
	"array_fire_interval": "剑阵发射间隔 · s", "array_speed": "剑阵飞行速度 · m/s",
	"array_radius": "剑阵命中半径 · m", "array_spread": "剑阵落点散布 · m",
	"array_cooldown": "剑阵冷却 · s", "radius": "目标命中半径 · m", "height": "目标命中高度 · m",
}
static var _components: Dictionary = {}
static var _camera: Array[Dictionary] = []


static func component_groups() -> Dictionary:
	if not _components.is_empty():
		return _components
	var vocabulary: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VOCABULARY_PATH))
	for component_class in vocabulary["components"]:
		var registered: Dictionary = vocabulary["components"][component_class]
		var path := str(registered["script"])
		if not path.begins_with("src/game/"):
			continue
		var script := load("res://" + path.trim_prefix("src/")) as Script
		var instance: Object = script.new()
		var parameters := exported_parameters(instance)
		instance.free()
		if not parameters.is_empty():
			_components[component_class] = parameters
	return _components


static func camera_parameters() -> Array[Dictionary]:
	if _camera.is_empty():
		_camera = exported_parameters(CameraRigConfig.new())
		var ordered: Array[Dictionary] = []
		for key in CAMERA_FIRST:
			ordered.append(find(_camera, key))
		for parameter in _camera:
			if parameter["key"] not in CAMERA_FIRST:
				ordered.append(parameter)
		_camera = ordered
	return _camera


static func exported_parameters(instance: Object) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for property in instance.get_property_list():
		var field := str(property["name"])
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 \
			or (int(property["usage"]) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var type := int(property["type"])
		if type not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_VECTOR3, TYPE_STRING, TYPE_PACKED_STRING_ARRAY]:
			continue
		var minimum := 0.0
		var maximum := 1000.0
		if field in ["yaw_degrees", "height_reference_y"] or type == TYPE_VECTOR3:
			minimum = -1000.0
		if field == "gravity" or field == "near":
			minimum = 0.01
		if field in ["array_spawn_interval", "array_fire_interval"]:
			minimum = 0.005
		if field == "array_max":
			minimum = 1.0
			maximum = 200.0
		if field == "fov":
			minimum = 10.0
			maximum = 150.0
		if field in ["pitch_degrees", "pitch_min_degrees", "pitch_max_degrees"]:
			maximum = 89.0
		var choices: Array = []
		if field == "start_mode" or field == "mode_choices":
			choices = MODE_CHOICES.duplicate()
		elif field == "follow_preset":
			choices = PRESET_CHOICES.duplicate()
		elif field == "projection":
			choices = [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]
		result.append({"key": field, "type": type, "label": LABELS.get(field, field.capitalize()),
			"default": encode(instance.get(field)), "min": minimum, "max": maximum,
			"step": 1.0 if type == TYPE_INT else (0.005 if field.ends_with("interval") else 0.01),
			"choices": choices})
	return result


static func find(parameters: Array, field: String) -> Dictionary:
	for parameter in parameters:
		if parameter["key"] == field:
			return parameter
	return {}


static func validate_value(parameter: Dictionary, value: Variant) -> String:
	if parameter.is_empty():
		return "参数未登记"
	var type := int(parameter["type"])
	match type:
		TYPE_BOOL:
			if not value is bool:
				return "需要开关值"
		TYPE_FLOAT, TYPE_INT:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
				return "需要有限数值"
			if float(value) < parameter["min"] or float(value) > parameter["max"]:
				return "数值范围为 %s–%s" % [parameter["min"], parameter["max"]]
			if type == TYPE_INT and float(value) != floorf(float(value)):
				return "需要整数"
		TYPE_VECTOR3:
			if not value is Array or value.size() != 3:
				return "需要三维坐标"
			for axis in value:
				if typeof(axis) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(axis)) \
					or float(axis) < parameter["min"] or float(axis) > parameter["max"]:
					return "坐标超出范围"
		TYPE_STRING:
			if not value is String or (not parameter["choices"].is_empty() and value not in parameter["choices"]):
				return "选项无效"
		TYPE_PACKED_STRING_ARRAY:
			if not value is Array or value.is_empty():
				return "至少选择一个镜头模式"
			for choice in value:
				if choice not in parameter["choices"]:
					return "镜头模式无效"
	if not parameter["choices"].is_empty() and type in [TYPE_INT, TYPE_STRING] \
		and value not in parameter["choices"]:
		return "选项无效"
	return ""


static func encode(value: Variant) -> Variant:
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is PackedStringArray:
		return Array(value)
	return value


static func decode(parameter: Dictionary, value: Variant) -> Variant:
	match int(parameter["type"]):
		TYPE_VECTOR3:
			return Vector3(float(value[0]), float(value[1]), float(value[2]))
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
	return value
