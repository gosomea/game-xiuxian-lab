extends Node2D

## 一屏坊市的场景编排。背景像素坐标即世界坐标，人物脚下位置驱动遮挡顺序。

const HUB_SCENE := "res://levels/lab_hub.tscn"
const TALK_RANGE := 116.0

const VISITORS := [
	{"node": "Herbalist", "name": "青岚药师", "line": "山里新采的清心草。闻着淡，煎出来却很香。"},
	{"node": "JadeTrader", "name": "玉器摊主", "line": "这块青玉留着天然纹路。先拿在手里看看光。"},
	{"node": "Traveler", "name": "路过的剑修", "line": "山门今日云开，往北走的景色很好。"},
]

@onready var _player: CharacterBody2D = %Player
@onready var _actors: Node2D = %Actors
@onready var _nearby_label: Label = %NearbyLabel
@onready var _hint_panel: PanelContainer = %HintPanel
@onready var _talk_panel: PanelContainer = %TalkPanel
@onready var _talk_name: Label = %TalkName
@onready var _talk_line: Label = %TalkLine

var _interact_down := false
var _cancel_down := false
var _nearby: Dictionary = {}


func _ready() -> void:
	assert(_player != null and _actors != null, "坊市人物与角色层必须存在")
	%BackButton.pressed.connect(_return_to_hub)
	_talk_panel.visible = false
	_build_walls()
	_build_visitor_collisions()


func _process(_delta: float) -> void:
	_nearby = _find_nearby_visitor()
	if _nearby.is_empty():
		_nearby_label.text = "WASD / 方向键 · 漫步坊市"
	else:
		_nearby_label.text = "E · 与%s交谈" % _nearby["name"]
	var interact_pressed := Input.is_action_pressed("market_interact")
	if interact_pressed and not _interact_down:
		if _talk_panel.visible:
			_talk_panel.visible = false
		elif not _nearby.is_empty():
			_talk_name.text = str(_nearby["name"])
			_talk_line.text = str(_nearby["line"])
			_talk_panel.visible = true
	_interact_down = interact_pressed
	var cancel_pressed := Input.is_action_pressed("ui_cancel")
	if cancel_pressed and not _cancel_down:
		if _talk_panel.visible:
			_talk_panel.visible = false
		else:
			_return_to_hub()
	_cancel_down = cancel_pressed
	var moving_input := Input.get_vector("market_left", "market_right", "market_up", "market_down")
	if _talk_panel.visible and (_nearby.is_empty() or moving_input.length_squared() > 0.01):
		_talk_panel.visible = false
	_hint_panel.visible = not _talk_panel.visible


func _find_nearby_visitor() -> Dictionary:
	var closest: Dictionary = {}
	var best_distance := TALK_RANGE
	for visitor in VISITORS:
		var node := _actors.get_node(str(visitor["node"])) as Node2D
		var distance := _player.position.distance_to(node.position)
		if distance < best_distance:
			best_distance = distance
			closest = visitor
	return closest


func _build_walls() -> void:
	var obstacles := StaticBody2D.new()
	obstacles.name = "MarketObstacles"
	obstacles.collision_layer = 1
	obstacles.collision_mask = 0
	add_child(obstacles)
	# 坊市画面中的铺面、栏杆与边界。碰撞范围让脚下始终停在石铺道路。
	_add_wall(obstacles, Vector2(804, 320), Vector2(1570, 54))
	_add_wall(obstacles, Vector2(804, 877), Vector2(1570, 80))
	_add_wall(obstacles, Vector2(197, 540), Vector2(54, 670))
	_add_wall(obstacles, Vector2(1399, 540), Vector2(54, 670))
	_add_wall(obstacles, Vector2(346, 320), Vector2(447, 219))
	_add_wall(obstacles, Vector2(1256, 330), Vector2(312, 242))
	_add_wall(obstacles, Vector2(281, 706), Vector2(170, 274))
	_add_wall(obstacles, Vector2(1335, 708), Vector2(120, 280))


func _add_wall(parent: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = center
	parent.add_child(collision)


func _build_visitor_collisions() -> void:
	for visitor in VISITORS:
		var node := _actors.get_node(str(visitor["node"])) as Node2D
		var body := StaticBody2D.new()
		body.name = "Footprint"
		body.collision_layer = 1
		body.collision_mask = 0
		node.add_child(body)
		var shape := CircleShape2D.new()
		shape.radius = 20.0
		var collision := CollisionShape2D.new()
		collision.shape = shape
		collision.position = Vector2(0, -9)
		body.add_child(collision)


func _return_to_hub() -> void:
	get_viewport().set_input_as_handled()
	var result := get_tree().change_scene_to_file(HUB_SCENE)
	if result != OK:
		push_error("坊市无法返回实验目录：%d" % result)
