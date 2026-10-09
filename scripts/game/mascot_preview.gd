extends Control

var portrait_viewport: SubViewport

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 345)
	resized.connect(queue_redraw)
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	portrait_viewport = SubViewport.new()
	portrait_viewport.name = "MappoPortrait"
	portrait_viewport.size = Vector2i(700, 480)
	portrait_viewport.transparent_bg = true
	portrait_viewport.own_world_3d = true
	portrait_viewport.msaa_3d = Viewport.MSAA_4X
	portrait_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(portrait_viewport)
	var world := Node3D.new()
	portrait_viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ccd2d5")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var camera := Camera3D.new()
	camera.name = "PortraitCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.35
	camera.current = true
	world.add_child(camera)
	camera.position = Vector3(1.8, 1.7, -4.4)
	camera.look_at(Vector3(0, 0.8, -0.1))
	_add_light(world, Vector3(-3, 4, -5), Color("fff4e6"), 1.55)
	_add_light(world, Vector3(3, 2, -3), Color("dce6ff"), 0.6)
	_add_light(world, Vector3(-1, 3, 4), Color("cde5df"), 0.65)
	var packed: PackedScene = load("res://scenes/mascot/mascot_dog.tscn")
	if packed:
		var mappo := packed.instantiate()
		mappo.name = "Mappo"
		mappo.set("animate", true)
		world.add_child(mappo)
	var plinth := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.88
	disc.bottom_radius = 0.88
	disc.height = 0.04
	disc.radial_segments = 48
	plinth.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("183c40")
	material.roughness = 0.9
	plinth.material_override = material
	plinth.position.y = -0.03
	world.add_child(plinth)

func _add_light(world: Node3D, from: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	world.add_child(light)
	light.position = from
	light.look_at(Vector3(0, 0.7, 0))

func _draw() -> void:
	var center := size * Vector2(0.5, 0.49)
	var radius := minf(size.x * 0.29, size.y * 0.42)
	draw_arc(center, radius, 0, TAU, 96, KennelUI.MINT.darkened(0.65), 2, true)
	draw_arc(center, radius * 1.16, -0.4, 2.4, 64, KennelUI.MINT.darkened(0.8), 2, true)
	draw_circle(center + Vector2(radius, 0).rotated(-0.5), 8, KennelUI.GOLD)
