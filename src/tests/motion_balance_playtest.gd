extends SceneTree
## Real movement input: eight-way facing, walk/run playback, jump and flight.
## Window capture: -- --capture-prefix=/absolute/path/motion
## Decision: notes/implemented/art/2026-09-27-human-locomotion-on-v9.md.
const SCENE := "res://levels/experiments/character_movement/motion_stage.tscn"
var _failed := 0
var _passed := 0
var _prefix := ""
var _actor: Swordsman
var _presentation: Node
var _player: AnimationPlayer

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-prefix="):
			_prefix = arg.trim_prefix("--capture-prefix=")
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("PASS ", label)
	else:
		_failed += 1
		print("FAIL ", label)

func _run() -> void:
	change_scene_to_file(SCENE)
	await scene_changed
	await _frames(30)
	_actor = current_scene.find_child("Swordsman", true, false) as Swordsman
	_presentation = _actor.get_node("Visual/CultivatorSkeletonPresentation")
	_player = _actor.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	await _capture("idle")
	for keys: Array in [[KEY_W],[KEY_S],[KEY_A],[KEY_D],[KEY_W,KEY_D],[KEY_W,KEY_A],[KEY_S,KEY_D],[KEY_S,KEY_A]]:
		_key(KEY_R,true); _key(KEY_R,false)
		await _frames(15)
		for code: Key in keys:
			_key(code,true)
		await _frames(12)
		var motion := _actor.motion()
		var flat := Vector3(_actor.velocity.x,0,_actor.velocity.z)
		var facing := (_actor.get_node("Visual") as Node3D).global_basis.z
		facing.y=0
		_check(absf(flat.length()-motion.move_speed)<.03,"eight-way %s speed %.3f" % [keys,flat.length()])
		_check(facing.normalized().dot(flat.normalized())>.999,"eight-way %s model faces velocity" % str(keys))
		_check(_presentation.pose_state()["current_clip"]=="walk","eight-way %s uses walk" % str(keys))
		for code: Key in keys:
			_key(code,false)
		await _frames(3)
	_key(KEY_R,true); _key(KEY_R,false)
	await _frames(20)
	_key(KEY_D,true)
	await _frames(30)
	_check(absf(_player.speed_scale-2.0/1.659)<.01,"walk playback matches measured stance reference")
	await _capture("walk")
	_key(KEY_SHIFT,true)
	await _frames(15)
	_check(_presentation.pose_state()["current_clip"]=="run","Shift selects run")
	_check(absf(_actor.velocity.length()-_actor.motion().sprint_speed)<.03,"run speed %.3f" % _actor.velocity.length())
	_check(absf(_player.speed_scale-4.2/4.224)<.01,"run plays close to native cadence")
	await _capture("run")
	_key(KEY_SPACE,true); _key(KEY_SPACE,false)
	await _frames(6)
	_check(not _actor.motion().on_floor and _presentation.pose_state()["current_clip"]=="jump","running jump uses jump clip")
	await _capture("jump")
	_key(KEY_D,false); _key(KEY_SHIFT,false)
	await _frames(80)
	_key(KEY_R,true); _key(KEY_R,false)
	await _frames(20)
	_key(KEY_F,true); _key(KEY_F,false)
	await _frames(20)
	_key(KEY_W,true); _key(KEY_SPACE,true)
	await _frames(12)
	_check(absf(Vector2(_actor.velocity.x,_actor.velocity.z).length()-22.0)<.03,"flight horizontal 22m/s")
	_check(absf(_actor.velocity.y-12.0)<.03,"flight ascent 12m/s")
	_check(_presentation.pose_state()["current_clip"]=="sword_ride","flight uses authored sword pose")
	await _capture("flight")
	_key(KEY_W,false); _key(KEY_SPACE,false)
	_key(KEY_CTRL,true)
	await _frames(6)
	_check(absf(_actor.velocity.y+12.0)<.03,"flight descent 12m/s")
	_key(KEY_CTRL,false)
	print("MOTION_BALANCE_RESULT passed=%d failed=%d" % [_passed,_failed])
	current_scene.queue_free()
	await _frames(3)
	quit(1 if _failed else 0)

func _capture(label: String) -> void:
	print("STATE %s position=%s pose=%s rate=%.3f" % [label,_actor.global_position,_presentation.pose_state(),_player.speed_scale])
	if _prefix.is_empty():
		return
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(_prefix+"-"+label+".png")
	_check(result==OK,"capture "+label)

func _frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=pressed
	Input.parse_input_event(event)
