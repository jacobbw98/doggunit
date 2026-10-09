extends CanvasLayer

var run: RunManager
var root: Control
var overlay: ColorRect
var content: VBoxContainer
var status: Label
var hint: Label
var boss_label: Label
var boss_bar: ProgressBar
var modal: String = ""
var currency: Label
var active_name: Label
var active_status: Label
var interaction: Label
var item_details: PanelContainer
var item_description: Label
var item_scope: Label
var pickup_notice: Label
var notice_remaining := 0.0
const LOOK_ALIGNMENT := 0.92

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 12
	run = get_tree().get_first_node_in_group("run_manager")
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = KennelUI.make_theme()
	add_child(root)
	status = KennelUI.label("", 20)
	status.position = Vector2(24, 125)
	root.add_child(status)
	currency = KennelUI.label("", 23, KennelUI.GOLD)
	currency.position = Vector2(24, 190)
	root.add_child(currency)
	var active_slot := PanelContainer.new()
	root.add_child(active_slot)
	active_slot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	active_slot.offset_left = 24
	active_slot.offset_right = 370
	active_slot.offset_top = -200
	active_slot.offset_bottom = -102
	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.035, 0.07, 0.09, 0.88)
	slot_style.border_color = KennelUI.MINT
	slot_style.set_border_width_all(2)
	slot_style.set_content_margin_all(12)
	active_slot.add_theme_stylebox_override("panel", slot_style)
	var slot_contents := VBoxContainer.new()
	slot_contents.add_theme_constant_override("separation", 4)
	active_slot.add_child(slot_contents)
	slot_contents.add_child(KennelUI.label("E  /  ACTIVE ITEM", 16, KennelUI.MINT))
	active_name = KennelUI.label("Empty slot", 21)
	slot_contents.add_child(active_name)
	active_status = KennelUI.label("Find an active item on a pedestal", 16)
	slot_contents.add_child(active_status)
	pickup_notice = KennelUI.label("", 23, KennelUI.MINT)
	pickup_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	pickup_notice.position = Vector2(-430, 90)
	pickup_notice.custom_minimum_size.x = 860
	root.add_child(pickup_notice)
	hint = KennelUI.label("", 20, KennelUI.MINT)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(24, -82)
	root.add_child(hint)
	var minimap := RoomMinimap.new()
	root.add_child(minimap)
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -354
	minimap.offset_right = -24
	minimap.offset_top = 24
	minimap.offset_bottom = 299
	item_details = PanelContainer.new()
	root.add_child(item_details)
	item_details.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	item_details.offset_left = -354
	item_details.offset_right = -24
	item_details.offset_top = 311
	item_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var details_style := StyleBoxFlat.new()
	details_style.bg_color = Color(0.035, 0.07, 0.09, 0.92)
	details_style.border_color = KennelUI.MINT
	details_style.set_border_width_all(1)
	details_style.set_content_margin_all(14)
	item_details.add_theme_stylebox_override("panel", details_style)
	var details_content := VBoxContainer.new()
	details_content.add_theme_constant_override("separation", 8)
	item_details.add_child(details_content)
	interaction = KennelUI.label("", 22, KennelUI.GOLD)
	interaction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_content.add_child(interaction)
	item_scope = KennelUI.label("", 17, KennelUI.MINT)
	item_scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_content.add_child(item_scope)
	item_description = KennelUI.label("", 20)
	item_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_content.add_child(item_description)
	item_details.hide()
	var boss_box := VBoxContainer.new()
	root.add_child(boss_box)
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -280
	boss_box.offset_right = 280
	boss_box.offset_top = 28
	boss_box.custom_minimum_size.x = 560
	boss_label = KennelUI.label("", 22, KennelUI.GOLD)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(560, 18)
	boss_bar.show_percentage = false
	boss_box.add_child(boss_bar)
	boss_bar.hide()
	overlay = ColorRect.new()
	overlay.color = Color(0.025, 0.055, 0.085, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	content = VBoxContainer.new()
	content.custom_minimum_size.x = 1000
	center.add_child(content)
	overlay.hide()
	run.pickup_message.connect(_show_pickup_notice)
	run.floor_completed.connect(_show_floor_complete)
	GameManager.run_ended.connect(_show_end)

func _process(delta: float) -> void:
	if not run:
		return
	status.text = run.get_status_text()
	currency.text = "BONES  %d     BOMBS  %d     KEYS  %d" % [run.bones, run.bombs, run.keys]
	active_name.text = run.active_item.get("name", "Empty slot")
	active_status.text = run.get_active_status()
	notice_remaining = maxf(0.0, notice_remaining - delta)
	pickup_notice.visible = notice_remaining > 0.0 and modal.is_empty()
	interaction.text = ""
	item_description.text = ""
	item_scope.text = ""
	item_details.hide()
	if modal.is_empty() and not run.loading and GameManager.current_state == GameManager.GameState.PLAYING:
		var target := _find_interactable()
		if is_instance_valid(target):
			item_details.show()
			var manual: bool = not target.has_method("requires_interaction") or target.requires_interaction()
			interaction.text = ("F  /  " if manual else "") + target.get_interaction_text(run)
			if target is ItemPedestal:
				item_details.custom_minimum_size.y = 220
				item_description.text = str(target.item.get("description", ""))
				var flavor := str(target.item.get("flavor_text", ""))
				if not flavor.is_empty():
					item_description.text += "\n" + flavor
				item_scope.text = PetItems.category_name(target.item)
				item_scope.text += " · " + str(target.item.get("rarity", "common")).capitalize()
				if target.item.get("category", -1) == PetItems.Category.DOG_INCLUSIVE:
					var selected: Gun = run.player.weapon_manager.get_current_gun()
					if is_instance_valid(selected):
						item_scope.text = "For " + selected.stats.get_display_name()
			elif target is DogGunPickup and is_instance_valid(target.gun):
				item_details.custom_minimum_size.y = 220
				var dog_stats: GunStats = target.gun.stats
				item_description.text = dog_stats.description + "\n" + dog_stats.flavor_text
				item_scope.text = "%s · %s · %.0f damage · %.2fs between shots · %.2fs reload" % [GunTypes.get_rarity_name(dog_stats.rarity), GunTypes.get_type_name(dog_stats.gun_type), dog_stats.get_scaled_damage(), dog_stats.fire_rate, dog_stats.get_reload_seconds()]
			else:
				item_details.custom_minimum_size.y = 68
		elif _can_leave_floor():
			item_details.custom_minimum_size.y = 100
			item_details.show()
			interaction.text = "F  /  " + ("Finish the walk" if run.current_floor >= run.max_floors else "Leave for the next dimension")
	item_scope.visible = not item_scope.text.is_empty()
	item_description.visible = not item_description.text.is_empty()
	if item_details.visible:
		# Wrapping changes the labels' minimum height after their text updates.
		# Apply it now so the panel contains the full effect and flavor text.
		item_details.size.y = item_details.get_combined_minimum_size().y
	var trail: String = run.generator.get_secret_hint() if not run.loading else ""
	hint.text = "WALK INTO ITEMS    •    F  DOGS / SHOP / SLOTS / LOCKS    •    E  ACTIVE    •    G  BOMB\nR  RELOAD    •    Q  SNIFF: %s    •    ESC  PAUSE" % ("ON" if run.generator.secret_scan_enabled else "OFF")
	if not trail.is_empty():
		hint.text += "\n" + trail
	boss_label.text = ""
	boss_bar.hide()
	for boss in get_tree().get_nodes_in_group("bosses"):
		if boss.get_meta("encounter_room", -1) != run.current_room_id or boss.current_health <= 0:
			continue
		boss_label.text = "%s  •  %s" % [boss.display_name.to_upper(), "ENRAGED" if boss.boss_phase > 1 else "ALPHA"]
		boss_bar.max_value = boss.max_health
		boss_bar.value = boss.current_health
		boss_bar.show()
		break

func _input(event: InputEvent) -> void:
	var console = get_tree().get_first_node_in_group("debug_console")
	if console and console.is_open:
		return
	if modal.is_empty() and not run.loading and GameManager.current_state == GameManager.GameState.PLAYING:
		if event.is_action_pressed("interact"):
			var target := _find_interactable(true)
			if is_instance_valid(target):
				target.interact(run)
			elif _can_leave_floor():
				run.request_floor_exit()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("use_active"):
			run.activate_item()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("use_bomb"):
			run.use_bomb()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if modal == "pause":
			_resume()
		elif modal.is_empty() and GameManager.current_state == GameManager.GameState.PLAYING:
			GameManager.pause_game()
			_show_pause()
	elif event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_Q or event.keycode == KEY_Q):
		if modal.is_empty() and not run.loading:
			run.generator.set_secret_scan_enabled(not run.generator.secret_scan_enabled)
			get_viewport().set_input_as_handled()

