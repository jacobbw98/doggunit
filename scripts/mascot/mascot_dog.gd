@tool
class_name MascotDog
extends Node3D
## MAPPO: an authored, flat-shaded mesh mascot. Forward is -Z; paws rest at Y=0.
## Every visible part is an editable ArrayMesh, with no external model dependency.

@export var animate: bool = true
@export var idle_strength: float = 1.0

const COAT := Color("182023")
const COAT_LIGHT := Color("293237")
const COAT_DARK := Color("10171a")
const MUZZLE := Color("424747")
const GREY := Color("898b83")
const INNER_EAR := Color("785b60")
const TONGUE := Color("cd7e91")
const SPOT := Color("393642")
const MINT := Color("78c9ae")
const TAG_BLUE := Color("3998c5")

var body_root: Node3D
var head_rig: Node3D
var jaw_rig: Node3D
var tail_rig: Node3D
var left_ear: Node3D
var right_ear: Node3D
var _time := 0.0
var _bark_time := 0.0
var _fur: StandardMaterial3D
var _nose: StandardMaterial3D
var _eye: StandardMaterial3D
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()

func _ready() -> void:
	if get_node_or_null("BodyRoot"):
		# Also support a copy saved with the generated native mesh children.
		body_root = get_node("BodyRoot")
		head_rig = body_root.get_node("HeadRig")
		jaw_rig = head_rig.get_node("JawRig")
		tail_rig = body_root.get_node("TailRig")
		left_ear = head_rig.get_node("LeftEarRig")
		right_ear = head_rig.get_node("RightEarRig")
		return
	_fur = _material(0.88)
	_nose = _material(0.28)
	_eye = _material(0.18)
	body_root = _rig("BodyRoot", self)
	_build_body()
	_build_legs()
	_build_tail()
	_build_collar()
	_build_head()

