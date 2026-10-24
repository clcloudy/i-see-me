class_name DialogueUI
extends CanvasLayer

## 课堂对话界面（主开发，2026-10-24）。
## 组成：顶部控制条（暂停/静音/跳过/重开/退出）、底部字幕条、右侧词条 chip、
## 分支选择面板（输入回答 / 躲避视线）、L2 词条卡片与内容提示/暂停/完成弹窗。
## 界面只发信号，不推进剧情；全部按钮在暂停时仍可操作（process_mode=ALWAYS）。

signal advance_requested ## 跳过当前节拍 / 下一张词条卡
signal pause_requested
signal mute_requested
signal restart_requested
signal quit_requested
signal answer_submitted(text: String) ## 玩家输入并提交的回答
signal avoid_chosen ## 玩家选择躲避视线

const SPEAKER_COLORS := {
	&"teacher": Color(0.98, 0.83, 0.55),
	&"protagonist": Color(0.62, 0.86, 0.99),
	&"classmate": Color(0.80, 0.88, 0.78),
	&"stage": Color(0.66, 0.68, 0.70),
}

var _copy: Dictionary = {}
var _muted: bool = false
var _paused: bool = false
## 词条 chip 记录：{"chip": Control, "done": bool}。用字典而不是直接捕获节点，
## 避免提前淡出的 chip 被释放后，未决的持有计时仍调用其回调（捕获已释放对象会报错）。
var _chip_records: Array[Dictionary] = []

@onready var brand: Label = %Brand
@onready var skip_button: Button = %Skip
@onready var pause_button: Button = %Pause
@onready var mute_button: Button = %Mute
@onready var restart_button: Button = %Restart
@onready var quit_button: Button = %Quit
@onready var subtitle_bar: PanelContainer = %SubtitleBar
@onready var speaker_label: Label = %Speaker
@onready var line_label: Label = %Line
@onready var chips: VBoxContainer = %Chips
@onready var choice_panel: PanelContainer = %ChoicePanel
@onready var choice_title: Label = %ChoiceTitle
@onready var answer_button: Button = %AnswerButton
@onready var avoid_button: Button = %AvoidButton
@onready var input_row: HBoxContainer = %InputRow
@onready var input: LineEdit = %Input
@onready var submit_button: Button = %Submit
@onready var input_back: Button = %InputBack
@onready var card_panel: PanelContainer = %CardPanel
@onready var card_title: Label = %CardTitle
@onready var card_body: Label = %CardBody
@onready var card_primary: Button = %CardPrimary
@onready var card_restart: Button = %CardRestart
@onready var card_quit: Button = %CardQuit
@onready var transition_label: Label = %Transition


func _ready() -> void:
	skip_button.pressed.connect(func() -> void: advance_requested.emit())
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	mute_button.pressed.connect(func() -> void: mute_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	answer_button.pressed.connect(_on_answer_button)
	avoid_button.pressed.connect(func() -> void: avoid_chosen.emit())
	submit_button.pressed.connect(_on_submit)
	input_back.pressed.connect(_show_choice_buttons)
	input.text_submitted.connect(func(_t: String) -> void: _on_submit())
	card_primary.pressed.connect(_on_card_primary)
	card_restart.pressed.connect(func() -> void: restart_requested.emit())
	card_quit.pressed.connect(func() -> void: quit_requested.emit())


func configure(content: Dictionary) -> void:
	_copy = content.get("ui", {})
	brand.text = _text("brand")
	skip_button.text = _text("skip")
	pause_button.text = _text("pause")
	mute_button.text = _text("mute")
	restart_button.text = _text("restart")
	quit_button.text = _text("quit")


## ——— 字幕 ———

func set_subtitle(speaker: String, text: String) -> void:
	subtitle_bar.visible = true
	speaker_label.text = speaker
	speaker_label.add_theme_color_override(
		"font_color", SPEAKER_COLORS.get(StringName(speaker), Color(0.85, 0.86, 0.84))
	)
	line_label.text = text


func clear_subtitle() -> void:
	subtitle_bar.visible = false
	line_label.text = ""


## ——— 词条 chip（L1 事件感受，出现数秒后淡出） ———

func show_chip(title: String, body: String) -> void:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.085, 0.08, 0.82)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	chip.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title_label := Label.new()
	title_label.text = "第二层 · " + title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.66, 0.78, 0.72))
	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 17)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	box.add_child(body_label)
	chip.add_child(box)
	chip.modulate = Color(1, 1, 1, 0)
	chips.add_child(chip)
	var record := {"chip": chip, "done": false}
	_chip_records.append(record)
	if _chip_records.size() > 3:
		_retire_chip(_chip_records[0])
	var tween := create_tween()
	tween.tween_property(chip, "modulate:a", 1.0, 0.25)
	var hold := get_tree().create_timer(3.6, true) # 暂停时也计时，避免恢复后堆叠
	hold.timeout.connect(func() -> void:
		if not bool(record.get("done", true)):
			_retire_chip(record)
	)


