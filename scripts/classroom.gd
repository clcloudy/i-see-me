class_name PrototypeClassroom
extends Node3D

## 教室场景的视角/可见性控制器（D 流程）。
## 场景本体可以是任意一套教室布景，只要提供 Room 与同名节点；
## 人物（SeatedSelf / Observer）是可选的——纯布景场景没有人物时，相关逻辑自动跳过。

var _view: StringName = &"l1"
var _camera_position := Vector3(0, 1.36, 0.95)

## L3 拆掉的围挡：墙面、天花与踢脚。旧教室与静态教室两套命名都兼容，缺什么跳什么。
const STAGE_HIDDEN := [
	"Room/Ceiling", "Room/FrontWall", "Room/RightWall", "Room/RightSkirting", "Ceiling",
]

const LightmapUV2Lib = preload("res://scripts/lightmap_uv2.gd")

@onready var room: Node3D = $Room
@onready var seated_self: Node3D = get_node_or_null("SeatedSelf") as Node3D
@onready var observer: Node3D = get_node_or_null("Observer") as Node3D


func _ready() -> void:
	# Baked lightmaps need UV2 on every static mesh; the same unwrap runs at bake time.
	LightmapUV2Lib.prepare(self)


func set_view(view_id: StringName) -> void:
	_view = view_id
	var stage_visible := view_id == &"l3"
	for path in STAGE_HIDDEN:
		var surface := get_node_or_null(path) as Node3D
		if surface != null:
			surface.visible = not stage_visible
	var stage_floor := get_node_or_null("StageFloor") as Node3D
	if stage_floor != null:
		stage_floor.visible = stage_visible
	_update_people()


func update_camera_position(camera_position: Vector3) -> void:
	_camera_position = camera_position
	_update_people()


func _update_people() -> void:
	# Reveal each self only after the camera has left its head.
	if seated_self != null:
		var anchor := get_node_or_null("SeatedSelf/ViewAnchor") as Node3D
		var clear := anchor != null and _camera_position.distance_to(anchor.global_position) > 0.65
		seated_self.visible = _view != &"l1" and clear
	if observer != null:
		var anchor := get_node_or_null("Observer/ViewAnchor") as Node3D
		var clear := anchor != null and _camera_position.distance_to(anchor.global_position) > 0.65
		observer.visible = _view == &"l3" and clear
