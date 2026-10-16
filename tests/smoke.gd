extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_fail("Main scene could not be loaded.")
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	var room := main.get_node_or_null("Room")
	var camera := main.get_node_or_null("Camera3D") as Camera3D
	if room == null or camera == null or not camera.current:
		_fail("Room or active camera missing.")
		return
	for mesh_name in ["Floor", "Ceiling", "BackWall", "FrontWall", "LeftWall", "RightWall"]:
		var mesh := room.get_node_or_null(mesh_name) as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			_fail("Missing room geometry: " + mesh_name)
			return
	if not OS.get_cmdline_user_args().has("--capture"):
		print("PASS: empty room, six surfaces and active camera.")
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		_fail("Capture needs an actual rendering window.")
		return
	DirAccess.make_dir_recursive_absolute("res://.local/captures")
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		DisplayServer.window_set_size(dimensions)
		root.size = dimensions
		for frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			_fail("Rendered viewport is empty.")
			return
		var darkest := 1.0
		var lightest := 0.0
		for y in range(0, image.get_height(), 12):
			for x in range(0, image.get_width(), 12):
				var brightness := image.get_pixel(x, y).get_luminance()
				darkest = minf(darkest, brightness)
				lightest = maxf(lightest, brightness)
		if lightest - darkest < 0.08:
			_fail("Viewport lacks visible room contrast.")
			return
		var output := "res://.local/captures/room-%dx%d.png" % [dimensions.x, dimensions.y]
		if image.save_png(output) != OK:
			_fail("Could not save viewport image.")
			return
		print("PASS: rendered %dx%d; contrast %.3f." % [dimensions.x, dimensions.y, lightest - darkest])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