func _retire_chip(record: Dictionary) -> void:
	if bool(record.get("done", true)):
		return
	record["done"] = true
	var chip: Control = record.get("chip")
	_chip_records.erase(record)
	if chip != null and is_instance_valid(chip):
		var tween := create_tween()
		tween.tween_property(chip, "modulate:a", 0.0, 0.5)
		tween.tween_callback(chip.queue_free)


## ——— 分支选择 ———

func show_choice(choice: Dictionary) -> void:
	subtitle_bar.visible = false
	card_panel.visible = false
	choice_panel.visible = true
	choice_title.text = str(choice.get("title", ""))
	answer_button.text = str(choice.get("answer_button", ""))
	avoid_button.text = str(choice.get("avoid_button", ""))
	submit_button.text = str(choice.get("input_submit", ""))
	input_back.text = str(choice.get("input_back", ""))
	input.placeholder_text = str(choice.get("input_placeholder", ""))
	input.text = ""
	_show_choice_buttons()


func _show_choice_buttons() -> void:
	answer_button.visible = true
	avoid_button.visible = true
	input_row.visible = false
	answer_button.grab_focus()


func _on_answer_button() -> void:
	answer_button.visible = false
	avoid_button.visible = false
	input_row.visible = true
	input.grab_focus()


func _on_submit() -> void:
	answer_submitted.emit(input.text)


func hide_choice() -> void:
	choice_panel.visible = false


## ——— L2 词条卡片 / 内容提示 / 暂停 / 完成 ———

func show_card(title: String, body: String) -> void:
	subtitle_bar.visible = false
	card_panel.visible = true
	card_title.text = title
	card_body.text = body
	card_primary.visible = false
	card_restart.visible = false
	card_quit.visible = false


func hide_card() -> void:
	card_panel.visible = false


func show_intro() -> void:
	clear_subtitle()
	hide_choice()
	card_panel.visible = true
	card_title.text = _text("intro_title")
	card_body.text = _text("intro_body")
	card_primary.visible = true
	card_primary.text = _text("intro_primary")
	card_restart.visible = false
	card_quit.visible = true
	card_primary.grab_focus()


func show_complete() -> void:
	clear_subtitle()
	card_panel.visible = true
	card_title.text = _text("complete_title")
	card_body.text = _text("complete_body")
	card_primary.visible = true
	card_primary.text = _text("complete_primary")
	card_restart.visible = false
	card_quit.visible = true
	card_primary.grab_focus()


func show_paused(paused: bool) -> void:
	_paused = paused
	if paused:
		card_panel.visible = true
		card_title.text = _text("paused_title")
		card_body.text = _text("paused_body")
		card_primary.visible = true
		card_primary.text = _text("resume")
		card_restart.visible = true
		card_quit.visible = true
		card_primary.grab_focus()
	else:
		# 恢复：由流程决定接下来显示哪一层
		card_panel.visible = false


func set_transition_text(text: String) -> void:
	transition_label.text = text
	transition_label.visible = not text.is_empty()


## ——— 控制条状态 ———

func present_controls(paused: bool, muted: bool, skip_enabled: bool) -> void:
	_paused = paused
	_muted = muted
	pause_button.text = _text("resume" if paused else "pause")
	mute_button.text = _text("unmute" if muted else "mute")
	skip_button.disabled = not skip_enabled
	skip_button.visible = skip_enabled


func focus_primary() -> void:
	if card_panel.visible and card_primary.visible:
		card_primary.grab_focus()
	elif choice_panel.visible:
		if input_row.visible:
			input.grab_focus()
		else:
			answer_button.grab_focus()


func _on_card_primary() -> void:
	if _paused:
		pause_requested.emit()
	elif card_title.text == _text("complete_title"):
		restart_requested.emit()
	else:
		advance_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		pause_requested.emit()
		get_viewport().set_input_as_handled()


func _text(key: String) -> String:
	return str(_copy.get(key, key))