func _material(roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat

func _rig(part_name: String, parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var result := Node3D.new()
	result.name = part_name
	result.position = at
	parent.add_child(result)
	result.owner = self
	return result

func _build_body() -> void:
	# Sculpted oval cross-sections describe shoulders, brisket, waist and haunches.
	_loft("Torso", body_root, [
		Vector4(-0.42, 0.13, 0.19, 0.68), Vector4(-0.28, 0.25, 0.275, 0.66),
		Vector4(-0.03, 0.285, 0.255, 0.65), Vector4(0.22, 0.26, 0.225, 0.635),
		Vector4(0.44, 0.225, 0.235, 0.625), Vector4(0.59, 0.095, 0.15, 0.655)
	], 12, COAT)
	var neck := _ellipsoid("NeckAndBrisket", body_root, Vector3(0, 0.765, -0.36), Vector3(0.227, 0.29, 0.245), COAT, 12, 6)
	neck.rotation.x = -0.28
	# A small irregular pale tuft, not a large white bib.
	_patch("ChestTuft", body_root, [Vector3(-0.045, 0.625, -0.587), Vector3(0.02, 0.65, -0.6), Vector3(0.067, 0.595, -0.574), Vector3(0.02, 0.49, -0.536), Vector3(-0.007, 0.535, -0.563), Vector3(-0.034, 0.51, -0.54), Vector3(-0.064, 0.58, -0.577)], Color("979a91"), Vector3(0, 0.3, -1))
	_patch("ChestTuftShadow", body_root, [Vector3(-0.046, 0.6, -0.589), Vector3(0.006, 0.633, -0.601), Vector3(0.005, 0.553, -0.573), Vector3(-0.033, 0.525, -0.55)], Color("686f6a"), Vector3(0, 0.3, -1))

func _build_legs() -> void:
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0 else "Right"
		_ellipsoid(prefix + "Shoulder", body_root, Vector3(side * 0.205, 0.61, -0.245), Vector3(0.133, 0.225, 0.175), COAT, 9, 5)
		_tube(prefix + "Foreleg", body_root, [Vector3(side * 0.226, 0.62, -0.27), Vector3(side * 0.243, 0.375, -0.295), Vector3(side * 0.254, 0.145, -0.33), Vector3(side * 0.255, 0.066, -0.36)], [0.103, 0.078, 0.059, 0.07], COAT, 7)
		_paw(prefix + "FrontPaw", Vector3(side * 0.255, 0, -0.365))
		_ellipsoid(prefix + "Haunch", body_root, Vector3(side * 0.205, 0.575, 0.415), Vector3(0.15, 0.225, 0.183), COAT, 10, 5)
		_tube(prefix + "HindLeg", body_root, [Vector3(side * 0.215, 0.55, 0.40), Vector3(side * 0.25, 0.365, 0.295), Vector3(side * 0.258, 0.175, 0.48), Vector3(side * 0.265, 0.067, 0.425)], [0.11, 0.095, 0.051, 0.065], COAT, 7)
		_paw(prefix + "RearPaw", Vector3(side * 0.265, 0, 0.421))
		# Sparse brindle flecks on the lower legs and tops of the paws.
		for index in range(5):
			var y := 0.13 + index * 0.042
			var x: float = side * (0.245 + sin(index * 2.1) * 0.018)
			var z := -0.356 - index * 0.011
			_patch(prefix + "ForelegBrindle%d" % index, body_root, [Vector3(x - 0.023, y, z), Vector3(x + 0.024, y + 0.007, z - 0.002), Vector3(x + 0.009, y + 0.026, z - 0.008), Vector3(x - 0.012, y + 0.018, z - 0.006)], Color("6d5a46").darkened(index * 0.075), Vector3.FORWARD)
		for index in range(3):
			var at := Vector3(side * 0.266 + (index - 1) * 0.041, 0.118, -0.4)
			_patch(prefix + "PawFleck%d" % index, body_root, [at + Vector3(-0.013, 0, 0), at + Vector3(0.011, 0.004, 0), at + Vector3(0.008, 0.001, -0.029), at + Vector3(-0.008, -0.003, -0.023)], Color("796751"), Vector3.UP)

func _paw(part_name: String, at: Vector3) -> void:
	var paw := _rig(part_name, body_root, at)
	_loft("PawMesh", paw, [Vector4(-0.125, 0.054, 0.035, 0.041), Vector4(-0.092, 0.09, 0.061, 0.061), Vector4(0.02, 0.081, 0.062, 0.063), Vector4(0.077, 0.045, 0.036, 0.052)], 8, COAT_LIGHT)
	for toe in [-1.0, 1.0]:
		_tube("ToeSeam", paw, [Vector3(toe * 0.029, 0.096, -0.107), Vector3(toe * 0.031, 0.106, -0.061)], [0.004, 0.0025], COAT_DARK, 4)

func _build_tail() -> void:
	tail_rig = _rig("TailRig", body_root, Vector3(0, 0.69, 0.535))
	_tube("Tail", tail_rig, [Vector3.ZERO, Vector3(0, 0.025, 0.12), Vector3(0.028, 0.09, 0.24), Vector3(0.06, 0.18, 0.32), Vector3(0.073, 0.23, 0.325)], [0.07, 0.052, 0.036, 0.019, 0.004], COAT, 7)

func _build_collar() -> void:
	var axis := Vector3(0, 0.66, -0.75).normalized()
	_band("MintCollar", body_root, Vector3(0, 0.755, -0.413), axis, 0.237, 0.224, 0.072, MINT)
	_band("TagRing", body_root, Vector3(0, 0.68, -0.601), Vector3.FORWARD, 0.021, 0.021, 0.009, Color("b7c9ca"))
	var heart := PackedVector2Array([Vector2(0, -0.07), Vector2(-0.069, -0.006), Vector2(-0.077, 0.034), Vector2(-0.051, 0.063), Vector2(-0.022, 0.064), Vector2(0, 0.037), Vector2(0.022, 0.064), Vector2(0.051, 0.063), Vector2(0.077, 0.034), Vector2(0.069, -0.006)])
	var tag := _rig("BlueHeartTag", body_root, Vector3(0, 0.594, -0.637))
	_extruded_polygon("Heart", tag, heart, 0.02, TAG_BLUE)
	# The small raised M is geometry, so it remains sharp at any viewing size.
	var letter := [Vector3(-0.024, -0.019, -0.013), Vector3(-0.022, 0.024, -0.013), Vector3(0, 0.004, -0.013), Vector3(0.022, 0.024, -0.013), Vector3(0.024, -0.019, -0.013)]
	_tube("MInitial", tag, letter, [0.003, 0.003, 0.003, 0.003, 0.003], Color("b9e6ec"), 4)

func _build_head() -> void:
	head_rig = _rig("HeadRig", body_root, Vector3(0, 0.915, -0.56))
	_loft("BroadSkull", head_rig, [Vector4(-0.221, 0.171, 0.142, 0.007), Vector4(-0.12, 0.265, 0.21, 0.022), Vector4(0.072, 0.272, 0.206, 0.02), Vector4(0.217, 0.169, 0.152, -0.032)], 12, COAT)
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0 else "Right"
		_ellipsoid(prefix + "Cheek", head_rig, Vector3(side * 0.194, -0.075, -0.132), Vector3(0.098, 0.129, 0.126), COAT_LIGHT, 8, 4)
		_build_eye(side, prefix)
		var ear := _rig(prefix + "EarRig", head_rig, Vector3(side * 0.184, 0.177, 0.022))
		_build_ear(ear, side)
		if side < 0:
			left_ear = ear
		else:
			right_ear = ear
	# The short broad nose sits close to the cheek line, avoiding a long shepherd snout.
	var muzzle := _loft("SilveredMuzzle", head_rig, [Vector4(-0.477, 0.106, 0.057, -0.046), Vector4(-0.428, 0.201, 0.091, -0.043), Vector4(-0.30, 0.222, 0.104, -0.044), Vector4(-0.188, 0.161, 0.089, -0.026)], 10, MUZZLE)
	_ellipsoid("Nose", head_rig, Vector3(0, -0.006, -0.479), Vector3(0.122, 0.066, 0.05), COAT_DARK, 9, 4, _nose)
	for side in [-1.0, 1.0]:
		_ellipsoid("Nostril", head_rig, Vector3(side * 0.06, -0.017, -0.523), Vector3(0.026, 0.014, 0.009), Color("080e12"), 7, 3)
	_ellipsoid("NoseHighlight", head_rig, Vector3(-0.029, 0.035, -0.513), Vector3(0.044, 0.011, 0.006), Color("657074"), 6, 3, _nose)
	_build_muzzle_flecks(muzzle)
	_ellipsoid("OpenMouth", head_rig, Vector3(0, -0.162, -0.308), Vector3(0.177, 0.083, 0.142), Color("10141b"), 10, 4)
	# The flexible lower jaw also carries the tongue so a bark is one coherent pose.
	jaw_rig = _rig("JawRig", head_rig, Vector3(0, -0.128, -0.129))
	_loft("LowerJaw", jaw_rig, [Vector4(-0.307, 0.081, 0.032, -0.111), Vector4(-0.267, 0.166, 0.053, -0.105), Vector4(-0.108, 0.182, 0.059, -0.073), Vector4(0.048, 0.094, 0.065, -0.011)], 10, COAT_LIGHT)
	for side in [-1.0, 1.0]:
		_ellipsoid("LowerLipGrey", jaw_rig, Vector3(side * 0.122, -0.124, -0.246), Vector3(0.052, 0.022, 0.03), Color("7d817b"), 6, 3)
		_tube("SmallCanine", head_rig, [Vector3(side * 0.143, -0.109, -0.375), Vector3(side * 0.134, -0.167, -0.38)], [0.018, 0.002], Color("ddd9c5"), 5)
	_build_tongue()

func _build_eye(side: float, prefix: String) -> void:
	var eye_rig := _rig(prefix + "Eye", head_rig, Vector3(side * 0.184, 0.057, -0.203))
	eye_rig.rotation.y = -side * 0.22
	_ellipsoid("Socket", eye_rig, Vector3.ZERO, Vector3(0.072, 0.053, 0.037), COAT_DARK, 8, 4)
	_ellipsoid("WarmSclera", eye_rig, Vector3(0, 0.004, -0.032), Vector3(0.048, 0.034, 0.012), Color("77705b"), 8, 4, _eye)
	_ellipsoid("AmberIris", eye_rig, Vector3(-side * 0.004, 0.004, -0.041), Vector3(0.033, 0.034, 0.012), Color("b68b49"), 9, 4, _eye)
	_ellipsoid("Pupil", eye_rig, Vector3(-side * 0.004, 0.004, -0.05), Vector3(0.017, 0.025, 0.006), Color("0b1216"), 7, 4, _eye)
	_ellipsoid("EyeCatchlight", eye_rig, Vector3(-0.012, 0.017, -0.058), Vector3(0.008, 0.008, 0.003), Color("fff7de"), 5, 3, _eye)
	var brow := _ellipsoid("Brow", eye_rig, Vector3(0, 0.047, -0.008), Vector3(0.087, 0.024, 0.036), COAT_LIGHT, 7, 3)
	brow.rotation.z = -side * 0.11

func _build_ear(parent: Node3D, side: float) -> void:
	var outline := [Vector3(-0.115, -0.016, -0.016), Vector3(0.115, -0.015, -0.017), Vector3(0.07 + 0.07 * side, 0.28, 0.023), Vector3(0.1 * side, 0.365, 0.026), Vector3(-0.07 + 0.07 * side, 0.28, 0.023)]
	# A thick folded base, a tall taper and an inset front plane create an ear,
	# rather than a flat triangle attached to the skull.
	_patch("OuterEarFront", parent, outline, COAT_LIGHT, Vector3.FORWARD)
	var back: Array = []
	for vertex in outline:
		back.append(vertex + Vector3(0, 0.008, 0.055))
	_patch("OuterEarBack", parent, back, COAT, Vector3.BACK)
	_begin()
	for i in range(outline.size()):
		var next := (i + 1) % outline.size()
		_quad(outline[i], outline[next], back[next], back[i], COAT_DARK, Vector3(outline[i].x, 0.05, 0))
	_finish("EarRim", parent)
	_patch("InnerEar", parent, [Vector3(-0.063, 0.037, -0.023), Vector3(0.066, 0.034, -0.024), Vector3(0.04 + 0.055 * side, 0.227, 0.001), Vector3(0.086 * side, 0.303, 0.009), Vector3(-0.04 + 0.055 * side, 0.227, 0.001)], INNER_EAR, Vector3.FORWARD)
	_patch("EarFold", parent, [Vector3(-0.054, 0.036, -0.026), Vector3(0.057, 0.036, -0.027), Vector3(0.013 * side, 0.105, -0.018)], Color("4c4149"), Vector3.FORWARD)

func _build_muzzle_flecks(muzzle: MeshInstance3D) -> void:
	for side in [-1.0, 1.0]:
		for i in range(13):
			var x: float = side * (0.065 + fmod(i * 0.047, 0.116))
			var y: float = -0.041 - fmod(i * 0.029, 0.06)
			var z: float = -0.438 + (absf(x) - 0.065) * 0.27
			var at := Vector3(x, y, z)
			var width := 0.008 + fmod(i * 0.011, 0.012)
			var points := [at + Vector3(-width, 0, 0), at + Vector3(width * 0.6, 0.007, 0), at + Vector3(width, -0.009, 0), at + Vector3(-width * 0.4, -0.013, 0)]
			for vertex in range(points.size()):
				points[vertex] = _onto_muzzle(muzzle, points[vertex])
			_patch("MuzzleSilver%d" % i, head_rig, points, GREY.darkened(fmod(i * 0.19, 0.3)), Vector3.FORWARD)
		for i in range(3):
			_ellipsoid("WhiskerDot", head_rig, Vector3(side * (0.09 + i * 0.035), -0.099 + i * 0.007, -0.443 + i * 0.008), Vector3(0.008, 0.006, 0.004), COAT_DARK, 5, 3)

func _onto_muzzle(muzzle: MeshInstance3D, point: Vector3) -> Vector3:
	var vertices: PackedVector3Array = muzzle.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var nearest := 1.0
	for triangle in range(0, vertices.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(point.x, point.y, -1), Vector3.BACK, vertices[triangle], vertices[triangle + 1], vertices[triangle + 2])
		if hit != null:
			nearest = minf(nearest, hit.z)
	if nearest < 1.0:
		point.z = nearest - 0.002
	return point

func _build_tongue() -> void:
	# The tongue emerges over the jaw, bends downward, and ends with a soft notch.
	var centers := [Vector3(0, -0.021, -0.204), Vector3(0, -0.057, -0.279), Vector3(0, -0.142, -0.353), Vector3(0, -0.203, -0.372)]
	var widths := [0.09, 0.101, 0.086, 0.062]
	_begin()
	for i in range(centers.size() - 1):
		var a: Vector3 = centers[i]
		var b: Vector3 = centers[i + 1]
		var normal := Vector3.RIGHT.cross(b - a).normalized()
		for half in [-1.0, 1.0]:
			_quad(a, a + Vector3.RIGHT * widths[i] * half, b + Vector3.RIGHT * widths[i + 1] * half, b, TONGUE.lightened(0.04 if half > 0 else 0.0), normal)
			_quad(a + Vector3.RIGHT * widths[i] * half, a + Vector3.RIGHT * widths[i] * half - normal * 0.012, b + Vector3.RIGHT * widths[i + 1] * half - normal * 0.012, b + Vector3.RIGHT * widths[i + 1] * half, TONGUE.darkened(0.15), Vector3.RIGHT * half)
		_quad(a - normal * 0.012, b - normal * 0.012, b + Vector3.RIGHT * widths[i + 1] - normal * 0.012, a + Vector3.RIGHT * widths[i] - normal * 0.012, TONGUE.darkened(0.18), -normal)
	var tip: Vector3 = centers.back()
	_triangle(tip + Vector3(-0.062, 0, 0), tip + Vector3(-0.028, -0.022, -0.001), tip + Vector3(0, -0.019, -0.002), TONGUE, Vector3.FORWARD)
	_triangle(tip + Vector3(0, -0.019, -0.002), tip + Vector3(0.03, -0.023, -0.001), tip + Vector3(0.062, 0, 0), TONGUE, Vector3.FORWARD)
	_finish("SpottedTongue", jaw_rig)
	var spots := [Vector3(-0.043, 0.47, 0.026), Vector3(0.042, 0.34, 0.023), Vector3(0.018, 0.74, 0.032), Vector3(-0.044, 0.83, 0.019), Vector3(0.044, 0.94, 0.019), Vector3(-0.003, 0.14, 0.02)]
	for i in range(spots.size()):
		var spot: Vector3 = spots[i]
		var cursor := spot.y * (centers.size() - 1)
		var segment := mini(int(cursor), centers.size() - 2)
		var start: Vector3 = centers[segment]
		var finish: Vector3 = centers[segment + 1]
		var along := (finish - start).normalized()
		var normal := Vector3.RIGHT.cross(along).normalized()
		var center := start.lerp(finish, cursor - segment) + Vector3.RIGHT * spot.x + normal * 0.002
		var points: Array = []
		for vertex in range(7):
			var angle := TAU * vertex / 7.0
			var radius := spot.z * (0.9 + 0.14 * sin(vertex * 2.5 + i))
			points.append(center + Vector3.RIGHT * cos(angle) * radius + along * sin(angle) * radius * 0.86)
		_patch("TongueSpot%d" % i, jaw_rig, points, SPOT, normal)

## Short visual bark; it still plays when idle animation is disabled for a held gun.
func bark() -> void:
	_bark_time = 0.30

func _process(delta: float) -> void:
	if not is_instance_valid(body_root):
		return
	_time += delta
	var strength := idle_strength if animate else 0.0
	body_root.scale.y = 1.0 + sin(_time * 2.6) * 0.008 * strength
	tail_rig.rotation.y = sin(_time * 4.8) * 0.17 * strength
	left_ear.rotation.z = sin(_time * 1.7 + 1.0) * 0.017 * strength
	right_ear.rotation.z = sin(_time * 1.9) * 0.013 * strength
	_bark_time = maxf(0.0, _bark_time - delta)
	var pulse := sin((1.0 - _bark_time / 0.3) * PI) if _bark_time > 0.0 else 0.0
	head_rig.rotation.x = 0.045 * pulse
	jaw_rig.rotation.x = -0.18 * pulse

func _begin() -> void:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()

func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	if normal.is_zero_approx():
		return
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	# Godot's visible front faces use clockwise winding. The outward normal is
	# derived above with the mathematical cross product, then vertices reverse.
	for vertex in [a, c, b]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(color)

func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	_triangle(a, b, c, color, outward)
	_triangle(a, c, d, color, outward)

func _finish(part_name: String, parent: Node3D, material: Material = null) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = material if material else _fur
	parent.add_child(instance)
	instance.owner = self
	return instance

func _loft(part_name: String, parent: Node3D, sections: Array, segments: int, color: Color) -> MeshInstance3D:
	_begin()
	for ring in range(sections.size() - 1):
		var from: Vector4 = sections[ring]
		var to: Vector4 = sections[ring + 1]
		for segment in range(segments):
			var angle := TAU * segment / segments + PI / segments
			var next := TAU * (segment + 1) / segments + PI / segments
			var a := Vector3(cos(angle) * from.y, from.w + sin(angle) * from.z, from.x)
			var b := Vector3(cos(next) * from.y, from.w + sin(next) * from.z, from.x)
			var c := Vector3(cos(next) * to.y, to.w + sin(next) * to.z, to.x)
			var d := Vector3(cos(angle) * to.y, to.w + sin(angle) * to.z, to.x)
			var outward := Vector3(cos(angle + PI / segments), sin(angle + PI / segments), 0)
			var tint := color.lightened(0.018 * (0.5 + 0.5 * sin(segment * 4.2 + ring)))
			_quad(a, b, c, d, tint, outward)
	for end in [0, sections.size() - 1]:
		var section: Vector4 = sections[end]
		var center := Vector3(0, section.w, section.x)
		for segment in range(segments):
			var angle := TAU * segment / segments + PI / segments
			var next := TAU * (segment + 1) / segments + PI / segments
			_triangle(center, center + Vector3(cos(angle) * section.y, sin(angle) * section.z, 0), center + Vector3(cos(next) * section.y, sin(next) * section.z, 0), color, Vector3.FORWARD if end == 0 else Vector3.BACK)
	return _finish(part_name, parent)

func _ellipsoid(part_name: String, parent: Node3D, at: Vector3, radii: Vector3, color: Color, segments: int = 10, rings: int = 5, material: Material = null) -> MeshInstance3D:
	_begin()
	for ring in range(rings):
		var latitude := PI * ring / rings
		var next_latitude := PI * (ring + 1) / rings
		for segment in range(segments):
			var longitude := TAU * segment / segments
			var next_longitude := TAU * (segment + 1) / segments
			var a := Vector3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude)) * radii
			var b := Vector3(sin(next_latitude) * cos(longitude), cos(next_latitude), sin(next_latitude) * sin(longitude)) * radii
			var c := Vector3(sin(next_latitude) * cos(next_longitude), cos(next_latitude), sin(next_latitude) * sin(next_longitude)) * radii
			var d := Vector3(sin(latitude) * cos(next_longitude), cos(latitude), sin(latitude) * sin(next_longitude)) * radii
			_quad(a, b, c, d, color.lightened(0.011 * fmod(segment + ring, 3)), (a + b + c + d).normalized())
	var instance := _finish(part_name, parent, material)
	instance.position = at
	return instance

