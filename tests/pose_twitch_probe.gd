extends SceneTree

## 诊断脚本（临时）：逐帧采样课堂上所有学生的模型/骨骼变换，抓“闪一帧”的抽搐。
## 判据：某通道先跳出一个值、几帧内又跳回原值（走出+走回配对）。
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/pose_twitch_probe.gd

var _main: Node = null
var _flow: DialogueFlow = null
var _seating: Node3D = null

var _actors: Dictionary = {}    # name -> Node3D
var _models: Dictionary = {}    # name -> Node3D
var _skels: Dictionary = {}     # name -> Skeleton3D
var _last_pose: Dictionary = {} # name -> int
var _last: Dictionary = {}      # "name|channel" -> sample value
var _moves: Dictionary = {}     # "name|channel" -> Array[{frame, from, to}]
var _pose_log: Array = []
var _stage_log: Array = []
var _frames := 0
var _stage_now: StringName = &""
var _card_now := -1

var _bones := ["Hips", "Torso", "Neck", "Head", "UpperArm.L", "LowerLeg.L"]
const TH_FLOAT := 0.012
const TH_QUAT := 2.5


func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/classroom_dialogue.tscn") as PackedScene
	if packed == null:
		print("PROBE: cannot load scene")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	for i in range(3):
		await process_frame
	_flow = _main.get_node_or_null("Flow") as DialogueFlow
	_seating = _main.get_node_or_null("Seating") as Node3D
	if _flow == null or _seating == null:
		print("PROBE: missing Flow/Seating")
		quit(1)
		return
	_flow.time_scale = 0.5
	_collect()
	process_frame.connect(_on_frame)
	print("PROBE: %d actors, fps cap %d" % [_actors.size(), Engine.max_fps])

	_press_intro()
	if not await _wait_stage(&"choice", 120.0):
		print("PROBE: never reached choice")
		quit(1)
		return
	_stage_log.append({"frame": _frames, "text": "choose answer"})
	_flow.debug_choose("认真试过的人，也可以保留停下的选择。")
	if not await _wait_stage(&"l2", 150.0):
		print("PROBE: never reached l2")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 45000 and _flow.stage == &"l2":
		await process_frame
	_report()
	quit(0)


func _collect() -> void:
	for child in _seating.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var model := node.get_node_or_null("Model") as Node3D
		if model == null:
			continue
		var skel: Skeleton3D = null
		for sub in node.find_children("*", "Skeleton3D", true, false):
			skel = sub as Skeleton3D
			break
		var nm := str(node.name)
		_actors[nm] = node
		_models[nm] = model
		_skels[nm] = skel
		_last_pose[nm] = int(node.get("pose")) if node.get("pose") != null else -1


func _press_intro() -> void:
	var ui := _main.get_node_or_null("DialogueUI")
	if ui == null:
		return
	var primary := ui.get_node_or_null("Screen/CardPanel/Box/CardButtons/CardPrimary") as Button
	if primary != null:
		primary.pressed.emit()


