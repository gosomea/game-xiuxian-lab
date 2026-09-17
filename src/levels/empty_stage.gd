extends Node3D

const HUB := "res://levels/lab_hub.tscn"

@onready var _camera: Camera3D = %Camera3D
var _initial_transform: Transform3D
var _initial_size: float


func _ready() -> void:
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_initial_transform = _camera.transform
	_initial_size = _camera.size
	%ReturnButton.pressed.connect(_return_to_hub)
	%ResetButton.pressed.connect(reset_view)
	_update_scale_label()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_to_hub()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = clampf(_camera.size - 1.5, 10.0, 36.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = clampf(_camera.size + 1.5, 10.0, 36.0)
		else:
			return
		_update_scale_label()
		get_viewport().set_input_as_handled()


func reset_view() -> void:
	_camera.transform = _initial_transform
	_camera.size = _initial_size
	_update_scale_label()


func _update_scale_label() -> void:
	%ScaleLabel.text = "参考网格 1 米 / 格    ·    视野 %.1f 米" % _camera.size


func _return_to_hub() -> void:
	var result := get_tree().change_scene_to_file(HUB)
	if result != OK:
		%ScaleLabel.text = "返回失败，错误码：%d" % result
