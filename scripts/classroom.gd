class_name PrototypeClassroom
extends Node3D

var _view: StringName = &"l1"
var _camera_position := Vector3(0, 1.36, 0.95)

@onready var room: Node3D = $Room
@onready var seated_self: Node3D = $SeatedSelf
@onready var observer: Node3D = $Observer


func set_view(view_id: StringName) -> void:
	_view = view_id
	var stage_visible := view_id == &"l3"
	for surface in [$Room/Ceiling, $Room/FrontWall, $Room/RightWall, $Room/RightSkirting]:
		surface.visible = not stage_visible
	$StageFloor.visible = stage_visible
	_update_people()


func update_camera_position(camera_position: Vector3) -> void:
	_camera_position = camera_position
	_update_people()


func _update_people() -> void:
	# Reveal each self only after the camera has left its head.
	seated_self.visible = _view != &"l1" and _camera_position.distance_to(
		$SeatedSelf/ViewAnchor.global_position
	) > 0.65
	observer.visible = _view == &"l3" and _camera_position.distance_to(
		$Observer/ViewAnchor.global_position
	) > 0.65