func _wait_stage(target: StringName, limit_seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit_seconds * 1000.0:
		if _flow.stage == target:
			return true
		await process_frame
	return false


func _on_frame() -> void:
	_frames += 1
	if _flow != null:
		if _flow.stage != _stage_now:
			_stage_now = _flow.stage
			_stage_log.append({"frame": _frames, "text": "stage=" + str(_stage_now)})
		var card := int(_flow.get("_l2_index"))
		if card != _card_now:
			_card_now = card
			_stage_log.append({"frame": _frames, "text": "l2 card #%d" % card})
	for nm in _actors:
		var node: Node3D = _actors[nm]
		if not is_instance_valid(node):
			continue
		_push(nm, "model_y", _models[nm].position.y, false)
		var skel: Skeleton3D = _skels[nm]
		if skel == null or skel.get_bone_count() == 0:
			continue
		var hips := skel.find_bone("Hips")
		if hips != -1:
			_push(
				nm, "hips_y",
				float((skel.global_transform * skel.get_bone_global_pose(hips)).origin.y),
				false
			)
		for bone_name in _bones:
			var idx := skel.find_bone(bone_name)
			if idx == -1:
				continue
			_push(nm, bone_name, skel.get_bone_pose_rotation(idx), true)
		if node.get("pose") != null:
			var p := int(node.pose)
			if p != int(_last_pose[nm]):
				_pose_log.append({"frame": _frames, "name": nm, "from": int(_last_pose[nm]), "to": p})
				_last_pose[nm] = p


func _push(name: String, channel: String, value: Variant, is_quat: bool) -> void:
	var key := name + "|" + channel
	if not _last.has(key):
		_last[key] = value
		return
	var prev: Variant = _last[key]
	var d := 0.0
	if is_quat:
		d = rad_to_deg((value as Quaternion).angle_to(prev as Quaternion))
	else:
		d = absf(float(value) - float(prev))
	if d > (TH_QUAT if is_quat else TH_FLOAT):
		if not _moves.has(key):
			_moves[key] = []
		(_moves[key] as Array).append({"frame": _frames, "from": prev, "to": value, "d": d})
		_last[key] = value


## 走出去再走回来（间隔 <= 4 帧）= 视觉上的一闪。
func _flickers() -> Array:
	var out: Array = []
	for key in _moves:
		var list: Array = _moves[key]
		var i := 0
		while i + 1 < list.size():
			var a: Dictionary = list[i]
			var b: Dictionary = list[i + 1]
			var gap := int(b["frame"]) - int(a["frame"])
			if gap <= 4 and _close(a["from"], b["to"]):
				out.append({
					"key": key, "from": int(a["frame"]), "to": int(b["frame"]),
					"gone": a["from"], "mid": a["to"], "d": a["d"], "stage": "",
				})
				i += 2
			else:
				i += 1
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["from"]) < int(y["from"]))
	return out


func _close(a: Variant, b: Variant) -> bool:
	if a is Quaternion:
		return rad_to_deg((a as Quaternion).angle_to(b as Quaternion)) < 1.0
	return absf(float(a) - float(b)) < 0.008


func _describe_at(frame: int) -> String:
	var pieces: Array = []
	for entry in _stage_log:
		if int(entry["frame"]) <= frame:
			pieces.append(str(entry["text"]))
	var tail := pieces.slice(maxi(0, pieces.size() - 3))
	return " / ".join(tail)


func _report() -> void:
	print("")
	print("==== PROBE REPORT ====")
	print("frames sampled: %d  (%.1f s at 60fps)" % [_frames, _frames / 60.0])
	print("--- timeline ---")
	for entry in _stage_log:
		print("  f%-5d %s" % [int(entry["frame"]), str(entry["text"])])
	var flickers := _flickers()
	print("--- one-frame flickers: %d ---" % flickers.size())
	var by_node := {}
	for f in flickers:
		var nm := str(f["key"]).split("|")[0]
		by_node[nm] = int(by_node.get(nm, 0)) + 1
	for nm in by_node:
		print("  %-14s %d" % [nm, int(by_node[nm])])
	for f in flickers:
		print(
			"  f%-5d -> f%-5d  %-24s gone=%s mid=%s d=%.3f  [%s]"
			% [
				int(f["from"]), int(f["to"]), str(f["key"]),
				_str_val(f["gone"]), _str_val(f["mid"]), float(f["d"]),
				_describe_at(int(f["from"])),
			]
		)
	print("--- pose changes: %d ---" % _pose_log.size())
	for entry in _pose_log:
		print("  f%-5d %-13s %d -> %d" % [int(entry["frame"]), str(entry["name"]), int(entry["from"]), int(entry["to"])])


func _str_val(v: Variant) -> String:
	if v is Quaternion:
		var e: Vector3 = (v as Quaternion).get_euler()
		return "(%.0f,%.0f,%.0f)" % [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]
	return "%.4f" % float(v)
