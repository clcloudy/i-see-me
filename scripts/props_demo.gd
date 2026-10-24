extends Node3D
## 道具演示（缺失动作 22~24，2026-10-24）：桌边滚落的笔、讲台课本与粉笔盒、
## 画方格同学的铅笔/橡皮/本子。全部为程序化网格，无外部素材。

func _ready() -> void:
	ActionDemoStage.build(self, Vector3(0.28, 1.24, 1.34), Vector3(0, 0.83, 0.0))
	ActionDemoStage.desk(self, Vector3(0, 0, 0.0), Vector3(1.95, 0.045, 0.72))
	var hud := ActionDemoStage.hud(self)
	hud.text = "课堂道具 · 22~24
笔（PICK_PEN）/ 讲台课本 + 粉笔盒 / 铅笔 + 橡皮 + 本子（DRAW_GRID）"

	# 22 笔：平放在桌面上，笔尖朝 +X
	var pen := PropKit.pen()
	add_child(pen)
	pen.position = Vector3(-0.56, 0.748, 0.14)
	_add_label("22 笔", Vector3(-0.56, 0.92, 0.20))

	# 23 讲台课本 + 粉笔盒
	var book := PropKit.textbook()
	add_child(book)
	book.position = Vector3(-0.20, 0.758, -0.02)
	book.rotation_degrees = Vector3(-7.0, -10.0, 0.0)
	_add_label("23 课本", Vector3(-0.20, 0.92, 0.04))

	var box := PropKit.chalk_box()
	add_child(box)
	box.position = Vector3(0.14, 0.747, 0.05)
	box.rotation_degrees.y = 14.0
	_add_label("23 粉笔盒", Vector3(0.14, 0.92, 0.10))

	# 24 本子 + 铅笔 + 橡皮
	var notebook := PropKit.notebook()
	add_child(notebook)
	notebook.position = Vector3(0.48, 0.750, -0.04)
	notebook.rotation_degrees = Vector3(-6.0, 8.0, 0.0)
	_add_label("24 本子+铅笔", Vector3(0.48, 0.92, 0.04))

	var pencil := PropKit.pencil()
	add_child(pencil)
	pencil.position = Vector3(0.42, 0.778, 0.12)
	pencil.rotation_degrees.y = -12.0

	var eraser := PropKit.eraser()
	add_child(eraser)
	eraser.position = Vector3(0.62, 0.764, 0.14)
	eraser.rotation_degrees.y = 22.0


func _add_label(text: String, pos: Vector3) -> void:
	var l := ActionDemoStage.label(self, text, pos, 20, Color(0.10, 0.14, 0.20))
	l.pixel_size = 0.0022
