extends Node3D
## L3 的世界文字陈列；位置固定，只向流程请求镜头，不自行推进阶段。
signal focus_requested(position: Vector3, target: Vector3)
var settings: Dictionary
var groups: Dictionary = {}
var stops: Array = []
var current := -1
var first := 0
var last := 0
var moving := false

func setup(config: Dictionary) -> void:
	settings = config
	add_to_group(&"dialogue_fx")
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	visible = not get_tree().paused

func clear() -> void:
	for child in get_children():
		child.hide()
		child.queue_free()
	groups.clear()
	stops.clear()
	current = -1
	moving = false

func present(key: String, heading: String, text: String) -> void:
	if not groups.has(key):
		var start := stops.size()
		for paragraph in text.split("\n\n", false):
			var remaining := str(paragraph)
			while not remaining.is_empty():
				var count := mini(int(settings["characters_per_stop"]), remaining.length())
				# 优先在完整句子后分段，长原话仍逐字保留。
				if count < remaining.length():
					var boundary := remaining.left(count).rfind("。")
					if boundary >= count / 2:
						count = boundary + 1
				_add_stop(heading, remaining.left(count))
				remaining = remaining.substr(count)
		groups[key] = Vector2i(start, stops.size() - 1)
	var range_value: Vector2i = groups[key]
	first = range_value.x
	last = range_value.y
	_focus(first)

func _add_stop(heading: String, text: String) -> void:
	var number := stops.size()
	var root := Node3D.new()
	root.name = "Passage%d" % number
	add_child(root)
	root.position = Vector3((-1.0 if number % 2 == 0 else 1.0) * float(settings["side_offset"]), float(settings["height"]), float(settings["start_z"]) - number * float(settings["depth_step"]))
	var title := _label(heading, 28, Color(0.69, 0.80, 0.78))
	title.position.y = 0.78
	root.add_child(title)
	var body := _label(text, 40, Color(0.95, 0.92, 0.83))
	root.add_child(body)
	stops.append({"root": root, "title": title, "body": body, "heading": heading})

func _label(text: String, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.0032
	label.width = 880
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = color
	label.outline_size = 4
	label.outline_modulate = Color(0.05, 0.06, 0.065)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	# 在 L3 后处理之后绘制，同时保留世界中的深度与透视。
	label.render_priority = 6
	label.outline_render_priority = 5
	return label

func step(direction: int) -> void:
	if moving:
		return
	_focus(clampi(current + direction, first, last))

func _focus(next: int) -> void:
	current = next
	moving = true
	for i in range(stops.size()):
		var passage: Dictionary = stops[i]
		passage["root"].visible = i >= current and i <= current + 1
		passage["title"].modulate.a = 1.0 if i == current else 0.28
		passage["title"].text = str(passage["heading"]) + (" · %d / %d" % [current - first + 1, last - first + 1] if i == current else "")
		passage["body"].visible = i == current
	var target: Vector3 = stops[current]["root"].global_position
	# 直视当前文字；它在移动期间始终留在原世界坐标，远处保留真实透视。
	focus_requested.emit(target + Vector3(0, 0, float(settings["camera_distance"])), target)

func arrived() -> void:
	moving = false
