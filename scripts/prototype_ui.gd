class_name PrototypeUI
extends CanvasLayer

signal advance_requested
signal pause_requested
signal mute_requested
signal skip_requested
signal restart_requested
signal quit_requested

var _copy: Dictionary
var _stage: StringName = &"intro"

@onready var stage_title: Label = %StageTitle
@onready var stage_body: Label = %StageBody
@onready var continue_button: Button = %Continue
@onready var pause_button: Button = %Pause
@onready var mute_button: Button = %Mute
@onready var skip_button: Button = %Skip
@onready var restart_button: Button = %Restart
@onready var quit_button: Button = %Quit
@onready var modal: Control = %Modal
@onready var modal_title: Label = %ModalTitle
@onready var modal_body: Label = %ModalBody
@onready var modal_primary: Button = %ModalPrimary
@onready var modal_restart: Button = %ModalRestart
@onready var modal_quit: Button = %ModalQuit


func _ready() -> void:
	continue_button.pressed.connect(func() -> void: advance_requested.emit())
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	mute_button.pressed.connect(func() -> void: mute_requested.emit())
	skip_button.pressed.connect(func() -> void: skip_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	modal_primary.pressed.connect(_on_modal_primary)
	modal_restart.pressed.connect(func() -> void: restart_requested.emit())
	modal_quit.pressed.connect(func() -> void: quit_requested.emit())


func configure(content: Dictionary) -> void:
	_copy = content
	%Brand.text = content["ui"]["brand"]
	%Prototype.text = content["ui"]["prototype"]
	skip_button.text = _text("skip")
	restart_button.text = _text("restart")
	quit_button.text = _text("quit")
	modal_restart.text = _text("restart")
	modal_quit.text = _text("quit")


func present(stage: StringName, transitioning: bool, paused: bool, muted: bool) -> void:
	_stage = stage
	var stage_copy: Dictionary = _copy["stages"][String(stage)]
	stage_title.text = stage_copy["title"]
	stage_body.text = stage_copy["body"]
	continue_button.text = _text("finish" if stage == &"l3" else "next")
	continue_button.disabled = transitioning
	continue_button.visible = not transitioning and stage in [&"l1", &"l2", &"l3"]
	skip_button.visible = transitioning
	pause_button.text = _text("resume" if paused else "pause")
	mute_button.text = _text("unmute" if muted else "mute")
	%Transition.text = _text("transition") if transitioning else ""
	pause_button.disabled = stage in [&"intro", &"complete"]
	var show_card := paused or stage in [&"intro", &"complete"]
	modal.visible = show_card
	%StagePanel.visible = not show_card
	modal_restart.visible = paused
	if paused:
		modal_title.text = _text("paused_title")
		modal_body.text = _text("paused_body")
		modal_primary.text = _text("resume")
	else:
		modal_title.text = stage_copy["title"]
		modal_body.text = stage_copy["body"]
		modal_primary.text = _text("start" if stage == &"intro" else "replay")


func focus_primary() -> void:
	if modal.visible:
		modal_primary.grab_focus()
	elif not continue_button.disabled:
		continue_button.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		pause_requested.emit()
		get_viewport().set_input_as_handled()


func _on_modal_primary() -> void:
	if get_tree().paused:
		pause_requested.emit()
	elif _stage == &"complete":
		restart_requested.emit()
	else:
		advance_requested.emit()


func _text(key: String) -> String:
	return _copy["ui"][key]
