# Player HUD - Shows health, ammo, and 3 gun slots
class_name PlayerHUD
extends CanvasLayer

# UI references
var health_bar: ProgressBar
var health_label: Label
var ammo_label: Label
var gun_slots: Array[Panel] = []
var gun_labels: Array[Label] = []

# Player reference
var player: Node
var weapon_manager: WeaponManager

func _ready() -> void:
	_create_ui()
	await get_tree().process_frame
	_connect_to_player()

func _create_ui() -> void:
	# Main container
	var main_container := Control.new()
	main_container.name = "HUDContainer"
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_container)
	
	# Health bar (top left)
	var health_container := VBoxContainer.new()
	health_container.position = Vector2(20, 20)
	health_container.size = Vector2(200, 50)
	main_container.add_child(health_container)
	
	var health_title := Label.new()
	health_title.text = "HEALTH"
	health_title.add_theme_font_size_override("font_size", 12)
	health_container.add_child(health_title)
	
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(200, 20)
	health_bar.value = 100
	health_bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2)
	health_bar.add_theme_stylebox_override("background", style)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.2, 0.2)
	health_bar.add_theme_stylebox_override("fill", fill)
	health_container.add_child(health_bar)
	
	health_label = Label.new()
	health_label.text = "100 / 100"
	health_label.add_theme_font_size_override("font_size", 14)
	health_container.add_child(health_label)
	
	# Ammo (bottom right)
	ammo_label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.position = Vector2(-150, -60)
	ammo_label.size = Vector2(130, 40)
	ammo_label.text = "-- / --"
	ammo_label.add_theme_font_size_override("font_size", 24)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main_container.add_child(ammo_label)
	
	# Gun slots (bottom center)
	var slots_container := HBoxContainer.new()
	slots_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	slots_container.position = Vector2(-120, -80)
	slots_container.add_theme_constant_override("separation", 10)
	main_container.add_child(slots_container)
	
	for i in range(3):
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(70, 50)
		
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		slot_style.border_color = Color(0.5, 0.5, 0.5)
		slot_style.set_border_width_all(2)
		slot.add_theme_stylebox_override("panel", slot_style)
		
		var slot_label := Label.new()
		slot_label.text = str(i + 1) + ": Empty"
		slot_label.add_theme_font_size_override("font_size", 11)
		slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(slot_label)
		
		slots_container.add_child(slot)
		gun_slots.append(slot)
		gun_labels.append(slot_label)

func _connect_to_player() -> void:
	player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	# Connect health signal
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	
	# Get weapon manager
	if player.has_node("Camera3D/WeaponManager"):
		weapon_manager = player.get_node("Camera3D/WeaponManager")
		weapon_manager.weapon_switched.connect(_on_weapon_switched)
		weapon_manager.weapon_picked_up.connect(_on_weapon_picked_up)
	
	# Initial update
	if player.has_method("get_health"):
		_on_health_changed(player.current_health, player.max_health)
	else:
		_on_health_changed(player.current_health, player.max_health)

func _on_health_changed(current: int, max_hp: int) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current
	health_label.text = "%d / %d" % [current, max_hp]
	
	# Color based on health
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill:
		if current < max_hp * 0.25:
			fill.bg_color = Color(0.9, 0.1, 0.1)  # Red
		elif current < max_hp * 0.5:
			fill.bg_color = Color(0.9, 0.6, 0.1)  # Orange
		else:
			fill.bg_color = Color(0.2, 0.8, 0.2)  # Green

func _on_weapon_switched(index: int, gun: Gun) -> void:
	# Update slot highlights
	for i in range(3):
		var slot := gun_slots[i]
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if i == index:
			style.border_color = Color(1.0, 0.8, 0.2)  # Gold highlight
			style.bg_color = Color(0.2, 0.2, 0.15, 0.9)
		else:
			style.border_color = Color(0.5, 0.5, 0.5)
			style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
		slot.add_theme_stylebox_override("panel", style)
	
	# Update ammo
	if gun and gun.stats:
		ammo_label.text = "%d / %d" % [gun.current_ammo, gun.stats.max_ammo]
		gun.ammo_changed.connect(_on_ammo_changed)

func _on_weapon_picked_up(gun: Gun) -> void:
	_update_gun_slots()

func _update_gun_slots() -> void:
	if not weapon_manager:
		return
	
	for i in range(3):
		if weapon_manager.guns[i]:
			var gun_stats = weapon_manager.guns[i].stats
			if gun_stats:
				var type_short = GunTypes.get_type_name(gun_stats.gun_type).substr(0, 4)
				gun_labels[i].text = str(i + 1) + ": " + type_short
				gun_labels[i].add_theme_color_override("font_color", GunTypes.RARITY_COLORS[gun_stats.rarity])
		else:
			gun_labels[i].text = str(i + 1) + ": Empty"
			gun_labels[i].remove_theme_color_override("font_color")

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [current, max_ammo]

func _process(_delta: float) -> void:
	# Update ammo from current gun
	if weapon_manager:
		var gun = weapon_manager.get_current_gun()
		if gun and gun.stats:
			ammo_label.text = "%d / %d" % [gun.current_ammo, gun.stats.max_ammo]