func _tube(part_name: String, parent: Node3D, centers: Array, radii: Array, color: Color, segments: int = 7) -> MeshInstance3D:
	_begin()
	var cross_sections: Array = []
	for index in range(centers.size()):
		var center: Vector3 = centers[index]
		var before: Vector3 = centers[maxi(index - 1, 0)]
		var after: Vector3 = centers[mini(index + 1, centers.size() - 1)]
		var axis := (after - before).normalized()
		var right := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.FORWARD).normalized()
		var up := axis.cross(right).normalized()
		var points: Array = []
		for segment in range(segments):
			var angle := TAU * segment / segments
			points.append(center + (right * cos(angle) + up * sin(angle)) * radii[index])
		cross_sections.append(points)
	for ring in range(centers.size() - 1):
		for segment in range(segments):
			var next := (segment + 1) % segments
			var a: Vector3 = cross_sections[ring][segment]
			var b: Vector3 = cross_sections[ring][next]
			var c: Vector3 = cross_sections[ring + 1][next]
			var d: Vector3 = cross_sections[ring + 1][segment]
			_quad(a, b, c, d, color.lightened(0.012 * (segment % 3)), (a + b + c + d) * 0.25 - (centers[ring] + centers[ring + 1]) * 0.5)
	for end in [0, centers.size() - 1]:
		var normal: Vector3 = (centers[0] - centers[1]).normalized() if end == 0 else (centers[-1] - centers[-2]).normalized()
		for segment in range(segments):
			_triangle(centers[end], cross_sections[end][segment], cross_sections[end][(segment + 1) % segments], color, normal)
	return _finish(part_name, parent)

