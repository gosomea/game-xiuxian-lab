extends RefCounted

## 角色移动子实验目录的数据契约测试：清单真相源、状态规则与入口判定。
## 真实运行链路（顶层入口、七项显示、键盘焦点、返回路径）由 src/tests/movement_hub_playtest.gd 覆盖。

const Hub := preload("res://levels/experiments/character_movement/movement_lab_hub.gd")
const Catalog := preload("res://game/systems/lab_catalog/lab_catalog.gd")

const EXPECTED_IDS := [
	"camera_lab",
	"motion_stage",
	"ground_contact_course",
	"sword_flight_course",
	"state_transition_lab",
	"movement_garden",
	"mountain_realm",
]
const EXPECTED_OPENABLE := ["camera_lab", "motion_stage", "movement_garden", "mountain_realm"]
const GARDEN_SCENE := "res://levels/experiments/character_movement/movement_garden.tscn"
const REALM_SCENE := "res://levels/experiments/character_movement/mountain_realm.tscn"


static func run(t) -> void:
	t.begin_case()
	var result := Hub.read()
	t.assert_true(result["errors"].is_empty(), "真实子实验清单满足契约：%s" % str(result["errors"]))
	t.assert_eq(str(result["parent_scene"]), "res://levels/lab_hub.tscn", "父级返回路径为顶层实验目录")
	var entries: Array = result["subexperiments"]
	t.assert_eq(entries.size(), EXPECTED_IDS.size(), "子实验清单恰好七项")
	var ids: Array = []
	var openable: Array = []
	for value in entries:
		var entry: Dictionary = value
		ids.append(str(entry["id"]))
		if Hub.can_open(entry):
			openable.append(str(entry["id"]))
	t.assert_eq(ids, EXPECTED_IDS, "子实验顺序与 note 提案一致")
	t.assert_eq(openable, EXPECTED_OPENABLE, "只有已落地子场景提供运行入口")
	for value in entries:
		var entry: Dictionary = value
		if str(entry["status"]) == "planned":
			t.assert_eq(str(entry["scene"]), "", "待探索条目不挂场景：%s" % entry["id"])
			t.assert_false(Hub.can_open(entry), "待探索条目不得进入：%s" % entry["id"])
		else:
			t.assert_true(str(entry["scene"]).begins_with("res://levels/"), "已落地条目场景位于 levels：%s" % entry["id"])
			t.assert_true(Hub.can_open(entry), "已落地条目可进入：%s" % entry["id"])

	t.begin_case()
	var top := Catalog.read()
	t.assert_true(top["errors"].is_empty(), "顶层实验清单仍满足契约")
	var movement := {}
	for value in top["modules"]:
		var module: Dictionary = value
		if str(module["id"]) == "character_movement":
			movement = module
	t.assert_eq(str(movement.get("scene", "")), "res://levels/experiments/character_movement/movement_lab_hub.tscn",
		"顶层角色移动入口指向子实验目录")
	t.assert_true(Catalog.can_open(movement), "顶层入口可打开")
	t.assert_true(ResourceLoader.exists(str(movement.get("scene", ""))), "顶层入口场景真实存在")
	for value in top["modules"]:
		var module: Dictionary = value
		if str(module["id"]) == "character_movement":
			continue
		t.assert_false(Catalog.can_open(module), "其余模块仍无运行入口：%s" % module["id"])

	t.begin_case()
	var base := _base_entries()
	t.assert_true(_valid(base), "七项基线清单通过结构校验")
	var planned: Dictionary = base[2]
	t.assert_eq(str(planned["scene"]), "", "基线地形接触训练场无场景")
	t.assert_false(Hub.can_open(planned), "planned 不可进入")
	var missing := base.duplicate(true)
	missing.remove_at(6)
	t.assert_false(_valid(missing), "缺少必需条目 mountain_realm 被拒绝")
	var false_planned := base.duplicate(true)
	(false_planned[2] as Dictionary)["scene"] = GARDEN_SCENE
	t.assert_false(_valid(false_planned), "planned 挂场景被拒绝")
	var false_ready := base.duplicate(true)
	(false_ready[2] as Dictionary)["status"] = "ready"
	t.assert_false(_valid(false_ready), "ready 缺场景被拒绝")
	var missing_scene := base.duplicate(true)
	(missing_scene[2] as Dictionary)["status"] = "ready"
	(missing_scene[2] as Dictionary)["scene"] = "res://levels/missing_subexperiment.tscn"
	t.assert_false(_valid(missing_scene), "ready 指向缺失场景被拒绝")
	t.assert_false(Hub.can_open(missing_scene[2] as Dictionary), "缺失场景不可进入")

	t.begin_case()
	var garden := _entry("movement_garden", "exploring", GARDEN_SCENE)
	t.assert_true(Hub.can_open(garden), "exploring + 有效场景可进入")
	var duplicate := base.duplicate(true)
	duplicate.append(garden.duplicate(true))
	t.assert_false(_valid(duplicate), "重复子实验 ID 被拒绝")
	var outside := base.duplicate(true)
	(outside[5] as Dictionary)["scene"] = "res://tests/fixtures/template_vitals/vitals_sheet.tscn"
	t.assert_false(_valid(outside), "测试夹具不得作为子实验入口")
	t.assert_false(Hub.can_open(outside[5] as Dictionary), "非 levels 场景不可进入")
	var bad_status := base.duplicate(true)
	(bad_status[5] as Dictionary)["status"] = "finished"
	t.assert_false(_valid(bad_status), "未知状态被拒绝")
	var empty_title := base.duplicate(true)
	(empty_title[5] as Dictionary)["title"] = "   "
	t.assert_false(_valid(empty_title), "空标题被拒绝")
	var bad_question := base.duplicate(true)
	(bad_question[5] as Dictionary)["question"] = ""
	t.assert_false(_valid(bad_question), "空问题被拒绝")
	var camera := base.duplicate(true)
	(camera[0] as Dictionary)["status"] = "planned"
	t.assert_false(_valid(camera), "已落地的镜头实验室被改回 planned 且挂场景时被拒绝")
	t.assert_false(Hub.validate([]).is_empty(), "错误顶层类型被拒绝")
	t.assert_false(Hub.validate({
		"schema_version": 2,
		"module": "character_movement",
		"parent_scene": "res://levels/lab_hub.tscn",
		"subexperiments": [],
	}).is_empty(), "不支持的 schema 被拒绝")
	t.assert_false(Hub.validate({
		"schema_version": 1,
		"module": "character_movement",
		"parent_scene": "res://levels/lab_hub.tscn",
		"subexperiments": [],
	}).is_empty(), "空子实验清单被拒绝（缺少全部必需条目）")


## 与真实清单同构的七项基线（两份已落地场景 + 五项待探索），供变异用例使用。
static func _base_entries() -> Array:
	return [
		_entry("camera_lab", "exploring", "res://levels/experiments/character_movement/camera_lab.tscn"),
		_entry("motion_stage", "exploring", "res://levels/experiments/character_movement/motion_stage.tscn"),
		_entry("ground_contact_course", "planned", ""),
		_entry("sword_flight_course", "planned", ""),
		_entry("state_transition_lab", "planned", ""),
		_entry("movement_garden", "exploring", GARDEN_SCENE),
		_entry("mountain_realm", "exploring", REALM_SCENE),
	]


static func _entry(id: String, status: String, scene: String) -> Dictionary:
	return {"id": id, "title": id, "stage": "fixture", "question": "fixture", "status": status, "scene": scene}


static func _valid(entries: Array) -> bool:
	return Hub.validate({
		"schema_version": 1,
		"module": "character_movement",
		"parent_scene": "res://levels/lab_hub.tscn",
		"subexperiments": entries,
	}).is_empty()
