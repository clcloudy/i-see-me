extends Node
## 教师动效演示驱动（2026-10-23）。挂在课堂预览场景根下的 Demo 节点上：
## 自动轮播动作/情绪，同时支持键盘手动切换，便于肉眼检查全部组合。
##   1~4：讲课 / 提问 / 点名 / 板书
##   Q W E R T：普通 / 激昂 / 失落 / 疑惑 / 开心
##   S：开关说话口型
##   空格：暂停/继续动效；A：开关自动轮播
## 该脚本只是演示工具，正式流程请直接调用 TeacherAnimator 的 set_action/set_state。

@export var teacher_path: NodePath
@export var auto_cycle: bool = true
@export var action_interval: float = 6.0
@export var emotion_interval: float = 3.5
@export var hud_path: NodePath

var _teacher: TeacherAnimator
var _label: Label
var _action_timer: float = 0.0
var _emotion_timer: float = 0.0


func _ready() -> void:
	_teacher = get_node_or_null(teacher_path) as TeacherAnimator
	_label = get_node_or_null(hud_path) as Label
	if _teacher == null:
		push_error("TeacherAnimDemo: teacher_path is empty or invalid.")
		return
	_teacher.action_changed.connect(_on_state_changed)
	_teacher.emotion_changed.connect(_on_state_changed)
	_refresh()


func _process(delta: float) -> void:
	if _teacher == null or not auto_cycle or not _teacher.playing:
		return
	_action_timer += delta
	_emotion_timer += delta
	if _action_timer >= action_interval:
		_action_timer = 0.0
		_teacher.cycle_action()
	if _emotion_timer >= emotion_interval:
		_emotion_timer = 0.0
		_teacher.cycle_emotion()


func _unhandled_input(event: InputEvent) -> void:
	if _teacher == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_teacher.set_action(0)
		KEY_2:
			_teacher.set_action(1)
		KEY_3:
			_teacher.set_action(2)
		KEY_4:
			_teacher.set_action(3)
		KEY_Q:
			_teacher.set_emotion(0)
		KEY_W:
			_teacher.set_emotion(1)
		KEY_E:
			_teacher.set_emotion(2)
		KEY_R:
			_teacher.set_emotion(3)
		KEY_T:
			_teacher.set_emotion(4)
		KEY_S:
			_teacher.talking = not _teacher.talking
		KEY_SPACE:
			_teacher.playing = not _teacher.playing
		KEY_A:
			auto_cycle = not auto_cycle
			_action_timer = 0.0
			_emotion_timer = 0.0
		_:
			return
	if key.keycode >= KEY_1 and key.keycode <= KEY_4:
		# 手动选动作后先暂停自动轮播，避免几秒后被切走。
		auto_cycle = false
	_refresh()


func _on_state_changed(_value: int) -> void:
	_refresh()


func _refresh() -> void:
	if _label == null or _teacher == null:
		return
	var action_name: String = _teacher.get_action_label()
	var emotion_name: String = _teacher.get_emotion_label()
	_label.text = "教师动效演示\n动作：%s    情绪：%s    说话：%s    播放：%s\n1-4 动作 | QWERT 情绪 | S 说话 | 空格 暂停 | A 自动轮播（%s）" % [
		action_name,
		emotion_name,
		"开" if _teacher.talking else "关",
		"开" if _teacher.playing else "暂停",
		"开" if auto_cycle else "关",
	]
