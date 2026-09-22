extends SceneTree
## 实机取证：用**斜侧（3/4 等距）**机位拍一张，与使用者报告倾斜时的同角度对比。
##
## 为什么单独做这个：之前用正视角截图，正视角下前后倾会被投影掉、看不出来，
## 所以「看起来正了」并不能证明斜侧视角下的观感也修好了。必须用同一机位复现。

const SCENE := "res://levels/experiments/character_movement/motion_stage.tscn"
const CAP_MSEC := 20000

var _scene: Node
var _prefix := ""
var _ticks := 0
var _drawn := false
var _failed := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="):
			_prefix = arg.trim_prefix("--capture-prefix=")
	_scene = (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(_scene)


## 状态机推进：等场景稳定 -> 斜侧 -> 等稳定 -> 拍 -> 正面 -> 等稳定 -> 拍 -> 退出。
var _stage := 0
var _stage_started := 0


func _process(_delta: float) -> bool:
	_ticks += 1
	if _scene == null:
		return false
	match _stage:
		0:
			if _ticks < 20:
				return false
			# 斜侧机位：使用者报告「人物是斜的」时的机位。
			_scene.call("_apply_view", 2, true)
			_stage = 1
			_stage_started = _ticks
		1:
			if _ticks - _stage_started < 40:
				return false
			_capture("iso")
			_scene.call("_apply_view", 0, true)
			_stage = 2
			_stage_started = _ticks
		2:
			if _ticks - _stage_started < 40:
				return false
			_capture("front")
			print("ISO_SHOT 完成：失败 %d" % _failed)
			quit(0 if _failed == 0 else 1)
			return true
	return false


## 在 frame_post_draw 之后取图。同帧内先连信号再阻塞等待会拿不到本帧，
## 因此改为直接取当前 viewport 纹理：状态机已经等过 40 帧，内容已就绪。
func _capture(suffix: String) -> void:
	if _prefix.is_empty():
		print("SKIP 截图（未给 --capture-prefix）")
		return
	var image := root.get_texture().get_image()
	if image == null:
		_failed += 1
		print("FAIL 取不到视口图像：%s" % suffix)
		return
	var path := "%s-%s.png" % [_prefix, suffix]
	var err := image.save_png(path)
	if err == OK:
		print("PASS 截图 %s" % path)
	else:
		_failed += 1
		print("FAIL 截图失败 %s（错误 %d）" % [path, err])