func _begin_modal(kind: String, title: String, subtitle: String) -> void:
	modal = kind
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	content.add_child(KennelUI.label("DOGGUN'IT   /   FLOOR %d" % run.current_floor, 18, KennelUI.MINT))
	content.add_child(KennelUI.label(title, 46))
	content.add_child(KennelUI.label(subtitle, 23, KennelUI.GOLD))
	overlay.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_pickup_notice(text: String) -> void:
	pickup_notice.text = text
	notice_remaining = 3.5

func _can_leave_floor() -> bool:
	var room = run.generator.get_room(run.current_room_id)
	return run.floor_won and is_instance_valid(room) and room.room_type == LevelGenerator.ROOM_BOSS

func _find_interactable(manual_only: bool = false) -> Node3D:
	if not is_instance_valid(run.player):
		return null
	var best: Node3D
	var best_score := INF
	var camera: Camera3D = run.player.camera
	for candidate in get_tree().get_nodes_in_group("item_interactables"):
		if not candidate is Node3D or not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
			continue
		if candidate.get_meta("room_id", candidate.get("room_id")) != run.current_room_id:
			continue
		if manual_only and candidate.has_method("requires_interaction") and not candidate.requires_interaction():
			continue
		if not candidate.is_visible_in_tree() or candidate.get_interaction_text(run).is_empty():
			continue
		var offset: Vector3 = RoomEconomy.interaction_position(candidate) - camera.global_position
		var distance := offset.length()
		var facing: float = (-camera.global_basis.z).dot(offset.normalized())
		if facing < LOOK_ALIGNMENT:
			continue
		var score: float = distance + (1.0 - facing) * 20.0
		if score < best_score:
			best_score = score
			best = candidate
	return best

