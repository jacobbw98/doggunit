class_name SlotMachine
extends Node3D

const SPIN_COST: int = 3
const SPIN_SECONDS: float = 1.2
const MODEL_HEIGHT: float = 4.2
const DISPLAY_SCALE: float = MODEL_HEIGHT / 2.1
enum Outcome { JACKPOT, ITEM, BONES, NOTHING }
var run: Node
var room: Node3D
var room_id: int = -1
var broken: bool = false
var spinning: bool = false
var spin_remaining: float = 0.0
var pending_roll: int = -1
var last_outcome: int = -1
var _model: Node3D
var _label: Label3D
var _reels: Array[Label3D] = []
var _time: float = 0.0
var _item_rewards: int = 0

func configure(run_owner: Node, owning_room: Node3D) -> void:
	run = run_owner
	room = owning_room
	room_id = int(room.get("room_id"))
	set_meta("room_id", room_id)

func _ready() -> void:
	add_to_group("item_interactables")
	add_to_group("slot_machines")
	name = "BoneSlotMachine"
	_model = RoomEconomy.make_model("slot_machine", MODEL_HEIGHT, true)
	add_child(_model)
	_label = RoomEconomy.make_label("BONE JACKPOT\n3 bones per spin", Color(1.0, 0.82, 0.35))
	_label.position.y = 2.50 * DISPLAY_SCALE
	add_child(_label)
	for index in range(3):
		var reel := RoomEconomy.make_label("?", Color(1.0, 0.92, 0.55))
		reel.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		# Label3D's text front points +Z; the GLB cabinet front points -Z.
		reel.rotation.y = PI
		reel.position = Vector3((index - 1) * 0.30, 1.25, -0.45) * DISPLAY_SCALE
		reel.font_size = 32
		reel.pixel_size *= DISPLAY_SCALE
		add_child(reel)
		_reels.append(reel)

func get_interaction_position() -> Vector3:
	return to_global(Vector3(0, 1.25, -0.45) * DISPLAY_SCALE)

func requires_interaction() -> bool:
	return true

static func outcome_for_roll(roll: int) -> Outcome:
	if roll == 0:
		return Outcome.JACKPOT
	if roll >= 1 and roll <= 20:
		return Outcome.ITEM
	if roll >= 21 and roll <= 50:
		return Outcome.BONES
	return Outcome.NOTHING

func get_interaction_text(actor_run: Node) -> String:
	if broken or not RoomEconomy.can_interact(actor_run, room, self):
		return ""
	if spinning:
		return "Spinning..."
	return "Spin · 3 bones" + (" (not enough bones)" if int(actor_run.get("bones")) < SPIN_COST else "")

func interact(actor_run: Node) -> bool:
	if broken or spinning or not RoomEconomy.can_interact(actor_run, room, self):
		return false
	# Lock before charging. Another input during the spin cannot charge twice.
	spinning = true
	if not actor_run.spend_bones(SPIN_COST):
		spinning = false
		return false
	pending_roll = RoomEconomy._rng(actor_run).randi_range(0, 99)
	spin_remaining = SPIN_SECONDS
	_label.text = "GOOD LUCK!"
	return true

func _process(delta: float) -> void:
	visible = RoomEconomy.room_visible(run, room)
	_time += delta
	if spinning:
		spin_remaining = maxf(0.0, spin_remaining - delta)
		for index in range(_reels.size()):
			_reels[index].text = ["B", "★", "●"][int(_time * 15.0 + index) % 3]
		if spin_remaining <= 0.0:
			resolve_spin()

func resolve_spin() -> void:
	if not spinning or broken:
		return
	spinning = false
	last_outcome = outcome_for_roll(pending_roll)
	pending_roll = -1
	match last_outcome:
		Outcome.JACKPOT:
			broken = true
			run.add_bones(100)
			_model.visible = false
			for reel in _reels:
				reel.visible = false
			_label.text = "JACKPOT! +100 BONES\nMachine destroyed"
			_explode()
		Outcome.ITEM:
			var rewards := RoomEconomy.spawn_reward(run, room, 1, false)
			if not rewards.is_empty():
				# Put winnings beside the machine, even if the player walked away.
				var outward := (global_position - room.global_position).normalized()
				var side := global_basis.x * (2.4 + (_item_rewards / 2) * 1.1)
				if _item_rewards % 2 == 1:
					side = -side
				var direction := (outward + side / float(room.get("radius"))).normalized()
				RoomEconomy.place_on_surface(rewards[0], room, direction, outward - global_basis.z * 0.1)
				_item_rewards += 1
			_label.text = "YOU WON AN ITEM!\n3 bones per spin"
			_set_reels("★")
		Outcome.BONES:
			var payout := 5 if RoomEconomy._rng(run).randi_range(0, 1) == 0 else 10
			RoomEconomy.spawn_bones(run, room, global_position + global_basis.y * DISPLAY_SCALE, payout)
			_label.text = "%d BONES!\n3 bones per spin" % payout
			_set_reels("B")
		Outcome.NOTHING:
			_label.text = "NO LUCK THIS TIME\n3 bones per spin"
			_set_reels("—")

func _set_reels(symbol: String) -> void:
	for reel in _reels:
		reel.text = symbol

func _explode() -> void:
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.30 * DISPLAY_SCALE
	sphere.height = 0.60 * DISPLAY_SCALE
	sphere.radial_segments = 8
	sphere.rings = 4
	flash.mesh = sphere
	flash.position.y = 1.05 * DISPLAY_SCALE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.80, 0.20)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.43, 0.08)
	material.emission_energy_multiplier = 3.0
	flash.material_override = material
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 7.0, 0.18)
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(flash.queue_free)
	for index in range(12):
		var shard := MeshInstance3D.new()
		var chunk := BoxMesh.new()
		chunk.size = Vector3(0.13, 0.18, 0.12) * DISPLAY_SCALE
		shard.mesh = chunk
		shard.material_override = material
		shard.position.y = 1.05 * DISPLAY_SCALE
		add_child(shard)
		var direction := Vector3(cos(index * TAU / 12.0), 0.8 + (index % 3) * 0.25, sin(index * TAU / 12.0))
		var scatter := create_tween().set_parallel(true)
		scatter.tween_property(shard, "position", shard.position + direction * 1.5 * DISPLAY_SCALE, 0.55)
		scatter.tween_property(shard, "scale", Vector3.ZERO, 0.6)
		scatter.chain().tween_callback(shard.queue_free)
