extends Node3D

var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	for i in range(get_child_count()):
		var strand := get_child(i) as Node3D
		strand.rotation.x = 0.6 * sin(i * 2.4) + sin(_time * 9.0 + i * 1.8) * 0.3
		strand.rotation.z = 0.6 * cos(i * 2.4) + cos(_time * 7.0 + i * 1.8) * 0.3
