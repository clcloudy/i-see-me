class_name PrototypeCameraRig
extends Node3D

signal transition_finished(view_id: StringName)
signal pose_changed(camera_position: Vector3)

@export_range(0.1, 10.0) var transition_seconds: float = 2.2

var _tween: Tween
var _generation: int = 0
var _active_view: StringName = &""
var _from: Transform3D
var _target: Transform3D

@onready var camera: Camera3D = $Camera3D
@onready var _views: Dictionary = {&"l1": $L1, &"l2": $L2, &"l3": $L3}
@onready var _focuses: Dictionary = {
	&"l1": $TeacherFocus, &"l2": $SubjectFocus, &"l3": $StageFocus
}


func _ready() -> void:
	snap_to(&"l1")


func snap_to(view_id: StringName) -> void:
	cancel_transition()
	camera.global_transform = _view_transform(view_id)
	pose_changed.emit(camera.global_position)


func transition_to(view_id: StringName) -> bool:
	if is_transitioning() or not _views.has(view_id):
		return false
	_generation += 1
	_active_view = view_id
	_from = camera.global_transform
	_target = _view_transform(view_id)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_tween.tween_method(_apply_blend, 0.0, 1.0, transition_seconds).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_complete.bind(_generation))
	return true


func finish_transition() -> void:
	if not is_transitioning():
		return
	if _tween != null:
		_tween.kill()
	_complete(_generation)


func cancel_transition() -> void:
	_generation += 1
	if _tween != null:
		_tween.kill()
	_tween = null
	_active_view = &""


func is_transitioning() -> bool:
	return not _active_view.is_empty()


func _view_transform(view_id: StringName) -> Transform3D:
	var marker: Marker3D = _views[view_id]
	var focus: Marker3D = _focuses[view_id]
	return marker.global_transform.looking_at(focus.global_position, Vector3.UP)


func _apply_blend(weight: float) -> void:
	camera.global_transform = _from.interpolate_with(_target, weight)
	pose_changed.emit(camera.global_position)


func _complete(generation: int) -> void:
	if generation != _generation or not is_transitioning():
		return
	_apply_blend(1.0)
	var finished_view := _active_view
	_active_view = &""
	_tween = null
	transition_finished.emit(finished_view)
