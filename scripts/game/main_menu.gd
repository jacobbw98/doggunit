extends Control

var seed_input: LineEdit
var launch_button: Button

func _ready() -> void:
	get_tree().paused = false
	GameManager.current_state = GameManager.GameState.MENU
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = KennelUI.make_theme()
	var background := ColorRect.new()
	background.color = KennelUI.INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 80)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 100)
	margin.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(KennelUI.label("A VERY GOOD DOG. A VERY WEIRD UNIVERSE.", 18, KennelUI.MINT))
	left.add_child(KennelUI.label("DOGGUN'IT", 104))
	left.add_child(KennelUI.label("FETCH. FIGHT. FOLD SPACE.", 30, KennelUI.GOLD))
	left.add_child(KennelUI.label("Walk around tiny worlds. Step through impossible doors.\nBuild a wildly irresponsible pack of superpowered pups.", 24))
	left.add_child(KennelUI.label("3 floors  /  3 alpha encounters  /  1 very strange walk", 18, Color("9bb2bd")))
	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Run seed (optional)"
	seed_input.custom_minimum_size = Vector2(480, 52)
	seed_input.max_length = 10
	seed_input.tooltip_text = "Use the same positive number to replay a layout. Leave blank for a new walk."
	left.add_child(seed_input)
	launch_button = KennelUI.button("LET'S GO FOR A WALK   →", _start_run)
	left.add_child(launch_button)
	left.add_child(KennelUI.button("QUIT TO DESKTOP", func(): get_tree().quit()))
	left.add_child(KennelUI.label("BEST %d    •    %d WALKS    •    %d VICTORIES" % [GameManager.best_score, GameManager.completed_runs, GameManager.victories], 18, KennelUI.MINT))
	launch_button.grab_focus()
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 510
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	var mascot: Control = load("res://scripts/game/mascot_preview.gd").new()
	mascot.name = "MappoPreview"
	mascot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(mascot)
	var mappo_caption := KennelUI.label("MAPPO  /  YOUR VERY GOOD STARTER", 18, KennelUI.MINT)
	mappo_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(mappo_caption)
	right.add_child(KennelUI.label("THE WALKER'S FIELD GUIDE", 24, KennelUI.GOLD))
	right.add_child(KennelUI.label("WASD    Move                 MOUSE    Look\nSPACE    Jump / bunny hop\nCTRL / C  Slide                  LEFT CLICK    Bark\n1 / 2 / 3  Swap pups         R    Reload\nF    Buy / use                     E    Active item\nG    Throw bomb                Q    Sniff     ESC    Pause", 21))
	right.add_child(KennelUI.label("Walk into free pedestal items. F buys items or uses slots.\nGlobal treats help your pack; dog treats stay with one pup.", 20, Color("9bb2bd")))
	for child in right.get_children():
		if child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			child.custom_minimum_size.x = 510

func _start_run() -> void:
	var value := seed_input.text.strip_edges()
	if not value.is_empty() and (not value.is_valid_int() or int(value) <= 0 or int(value) > 2147483647):
		seed_input.text = ""
		seed_input.placeholder_text = "Enter 1–2147483647, or leave blank"
		seed_input.grab_focus()
		return
	launch_button.disabled = true
	GameManager.run_seed = int(value) if not value.is_empty() else 0
	get_tree().change_scene_to_file("res://scenes/levels/procedural_level.tscn")
