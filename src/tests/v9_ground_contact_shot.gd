extends SceneTree
## 实机取证：在真实移动场景里，用使用者报告问题时的同款机位拍角色全景与脚部特写。
##
## 为什么单独做这个：本轮修的是「角色浮空 / 没踩在地面上」。数字报告
## （tools/art/measure_glb_ground_contact.py）给出的是米数，而使用者看到的是画面。
## 本脚本把两者对上：同一场景、同一机位、同一状态，修前修后各拍一组。
##
## 必须窗口模式（无头不出帧）：
##   godot --path src --script res://tests/v9_ground_contact_shot.gd -- \
##       --capture-prefix=/abs/path/prefix
##
## 状态机：等场景稳定 → 3/4 斜侧全景 → 脚部近景 → 退出。

const SCENE := "res://levels/experiments/character_movement/jade_paper_sample.tscn"

var _prefix := ""
var _scene: Node
var _ticks := 0
var _failed := 0
var _stage := 0
var _stage_started := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-prefix="):
			_prefix = argument.trim_prefix("--capture-prefix=")
	_scene = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_scene)


func _process(_delta: float) -> bool:
	_ticks += 1
	if _scene == null:
		return false
	match _stage:
		0:
			if _ticks < 30:
				return false
			# 等场景装配完成再动相机：_ready 里才建 rig。
			_apply_view(2)
			_stage = 1
			_stage_started = _ticks
		1:
			if _ticks - _stage_started < 45:
				return false
			_capture("iso")
			_zoom_feet()
			_stage = 2
			_stage_started = _ticks
		2:
			if _ticks - _stage_started < 45:
				return false
			_capture("feet")
			print("GROUND_CONTACT_SHOT 完成：失败 %d" % _failed)
			quit(0 if _failed == 0 else 1)
			return true
	return false


## 切换机位。`jade_paper_sample` 的机位由 CameraRig 配置持有，本场景只暴露 rig()；
## 机位编号沿用 camera_lab / motion_stage 的 `_apply_view(index, snap)` 约定。
func _apply_view(index: int) -> void:
	if _scene.has_method("_apply_view"):
		_scene.call("_apply_view", index, true)
		return
	var rig: Node = _scene.call("rig") if _scene.has_method("rig") else null
	if rig == null:
		print("WARN 场景没有 rig() 也没有 _apply_view()，沿用默认机位")
		return
	if rig.has_method("set_mode"):
		rig.call("set_mode", "fixed_follow")


## 缩到最近，让脚与地面的关系填满画面。
##
## 走 CameraRig 自己的 set_zoom_size()，**不直接写 Camera3D**：rig 每帧独占写相机的
## position / rotation / size（见 camera_rig.gd 文件头「独占写」），直接写会被下一帧覆盖，
## 结果是一张看起来正常、其实完全没放大的图（本轮实测踩过）。
func _zoom_feet() -> void:
	var rig: Node = _scene.call("rig") if _scene.has_method("rig") else null
	if rig == null or not rig.has_method("set_zoom_size"):
		print("WARN 场景没有 rig().set_zoom_size()，脚部特写退回默认机位")
		return
	rig.call("set_zoom_size", 3.6)


## 直接取当前 viewport 纹理存图：状态机已经等过 45 帧，内容已就绪。
##
## 这里**不用** await frame_post_draw：`_process` 里调用协程不会等待它，脚本会在协程
## 恢复之前 quit()，截图既不落盘也不报错（实测「失败 0」且没有任何文件）。取图不加等待，
## 判定「等够了帧」的责任留在状态机里。
func _capture(suffix: String) -> void:
	if _prefix.is_empty():
		print("SKIP 截图（未给 --capture-prefix）：%s" % suffix)
		return
	var image := root.get_texture().get_image()
	if image == null:
		_failed += 1
		print("FAIL 取不到视口图像：%s" % suffix)
		return
	var path := "%s-%s.png" % [_prefix, suffix]
	var error := image.save_png(path)
	if error == OK:
		print("PASS 截图 %s" % path)
	else:
		_failed += 1
		print("FAIL 截图失败 %s（错误 %d）" % [path, error])
