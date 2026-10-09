extends SceneTree
## 主 Agent 连续画面验收：真实输入与可见窗口，保留每一帧运动样本和阶段图序列。
## 依据 notes/implemented/gameplay/2026-10-10-sword-spell-exploration.md。
const SCENE := "res://levels/experiments/sword_combat/sword_workbench.tscn"
const FORMS := [SwordCastComponent.FORM_WHEEL, SwordCastComponent.FORM_GIANT, SwordCastComponent.FORM_RAIN]
var _scene: Node
var _cast: SwordCastComponent
var _base := ""
var _run_dir := ""
var _checks: Array = []
var _samples: Array = []
var _captures: Array = []
var _passed := 0
var _failed := 0

func _initialize() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence-dir="):
			_base = arg.trim_prefix("--evidence-dir=")
	if _base.is_empty():
		_base = "docs/playtest/2026-10-10-sword-spells"
	if not _base.is_absolute_path():
		_base = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join(_base)
	_run_dir = _base.path_join("window-%s" % str(Time.get_unix_time_from_system()).replace(".", "-"))
	DirAccess.make_dir_recursive_absolute(_run_dir)
	_run.call_deferred()

func _check(ok: bool, text: String) -> void:
	_checks.append({"pass":ok,"label":text})
	if ok: _passed += 1
	else: _failed += 1
	print("PASS " if ok else "FAIL ", text)

func _run() -> void:
	root.size = Vector2i(1280,800)
	change_scene_to_file(SCENE)
	await scene_changed
	await _frames(25)
	_scene = current_scene
	_cast = _scene.call("cast_component")
	await _capture("idle",0)
	for form in FORMS:
		await _exercise(form, Vector3(0,0,-4), 80, form)
	# 小窗口、快速释放与高台落点。
	root.size = Vector2i(960,600)
	_scene.call("reset_experiment")
	await _frames(20)
	_scene.call("select_form",SwordCastComponent.FORM_GIANT)
	await _aim(Vector3(10,1.5,-5))
	_check(_cast.aim_surface_valid and absf(_cast.aim_surface_point.y-1.5)<.04,"960窗口高台真实落点")
	await _exercise(SwordCastComponent.FORM_GIANT,Vector3(10,1.5,-5),4,"giant_quick_platform")
	# C、R、跳跃、御剑保持输入入口；释放后切招由组合运行时覆盖。
	_scene.call("reset_experiment")
	await _frames(3)
	_scene.call("select_form",SwordCastComponent.FORM_QI)
	_key(KEY_C)
	await _frames(2)
	_check(_cast.form==SwordCastComponent.FORM_STRIKE,"C切招入口有效")
	_key(KEY_SPACE)
	await _frames(8)
	var actor: Swordsman = _scene.call("actor")
	_check(actor.global_position.y>.2,"Space跳跃有效")
	await _frames(80)
	_key(KEY_F)
	await _frames(20)
	_check(actor.motion().flight_active,"F御剑有效")
	_scene.call("select_form",SwordCastComponent.FORM_RAIN)
	await _aim(Vector3(0,0,-4))
	_click(true)
	await _frames(20)
	_key(KEY_R)
	await _frames(4)
	_check(str((_scene.call("spell_component",SwordCastComponent.FORM_RAIN) as Component).get("phase"))=="idle","R取消高空聚剑")
	_check(TimeKeeper.request_count()==0,"顿帧请求释放")
	_check(_scene.get_viewport().get_visible_rect().size.x>=960,"两种窗口尺寸运行")
	await _capture("small_window_final",0)
	var report := {"run_dir":_run_dir,"passed":_passed,"failed":_failed,"checks":_checks,"samples":_samples,"captures":_captures,"rendering_method":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"subjective_review":"Primary visual review is recorded separately in report.md"}
	_write_json(_run_dir.path_join("motion.json"),report)
	_write_json(_base.path_join("acceptance.json"),report)
	print("EVIDENCE ",_run_dir)
	print("SUMMARY passed=%d failed=%d"%[_passed,_failed])
	quit(1 if _failed else 0)

