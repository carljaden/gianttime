extends RigidBody3D

@export var impulse_multiplier := 1.0
@export var damage_per_speed := 1.0
@export var minimum_damage := 2
@export var vector_visual_scale := 0.08
@export var vector_visual_height := 0.0
@export var vector_shaft_radius := 0.045
@export var trajectory_marker_count := 16
@export var trajectory_step_time := 0.12
@export var trajectory_marker_radius := 0.055

var _pending_impulse := Vector3.ZERO
var _can_damage := true
var _highlight_material: StandardMaterial3D = StandardMaterial3D.new()
var _selected_material: StandardMaterial3D = StandardMaterial3D.new()
var _planned_material: StandardMaterial3D = StandardMaterial3D.new()
var _vector_material: StandardMaterial3D = StandardMaterial3D.new()
var _vector_root: Node3D
var _vector_shaft_mesh: CylinderMesh = CylinderMesh.new()
var _vector_tip_mesh: CylinderMesh = CylinderMesh.new()
var _vector_shaft: MeshInstance3D
var _vector_tip: MeshInstance3D
var _trajectory_root: Node3D
var _trajectory_material: StandardMaterial3D = StandardMaterial3D.new()
var _trajectory_markers: Array[MeshInstance3D] = []
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float


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
	_vector_material.no_depth_test = true
	_vector_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_vector_root = Node3D.new()
	_vector_root.name = "PlannedVector"
	_vector_root.visible = false
	add_child(_vector_root)

	_vector_shaft_mesh.top_radius = vector_shaft_radius
	_vector_shaft_mesh.bottom_radius = vector_shaft_radius
	_vector_shaft_mesh.height = 1.0

	_vector_shaft = MeshInstance3D.new()
	_vector_shaft.name = "PlannedVectorShaft"
	_vector_shaft.mesh = _vector_shaft_mesh
	_vector_shaft.material_override = _vector_material
	_vector_root.add_child(_vector_shaft)

	_vector_tip_mesh.top_radius = 0.0
	_vector_tip_mesh.bottom_radius = vector_shaft_radius * 3.0
	_vector_tip_mesh.height = 0.28

	_vector_tip = MeshInstance3D.new()
	_vector_tip.name = "PlannedVectorTip"
	_vector_tip.mesh = _vector_tip_mesh
	_vector_tip.material_override = _vector_material
	_vector_root.add_child(_vector_tip)

	_trajectory_material.albedo_color = Color(0.35, 0.95, 1.0, 0.86)
	_trajectory_material.emission_enabled = true
	_trajectory_material.emission = Color(0.35, 0.95, 1.0, 1.0)
	_trajectory_material.emission_energy_multiplier = 1.4
	_trajectory_material.no_depth_test = true
	_trajectory_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trajectory_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_trajectory_root = Node3D.new()
	_trajectory_root.name = "ProjectedTrajectory"
	_trajectory_root.visible = false
	add_child(_trajectory_root)

	var marker_mesh: SphereMesh = SphereMesh.new()
	marker_mesh.radius = trajectory_marker_radius
	marker_mesh.height = trajectory_marker_radius * 2.0

	for marker_index in range(trajectory_marker_count):
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.name = "TrajectoryMarker%s" % marker_index
		marker.mesh = marker_mesh
		marker.material_override = _trajectory_material
		marker.visible = false
		_trajectory_root.add_child(marker)
		_trajectory_markers.append(marker)


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
	_update_trajectory_visual(_pending_impulse)


func preview_gravity_impulse(impulse: Vector3) -> void:
	var preview_impulse: Vector3 = impulse * impulse_multiplier
	_update_vector_visual(preview_impulse)
	_update_trajectory_visual(preview_impulse)


func has_planned_impulse() -> bool:
	return _pending_impulse != Vector3.ZERO


func apply_planned_impulse() -> void:
	if _pending_impulse == Vector3.ZERO:
		return

	sleeping = false
	apply_central_impulse(_pending_impulse)
	_pending_impulse = Vector3.ZERO
	_set_overlay(null)
	_hide_vector_visual()
	_hide_trajectory_visual()


func clear_plan() -> void:
	_pending_impulse = Vector3.ZERO
	_set_overlay(null)
	_hide_vector_visual()
	_hide_trajectory_visual()


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
	var direction := local_vector.normalized()
	var visual_length := local_vector.length()
	var head_length := minf(visual_length * 0.3, 0.45)
	var shaft_length := maxf(visual_length - head_length, 0.05)
	var shaft_center := origin + direction * (shaft_length * 0.5)
	var tip_center := origin + direction * (shaft_length + head_length * 0.5)
	var arrow_basis := Basis(Quaternion(Vector3.UP, direction))

	_vector_shaft_mesh.height = shaft_length
	_vector_tip_mesh.height = head_length
	_vector_shaft.transform = Transform3D(arrow_basis, shaft_center)
	_vector_tip.transform = Transform3D(arrow_basis, tip_center)
	_vector_root.visible = true


func _hide_vector_visual() -> void:
	if _vector_root != null:
		_vector_root.visible = false


func _update_trajectory_visual(impulse: Vector3) -> void:
	if impulse.length() < 0.05:
		_hide_trajectory_visual()
		return

	var launch_velocity: Vector3 = impulse / mass
	var gravity_vector: Vector3 = Vector3.DOWN * _gravity
	var origin_global: Vector3 = global_position
	var previous_global: Vector3 = origin_global
	var inverse_basis: Basis = global_transform.basis.inverse()
	var visible_count: int = 0

	for marker_index in trajectory_marker_count:
		var time: float = float(marker_index + 1) * trajectory_step_time
		var offset: Vector3 = launch_velocity * time + 0.5 * gravity_vector * time * time
		var predicted_global: Vector3 = origin_global + offset
		var collision_global: Vector3 = _get_trajectory_collision_point(previous_global, predicted_global)

		if collision_global != Vector3.INF:
			_set_trajectory_marker(marker_index, inverse_basis * (collision_global - origin_global))
			visible_count = marker_index + 1
			break

		_set_trajectory_marker(marker_index, inverse_basis * offset)
		previous_global = predicted_global
		visible_count = marker_index + 1

	_trajectory_root.visible = true

	for marker_index in range(visible_count, trajectory_marker_count):
		_trajectory_markers[marker_index].visible = false


func _get_trajectory_collision_point(from_global: Vector3, to_global: Vector3) -> Vector3:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_global, to_global)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return Vector3.INF

	return result.get("position") as Vector3


func _set_trajectory_marker(marker_index: int, local_position: Vector3) -> void:
	var marker: MeshInstance3D = _trajectory_markers[marker_index]
	var size_multiplier: float = 1.0 - float(marker_index) / float(trajectory_marker_count) * 0.55
	marker.position = local_position
	marker.scale = Vector3.ONE * size_multiplier
	marker.visible = true


func _hide_trajectory_visual() -> void:
	if _trajectory_root != null:
		_trajectory_root.visible = false

	for marker in _trajectory_markers:
		marker.visible = false


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
