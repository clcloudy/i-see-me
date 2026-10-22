class_name PrototypeFlow
extends Node

signal stage_changed(stage_id: StringName)

const CONTENT_PATH := "res://content/prototype.json"
const NEXT_VIEW := {&"l1": &"l2", &"l2": &"l3"}

@export var camera_rig: PrototypeCameraRig
@export var classroom: PrototypeClassroom
@export var interface: PrototypeUI
@export var flow_state: L2FlowState

var stage: StringName = &"intro"
var transitioning: bool = false
var muted: bool = false
var _last_advance_frame: int = -1


func _ready() -> void:
	var content = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_PATH))
	if not content is Dictionary:
		push_error("Prototype content could not be loaded.")
		get_tree().quit(1)
		return
	interface.configure(content)
	interface.advance_requested.connect(advance)
	interface.pause_requested.connect(toggle_pause)
	interface.mute_requested.connect(toggle_mute)
	interface.skip_requested.connect(skip_transition)
	interface.restart_requested.connect(restart)
	interface.quit_requested.connect(quit)
	camera_rig.transition_finished.connect(_on_transition_finished)
	camera_rig.pose_changed.connect(classroom.update_camera_position)
	restart()


func advance() -> void:
	var frame := Engine.get_process_frames()
	if get_tree().paused or transitioning or _last_advance_frame == frame:
		return
	_last_advance_frame = frame
	match stage:
		&"intro":
			_set_stage(&"l1")
		&"l1", &"l2":
			transitioning = true
			var next: StringName = NEXT_VIEW[stage]
			classroom.set_view(next)
			if not camera_rig.transition_to(next):
				transitioning = false
				classroom.set_view(stage)
			_refresh()
		&"l3":
			_set_stage(&"complete")


func toggle_pause() -> void:
	if stage in [&"intro", &"complete"]:
		return
	get_tree().paused = not get_tree().paused
	_refresh()
	interface.focus_primary()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	_refresh()


func skip_transition() -> void:
	if transitioning and not get_tree().paused:
		camera_rig.finish_transition()


func restart() -> void:
	get_tree().paused = false
	if flow_state != null:
		flow_state.deactivate(true)
	camera_rig.cancel_transition()
	transitioning = false
	_last_advance_frame = Engine.get_process_frames()
	camera_rig.snap_to(&"l1")
	_set_stage(&"intro")


func quit() -> void:
	get_tree().paused = false
	if flow_state != null:
		flow_state.deactivate(true)
	camera_rig.cancel_transition()
	get_tree().quit()


func _on_transition_finished(view_id: StringName) -> void:
	if not transitioning or NEXT_VIEW.get(stage, &"") != view_id:
		return
	transitioning = false
	_last_advance_frame = Engine.get_process_frames()
	_set_stage(view_id)


func _set_stage(stage_id: StringName) -> void:
	stage = stage_id
	if stage in [&"l1", &"l2", &"l3"]:
		classroom.set_view(stage)
	elif stage == &"intro":
		classroom.set_view(&"l1")
	if flow_state != null:
		if stage == &"l2":
			flow_state.activate()
		else:
			flow_state.deactivate()
	_refresh()
	stage_changed.emit(stage)
	interface.focus_primary()


func _refresh() -> void:
	interface.present(stage, transitioning, get_tree().paused, muted)
