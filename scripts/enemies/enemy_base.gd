# Base Enemy - Enemies use guns that drop when defeated
class_name EnemyBase
extends CharacterBody3D

signal died(enemy: EnemyBase)
signal damaged(current_health: int, max_health: int)

@export var max_health: int = 50
@export var move_speed: float = 3.0
@export var enemy_type: GunTypes.Type = GunTypes.Type.EXPLOSIVE

# The gun this enemy uses (and drops)
@export var equipped_gun_stats: GunStats

var current_health: int
var target: Node3D = null
var gun: Gun = null

func _ready() -> void:
	current_health = max_health
	_setup_gun()

func _setup_gun() -> void:
	if equipped_gun_stats:
		gun = Gun.new()
		gun.stats = equipped_gun_stats
		add_child(gun)

func _physics_process(delta: float) -> void:
	if target:
		_move_towards_target(delta)
		_try_attack()

func _move_towards_target(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0  # Stay on ground
	velocity = direction * move_speed
	move_and_slide()
	
	# Face target
	look_at(target.global_position)

func _try_attack() -> void:
	if not gun:
		return
	
	var distance = global_position.distance_to(target.global_position)
	if distance < 15.0:  # Attack range
		var direction = (target.global_position - global_position).normalized()
		gun.fire(global_position + Vector3(0, 1, 0), direction)

func take_damage(amount: int, damage_type: GunTypes.Type) -> void:
	# Apply type effectiveness
	var effectiveness = GunTypes.get_effectiveness(damage_type, enemy_type)
	var final_damage = int(amount * effectiveness)
	
	current_health -= final_damage
	current_health = max(current_health, 0)
	
	damaged.emit(current_health, max_health)
	
	if effectiveness > 1.0:
		print("Super effective! %.0f%% damage" % [effectiveness * 100])
	elif effectiveness < 1.0:
		print("Not very effective... %.0f%% damage" % [effectiveness * 100])
	
	if current_health <= 0:
		_die()

func _die() -> void:
	died.emit(self)
	GameManager.enemy_killed()
	
	# Drop gun pickup (will be handled by level)
	_drop_gun()
	
	queue_free()

func _drop_gun() -> void:
	if equipped_gun_stats:
		print("Enemy dropped: %s" % equipped_gun_stats.get_display_name())
		# Actual pickup spawning will be handled by the level manager

func set_target(new_target: Node3D) -> void:
	target = new_target