func _patch(part_name: String, parent: Node3D, points: Array, color: Color, normal: Vector3) -> MeshInstance3D:
	_begin()
	var center := Vector3.ZERO
	for point in points:
		center += point
	center /= points.size()
	for index in range(points.size()):
		_triangle(center, points[index], points[(index + 1) % points.size()], color, normal)
	return _finish(part_name, parent)

func _band(part_name: String, parent: Node3D, center: Vector3, axis: Vector3, radius_x: float, radius_y: float, width: float, color: Color) -> MeshInstance3D:
	_begin()
	var right := Vector3.RIGHT
	var up := axis.cross(right).normalized()
	for segment in range(16):
		var angle := TAU * segment / 16
		var next := TAU * (segment + 1) / 16
		var radial := right * cos(angle) * radius_x + up * sin(angle) * radius_y
		var next_radial := right * cos(next) * radius_x + up * sin(next) * radius_y
		_quad(center + radial - axis * width * 0.5, center + next_radial - axis * width * 0.5, center + next_radial + axis * width * 0.5, center + radial + axis * width * 0.5, color.lightened(0.018 * (segment % 3)), radial)
		_quad(center + radial + axis * width * 0.5, center + next_radial + axis * width * 0.5, center + next_radial * 0.95 + axis * width * 0.5, center + radial * 0.95 + axis * width * 0.5, color.lightened(0.08), axis)
	return _finish(part_name, parent)

func _extruded_polygon(part_name: String, parent: Node3D, outline: PackedVector2Array, depth: float, color: Color) -> MeshInstance3D:
	_begin()
	var indices := Geometry2D.triangulate_polygon(outline)
	for face in [-1.0, 1.0]:
		for index in range(0, indices.size(), 3):
			var a := outline[indices[index]]
			var b := outline[indices[index + 1]]
			var c := outline[indices[index + 2]]
			_triangle(Vector3(a.x, a.y, depth * face * 0.5), Vector3(b.x, b.y, depth * face * 0.5), Vector3(c.x, c.y, depth * face * 0.5), color, Vector3(0, 0, face))
	for index in range(outline.size()):
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		_quad(Vector3(a.x, a.y, -depth * 0.5), Vector3(b.x, b.y, -depth * 0.5), Vector3(b.x, b.y, depth * 0.5), Vector3(a.x, a.y, depth * 0.5), color.darkened(0.25), Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 0))
	return _finish(part_name, parent)
