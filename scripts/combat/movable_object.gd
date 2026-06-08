extends RigidBody3D

@export var impulse_multiplier := 1.0
@export var damage_per_speed := 1.0
@export var minimum_damage := 2
@export var vector_visual_scale := 0.08
@export var vector_visual_height := 0.9

var _pending_impulse := Vector3.ZERO
var _can_damage := true
var _highlight_material: StandardMaterial3D = StandardMaterial3D.new()
var _selected_material: StandardMaterial3D = StandardMaterial3D.new()
var _planned_material: StandardMaterial3D = StandardMaterial3D.new()
var _vector_material: StandardMaterial3D = StandardMaterial3D.new()
var _vector_mesh: ImmediateMesh = ImmediateMesh.new()
var _vector_visual: MeshInstance3D
var _vector_tip: MeshInstance3D


func _ready() -> void:
	add_to_group("gravity_movable")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	_highlight_material.albedo_color = Color(0.18, 0.72, 1.0, 0.45)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_selected_material.albedo_color = Color(1.0, 0.82, 0.18, 0.6)
	_selected_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selected_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_planned_material.albedo_color = Color(0.45, 1.0, 0.38, 0.5)
	_planned_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_planned_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_vector_material.albedo_color = Color(0.5, 1.0, 0.3, 1.0)
	_vector_material.emission_enabled = true
	_vector_material.emission = Color(0.5, 1.0, 0.3, 1.0)
	_vector_material.emission_energy_multiplier = 1.6
	_vector_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_vector_visual = MeshInstance3D.new()
	_vector_visual.name = "PlannedVector"
	_vector_visual.mesh = _vector_mesh
	_vector_visual.visible = false
	add_child(_vector_visual)

	var tip_mesh := SphereMesh.new()
	tip_mesh.radius = 0.08
	tip_mesh.height = 0.16

	_vector_tip = MeshInstance3D.new()
	_vector_tip.name = "PlannedVectorTip"
	_vector_tip.mesh = tip_mesh
	_vector_tip.material_override = _vector_material
	_vector_tip.visible = false
	add_child(_vector_tip)


func set_tactical_highlight(enabled: bool, selected: bool = false) -> void:
	if selected:
		_set_overlay(_selected_material)
	elif _pending_impulse != Vector3.ZERO:
		_set_overlay(_planned_material)
	elif enabled:
		_set_overlay(_highlight_material)
	else:
		_set_overlay(null)


func queue_gravity_impulse(impulse: Vector3) -> void:
	if impulse.length() < 0.05:
		clear_plan()
		return

	_pending_impulse = impulse * impulse_multiplier
	_set_overlay(_planned_material)
	_update_vector_visual(_pending_impulse)


func preview_gravity_impulse(impulse: Vector3) -> void:
	_update_vector_visual(impulse * impulse_multiplier)


func apply_planned_impulse() -> void:
	if _pending_impulse == Vector3.ZERO:
		return

	sleeping = false
	apply_central_impulse(_pending_impulse)
	_pending_impulse = Vector3.ZERO
	_set_overlay(null)
	_hide_vector_visual()


func clear_plan() -> void:
	_pending_impulse = Vector3.ZERO
	_set_overlay(null)
	_hide_vector_visual()


func _set_overlay(material: Material) -> void:
	for child in get_children():
		if child is MeshInstance3D and not child.name.begins_with("PlannedVector"):
			child.material_overlay = material


func _update_vector_visual(impulse: Vector3) -> void:
	if impulse.length() < 0.05:
		_hide_vector_visual()
		return

	var origin := Vector3(0.0, vector_visual_height, 0.0)
	var local_vector := global_transform.basis.inverse() * impulse * vector_visual_scale
	var tip := origin + local_vector
	var direction := local_vector.normalized()
	var side := direction.cross(Vector3.UP)

	if side.length() < 0.01:
		side = direction.cross(Vector3.RIGHT)

	side = side.normalized()
	var head_length := minf(local_vector.length() * 0.3, 0.45)
	var head_width := minf(local_vector.length() * 0.18, 0.25)
	var head_back := tip - direction * head_length

	_vector_mesh.clear_surfaces()
	_vector_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _vector_material)
	_vector_mesh.surface_add_vertex(origin)
	_vector_mesh.surface_add_vertex(tip)
	_vector_mesh.surface_add_vertex(tip)
	_vector_mesh.surface_add_vertex(head_back + side * head_width)
	_vector_mesh.surface_add_vertex(tip)
	_vector_mesh.surface_add_vertex(head_back - side * head_width)
	_vector_mesh.surface_end()

	_vector_visual.visible = true
	_vector_tip.position = tip
	_vector_tip.visible = true


func _hide_vector_visual() -> void:
	_vector_mesh.clear_surfaces()
	_vector_visual.visible = false
	_vector_tip.visible = false


func _on_body_entered(body: Node) -> void:
	if not _can_damage or not body.has_method("take_damage"):
		return

	var impact_speed: float = linear_velocity.length()
	if impact_speed < 2.0:
		return

	var speed_damage: int = roundi(impact_speed * damage_per_speed)
	var damage: int = maxi(minimum_damage, speed_damage)
	body.call("take_damage", damage)

	_can_damage = false
	await get_tree().create_timer(0.2).timeout
	_can_damage = true
