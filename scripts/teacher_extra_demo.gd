extends Node3D
## 教师新增动作演示（缺失动作 17~21，2026-10-24）。
## 数字键 1~5 切换；A 开关自动轮播。截图由 action_shot.gd 调用。

const ACTIONS: Array[int] = [
	TeacherAnimator.Action.CHALK_DOWN,
	TeacherAnimator.Action.BOOK_PLACE,
	TeacherAnimator.Action.POINT,
	TeacherAnimator.Action.WALK,
	TeacherAnimator.Action.BOOK_FLIP,
]
const LABELS := ["放下粉笔", "把课本放到讲台", "指向你", "讲台 ↔ 黑板走路", "翻课本"]

var teacher: TeacherAnimator
var hud: Label
var _index: int = -1
var _auto: bool = true
var _wait: float = 2.0
var _walk_from := Vector3(0, 0, 0)
var _walk_to := Vector3(-1.15, 0, -0.85)
var _walk_duration := 2.2


func _ready() -> void:
	ActionDemoStage.build(self, Vector3(1.9, 1.62, 2.95), Vector3(0, 1.05, -0.1))
	ActionDemoStage.blackboard(self, Vector3(0, 1.35, -1.5))
	ActionDemoStage.podium(self, Vector3(0, 0, 0.55))
	ActionDemoStage.label(self, "教师 · 动作补全", Vector3(0.4, 2.35, -0.6), 42)

	var lectern := Marker3D.new()
	lectern.name = "LecternTop"
	lectern.position = Vector3(0, 0.965, 0.32)
	add_child(lectern)
	var chalk_box := Marker3D.new()
	chalk_box.name = "ChalkBoxSpot"
	chalk_box.position = Vector3(0.22, 0.965, 0.32)
	add_child(chalk_box)
	var point := Marker3D.new()
	point.name = "PointTarget"
	point.position = Vector3(-1.05, 1.15, 1.45)
	add_child(point)

	var scene: Node3D = load("res://scenes/actors/teacher/teacher_animated.tscn").instantiate()
	scene.rotation_degrees.y = 180.0
	add_child(scene)
	teacher = scene as TeacherAnimator
	teacher.lectern_node = lectern
	teacher.chalk_box_node = chalk_box
	teacher.point_target = point

	hud = ActionDemoStage.hud(self)
	play_index(0)
	set_process(true)


func _process(delta: float) -> void:
	if not _auto:
		return
	_wait -= delta
	if _wait <= 0.0:
		play_index((_index + 1) % ACTIONS.size())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_5:
		_auto = false
		play_index(key - KEY_1)
	elif key == KEY_A:
		_auto = not _auto
		_wait = 0.1 if _auto else 1e9
	elif key == KEY_R:
		play_index(_index, true)


func set_demo_index(i: int) -> void:
	_auto = false
	play_index(i)


func seek_demo(seconds: float) -> void:
	if teacher == null:
		return
	if _index == 3:
		var k := smoothstep(0.0, 1.0, clampf(seconds / _walk_duration, 0.0, 1.0))
		teacher.global_position = _walk_from.lerp(_walk_to, k)
		teacher._walking = true
		teacher._walk_phase = seconds * TAU * 1.8
		teacher._model_yaw = rad_to_deg(atan2(-(_walk_to - _walk_from).x, -(_walk_to - _walk_from).z))
	teacher.warm_action(seconds, 8)


func set_auto(value: bool) -> void:
	_auto = value
	_wait = 0.1 if value else 1e9


func play_index(i: int, force: bool = false) -> void:
	var idx := clampi(i, 0, ACTIONS.size() - 1)
	if idx == _index and not force:
		return
	_index = idx
	teacher.global_position = Vector3.ZERO
	match idx:
		0:
			# 先站在黑板前板书，再执行“放下粉笔”：粉笔会从手里回到粉笔盒。
			teacher.set_action(TeacherAnimator.Action.WRITE_BOARD, true)
			teacher.set_action(TeacherAnimator.Action.CHALK_DOWN)
			_wait = 1.6 + 0.6
		1:
			teacher.set_action(TeacherAnimator.Action.BOOK_PLACE, true)
			_wait = 2.0 + 0.6
		2:
			teacher.set_action(TeacherAnimator.Action.POINT, true)
			_wait = 2.8
		3:
			teacher.set_action(TeacherAnimator.Action.LECTURE, true)
			teacher.walk_to(_walk_to, _walk_duration, TeacherAnimator.Action.LECTURE)
			_wait = _walk_duration + 0.8
		4:
			teacher.set_action(TeacherAnimator.Action.BOOK_FLIP, true)
			_wait = 2.6 + 0.6
	_update_hud()


func _update_hud() -> void:
	if hud == null:
		return
	var mode := "自动轮播" if _auto else "手动"
	hud.text = "教师动作补全 · %d/%d  %s\n数字键 1-5 切换 · A 自动 · R 重播 · 模式：%s" % [
		_index + 1, ACTIONS.size(), LABELS[_index], mode,
	]