func _show_pause() -> void:
	_begin_modal("pause", "TAKING A BREATHER.", "Your pack and your run are waiting right here.")
	var resume_button := KennelUI.button("BACK TO THE WALK", _resume)
	content.add_child(resume_button)
	resume_button.grab_focus()
	var items: Array[String] = []
	for item in run.run_modifiers:
		var scope := PetItems.category_name(item)
		if item.get("category", -1) == PetItems.Category.DOG_INCLUSIVE:
			var gun = instance_from_id(item.get("gun_id", 0)) if item.get("gun_id", 0) > 0 else null
			scope = gun.stats.get_display_name() if is_instance_valid(gun) and gun.stats else "Selected pup"
		items.append("%s [%s]" % [item.name, scope])
	var inventory := KennelUI.label("PASSIVES: " + (", ".join(items) if not items.is_empty() else "None yet. Find treats on room pedestals."), 20)
	inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory.custom_minimum_size.x = 980
	content.add_child(inventory)
	content.add_child(KennelUI.label("ACTIVE: %s   ·   BONES %d   ·   BOMBS %d   ·   KEYS %d" % [run.active_item.get("name", "Empty"), run.bones, run.bombs, run.keys], 20, KennelUI.MINT))
	content.add_child(KennelUI.button("END WALK & RETURN TO MENU", _to_menu))

func _resume() -> void:
	GameManager.resume_game()
	_hide_modal()

func _hide_modal() -> void:
	modal = ""
	overlay.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _show_floor_complete() -> void:
	_begin_modal("floor", "ALPHA DOWN. TAIL UP.", "Your treats carry forward. The next dimension bites a little harder.")
	var next := KennelUI.button("SNIFF OUT FLOOR %d   →" % (run.current_floor + 1), _next_floor)
	content.add_child(next)
	next.grab_focus()

func _next_floor() -> void:
	_hide_modal()
	run.advance_floor()

func _show_end(victory: bool) -> void:
	_begin_modal("end", "THE GOODEST DOG IN 4D." if victory else "EVERY DOG HAS ANOTHER DAY.", "SCORE %d   •   %d KILLS   •   %d ROOMS   •   %02d:%02d" % [GameManager.current_score, GameManager.enemies_killed, GameManager.rooms_cleared, int(GameManager.run_time) / 60, int(GameManager.run_time) % 60])
	var retry := KennelUI.button("ANOTHER WALK", _retry)
	content.add_child(retry)
	retry.grab_focus()
	content.add_child(KennelUI.button("RETURN TO MENU", _to_menu))

func _retry() -> void:
	get_tree().paused = false
	GameManager.run_seed = 0
	get_tree().reload_current_scene()

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
