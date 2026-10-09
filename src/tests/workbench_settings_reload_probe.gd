extends SceneTree


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-path="):
			LabDefaults.configure_storage(arg.trim_prefix("--settings-path="))
	_run.call_deferred()


func _run() -> void:
	var actor := (load("res://game/actors/swordsman/swordsman.tscn") as PackedScene).instantiate() as Swordsman
	root.add_child(actor)
	var camera := Camera3D.new()
	root.add_child(camera)
	var rig := (load("res://game/systems/camera_rig/camera_rig_sheet.tscn") as PackedScene).instantiate() as CameraRig
	root.add_child(rig)
	rig.bind(camera, actor, CameraRigConfig.new())
	var valid := actor.motion().move_speed == 3.25 and actor.motion().jump_speed == 8.0 \
		and actor.capability_manager().get_node_or_null("Jump") == null \
		and rig.component().mode_id == "overview" and LabDefaults.load_error.is_empty()
	print("SETTINGS_RELOAD_", "OK" if valid else "FAIL")
	actor.queue_free()
	rig.queue_free()
	camera.queue_free()
	await process_frame
	quit(0 if valid else 1)
