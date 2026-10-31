class_name DigitalClock
extends Node3D

## 将教室电子钟同步到运行机器的本地时间。电子钟只显示小时和分钟，
## 因此每跨过一分钟刷新一次文字即可。

@export var clock_label_path: NodePath = ^"Display"

var _label: Label3D
var _last_minute_key: String = ""


func _ready() -> void:
	_label = get_node_or_null(clock_label_path) as Label3D
	_sync_to_system_time()


func _process(_delta: float) -> void:
	_sync_to_system_time()


func set_display_time(hour: int, minute: int) -> void:
	if _label == null:
		return
	var safe_hour := clampi(hour, 0, 23)
	var safe_minute := clampi(minute, 0, 59)
	_label.text = "%02d:%02d" % [safe_hour, safe_minute]
	_last_minute_key = _label.text


func get_display_text() -> String:
	return _label.text if _label != null else ""


func _sync_to_system_time() -> void:
	if _label == null:
		return
	var now := Time.get_time_dict_from_system(false)
	var minute_key := "%02d:%02d" % [int(now.hour), int(now.minute)]
	if minute_key == _last_minute_key:
		return
	_last_minute_key = minute_key
	_label.text = minute_key