func _exercise(form:String,point:Vector3,hold:int,label:String) -> void:
	_scene.call("reset_experiment")
	await _frames(35)
	_scene.call("select_form",form)
	await _aim(point)
	_click(true)
	var data:Component=_scene.call("spell_component",form)
	var phases:Array=[]
	var frame:=0
	var previous:Dictionary={}
	var max_step:=0.0
	var min_tangent:=1.0
	var active_samples:=0
	for i in range(hold):
		await _aim(point)
		var metrics:=_sample(form,data,frame,previous)
		max_step=maxf(max_step,metrics[0]);min_tangent=minf(min_tangent,metrics[1]);active_samples+=int(metrics[2])
		if not str(data.get("phase")) in phases: phases.append(str(data.get("phase")))
		if frame%3==0: await _capture(label,frame)
		frame+=1
	_click(false)
	for i in range(300):
		await _frames(1)
		var metrics:=_sample(form,data,frame,previous)
		max_step=maxf(max_step,metrics[0]);min_tangent=minf(min_tangent,metrics[1]);active_samples+=int(metrics[2])
		if not str(data.get("phase")) in phases: phases.append(str(data.get("phase")))
		if frame%3==0: await _capture(label,frame)
		frame+=1
		if str(data.get("phase"))=="idle": break
	_check(phases.has("gather") and phases.has("idle"),label+"凝聚到消散阶段完整 "+str(phases))
	_check(str(data.get("phase"))=="idle",label+"完成并回到待命")
	_check(active_samples>10,label+"连续运动样本可观察")
	_check(max_step<2.0,label+"逐帧无超过2米跳变 %.3fm"%max_step)
	_check(min_tangent>.35,label+"剑尖与实际飞行方向一致 %.3f"%min_tangent)
	if point.y<.1: _check(int(_scene.call("total_hits"))>0,label+"实际命中木桩")
	_samples.append({"form":form,"summary":true,"phases":phases,"max_step_m":max_step,"min_tangent_dot":min_tangent,"motion_pairs":active_samples})

func _sample(form:String,data:Component,frame:int,previous:Dictionary)->Array:
	var phase:=str(data.get("phase"))
	var swords:Array=[]
	if form==SwordCastComponent.FORM_GIANT:
		if phase!="idle":swords.append({"slot":0,"point":data.get("sword_tip"),"forward":data.get("sword_forward"),"state":phase})
	else:
		var index:=0
		for sword in data.get("swords"):
			var point:Vector3=sword.get("tip",sword.get("position",Vector3.ZERO))
			swords.append({"slot":sword.get("slot",str(sword.get("ring",0))+":"+str(sword.get("angle",index))),"point":point,"forward":sword.get("forward",Vector3.DOWN),"state":str(sword.get("state",""))})
			index+=1
	var max_step:=0.0
	var min_dot:=1.0
	var pairs:=0
	var serialized:Array=[]
	for sword in swords:
		var point:Vector3=sword["point"]
		var forward:Vector3=sword["forward"]
		var slot:String=str(sword["slot"])
		var state:String=sword["state"]
		if previous.has(slot) and previous[slot]["state"]==state:
			var displacement:Vector3=point-previous[slot]["point"]
			max_step=maxf(max_step,displacement.length())
			if state in ["fly","flight","fall","descent"] and displacement.length()>.006:
				min_dot=minf(min_dot,forward.normalized().dot(displacement.normalized()))
				pairs+=1
		previous[slot]=sword
		serialized.append({"slot":slot,"point":[point.x,point.y,point.z],"forward":[forward.x,forward.y,forward.z],"state":state})
	_samples.append({"form":form,"frame":frame,"phase":phase,"swords":serialized})
	return [max_step,min_dot,pairs]

func _capture(label:String,frame:int)->void:
	await RenderingServer.frame_post_draw
	var path:=_run_dir.path_join("%s-%04d.png"%[label,frame])
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:_check(false,"截图保存 "+path)
	_captures.append(path)

func _write_json(path:String,data:Variant)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))

func _aim(point:Vector3)->void:
	var camera:=root.get_camera_3d()
	var event:=InputEventMouseMotion.new()
	event.position=root.get_stretch_transform()*camera.unproject_position(point)
	event.global_position=event.position
	Input.parse_input_event(event)
	await _frames(1)

func _click(pressed:bool)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	event.position=root.get_stretch_transform()*root.get_camera_3d().unproject_position(_cast.aim_surface_point)
	event.global_position=event.position
	Input.parse_input_event(event)

func _key(code:Key)->void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code;event.physical_keycode=code;event.pressed=pressed
		Input.parse_input_event(event)

func _frames(count:int)->void:
	for i in range(count):
		await physics_frame
		await process_frame
