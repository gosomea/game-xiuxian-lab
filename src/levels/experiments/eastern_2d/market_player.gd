extends CharacterBody2D

## 坊市试验专用的四向步行。物理位置以脚下为准，视觉图像相对脚下偏移。

const WALK_SPEED := 235.0
const ACCELERATION := 1700.0
const SHEET_HEIGHT := 887.0
const FACE_REGIONS := [
	Rect2(0, 0, 443, 887),
	Rect2(443, 0, 443, 887),
	Rect2(886, 0, 444, 887),
	Rect2(1330, 0, 444, 887),
]

@onready var _visual: Sprite2D = %Visual

var _facing := 0
var _walk_time := 0.0


func _ready() -> void:
	assert(_visual != null, "坊市人物必须包含 Visual")
	_visual.region_rect = FACE_REGIONS[_facing]


func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("market_left", "market_right", "market_up", "market_down")
	velocity = velocity.move_toward(direction * WALK_SPEED, ACCELERATION * delta)
	move_and_slide()
	if direction.length_squared() > 0.01:
		if absf(direction.x) > absf(direction.y) * 1.2:
			_facing = 3 if direction.x > 0.0 else 2
		else:
			_facing = 0 if direction.y > 0.0 else 1
		_visual.region_rect = FACE_REGIONS[_facing]
		_walk_time += delta * 11.0
	else:
		_walk_time += delta * 2.0
	var moving := velocity.length_squared() > 100.0
	var depth := clampf((position.y - 320.0) / 500.0, 0.0, 1.0)
	var visual_scale := lerpf(0.135, 0.18, depth)
	_visual.scale = Vector2.ONE * visual_scale
	_visual.position.y = -SHEET_HEIGHT * visual_scale * 0.5 + (sin(_walk_time) * 2.0 if moving else sin(_walk_time) * 0.7)
	_visual.rotation = (sin(_walk_time) * 0.012) if moving else 0.0
