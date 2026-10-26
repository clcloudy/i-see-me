extends Node3D
## 同学动作演示（缺失动作 7~16，2026-10-24）。
## 数字键 1~9 切换；A 开关自动轮播。截图由 action_shot.gd 调用。

const CLIPS: Array[int] = [
	CharacterAction.Clip.LAUGH_SHAKE,
	CharacterAction.Clip.NOD_FULL,
	CharacterAction.Clip.PICK_PEN,
	CharacterAction.Clip.LOOK_BACK,
	CharacterAction.Clip.HEAD_SHAKE,
	CharacterAction.Clip.DRAW_GRID,
	CharacterAction.Clip.LOWER_BOOK,
	CharacterAction.Clip.WHISPER_LOOP,
	CharacterAction.Clip.QUIET_SETTLE,
	CharacterAction.Clip.DESK_PEN_IDLE,
]
const EXPRESSIONS := [
	"amused", "warm", "neutral", "neutral", "doubt",
	"focused", "neutral", "amused", "neutral", "focused",
]

var character: CharacterAction
var hud: Label
var _index: int = -1
var _auto: bool = true
var _wait: float = 2.0


func _ready() -> void:
	ActionDemoStage.build(self, Vector3(1.65, 1.42, -2.45), Vector3(0, 1.0, -0.08))
	ActionDemoStage.chair(self, Vector3.ZERO)
	ActionDemoStage.desk(self, Vector3(0, 0, -0.52))
	ActionDemoStage.label(self, "同学 · 动作补全", Vector3(0, 2.05, -0.15), 42)
	character = _spawn_character()
	hud = ActionDemoStage.hud(self)
	play_index(0)
	set_process(true)


func _spawn_character() -> CharacterAction:
	var holder := Node3D.new()
	holder.name = "Classmate"
	holder.set_script(load("res://scripts/character_action.gd"))
	# 必须在进入场景树（_ready 应用配色）之前设置。
	holder.set("outfit", 3)
	holder.set("whisper_side", 1)
	# 演示小桌台面 0.74（ActionDemoStage.desk 的桌面 0.72 + 厚 0.04）。
	holder.set("desk_height", 0.74)
	var model: Node3D = load("res://assets/characters/quaternius/Casual2.glb").instantiate()
	model.name = "Model"
	model.rotation_degrees = Vector3(0, 180, 0)
	holder.add_child(model)
	add_child(holder)
	return holder as CharacterAction


func _process(delta: float) -> void:
	if not _auto:
		return
	_wait -= delta
	if _wait <= 0.0:
		play_index((_index + 1) % CLIPS.size())


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_9:
		_auto = false
		play_index(key - KEY_1)
	elif key == KEY_0:
		_auto = false
		play_index(9)
	elif key == KEY_A:
		_auto = not _auto
		_wait = 0.1 if _auto else 1e9
	elif key == KEY_R:
		play_index(_index, true)


func set_clip_index(i: int) -> void:
	_auto = false
	play_index(i)


func seek_clip(seconds: float) -> void:
	if character != null:
		character.warm(seconds, 8)


func set_auto(value: bool) -> void:
	_auto = value
	_wait = 0.1 if value else 1e9


func play_index(i: int, force: bool = false) -> void:
	var idx := clampi(i, 0, CLIPS.size() - 1)
	if idx == _index and not force and character != null and character.clip == CLIPS[idx]:
		return
	_index = idx
	character.play_clip(CLIPS[idx], true)
	character.expression = EXPRESSIONS[idx]
	character.speaking = idx == 7
	var dur := character.get_clip_duration()
	_wait = dur + (0.55 if character.is_looping() else 0.45)
	_update_hud()


func _update_hud() -> void:
	if hud == null:
		return
	var mode := "自动轮播" if _auto else "手动"
	hud.text = "同学动作补全 · %d/%d  %s（%.2fs）\n数字键 1-9 / 0 切换 · A 自动 · R 重播 · 模式：%s" % [
		_index + 1, CLIPS.size(), character.get_clip_label(),
		character.get_clip_duration(), mode,
	]
