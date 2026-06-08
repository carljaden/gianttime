extends CharacterBody3D

signal health_changed(current_health: int, maximum_health: int)
signal gold_changed(gold: int)

@export_group("Vitals")
@export var maximum_health := 100
@export var current_health := 100
@export var gold := 25

@export_group("Movement")
@export var walk_speed := 5.0
@export var sprint_speed := 8.0
@export var jump_velocity := 4.5
@export var acceleration := 18.0
@export var air_acceleration := 6.0

@export_group("Mouse Look")
@export var mouse_sensitivity := 0.0025
@export var minimum_look_angle := -85.0
@export var maximum_look_angle := 85.0

@export_group("Tactical Gravity")
@export var planning_drag_strength := 0.08
@export var planning_scroll_strength := 2.0
@export var maximum_planned_impulse := 38.0
@export var planning_ray_length := 80.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var _gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _look_rotation := Vector2.ZERO
var _is_tactical_planning := false
var _is_dragging_vector := false
var _selected_movable: Node3D
var _hovered_movable: Node3D
var _planned_impulse := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(current_health, maximum_health)
	gold_changed.emit(gold)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and not (_is_tactical_planning and _is_dragging_vector)
	):
		_look_rotation.x -= event.relative.y * mouse_sensitivity
		_look_rotation.y -= event.relative.x * mouse_sensitivity
		_look_rotation.x = clamp(
			_look_rotation.x,
			deg_to_rad(minimum_look_angle),
			deg_to_rad(maximum_look_angle)
		)

		rotation.y = _look_rotation.y
		camera_pivot.rotation.x = _look_rotation.x

	if (
		event is InputEventMouseButton
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_toggle_tactical_planning()
		elif _is_tactical_planning:
			_handle_planning_mouse_button(event)

	if event is InputEventMouseMotion and _is_tactical_planning and _is_dragging_vector:
		_adjust_planned_impulse_from_drag(event.relative)

	if event.is_action_pressed("ui_cancel"):
		if _is_tactical_planning:
			_set_tactical_planning(false)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _is_tactical_planning and not _is_dragging_vector:
		_update_hovered_movable()


func _physics_process(delta: float) -> void:
	if _is_tactical_planning:
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	var target_speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target_velocity := move_direction * target_speed
	var current_acceleration := acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, current_acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, current_acceleration * delta)

	move_and_slide()


func take_damage(amount: int) -> void:
	current_health = clampi(current_health - amount, 0, maximum_health)
	health_changed.emit(current_health, maximum_health)


func heal(amount: int) -> void:
	current_health = clampi(current_health + amount, 0, maximum_health)
	health_changed.emit(current_health, maximum_health)


func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func _toggle_tactical_planning() -> void:
	_set_tactical_planning(not _is_tactical_planning)


func _set_tactical_planning(enabled: bool) -> void:
	_is_tactical_planning = enabled
	get_tree().paused = enabled

	if enabled:
		velocity = Vector3.ZERO
		_highlight_all_movable(true)
		_update_hovered_movable()
	else:
		if (
			_is_dragging_vector
			and _selected_movable != null
			and _selected_movable.has_method("queue_gravity_impulse")
		):
			_selected_movable.call("queue_gravity_impulse", _planned_impulse)

		_is_dragging_vector = false
		_selected_movable = null
		_hovered_movable = null
		_apply_all_planned_impulses()
		_highlight_all_movable(false)


func _handle_planning_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_selected_movable = _find_movable_under_crosshair()
			_planned_impulse = Vector3.ZERO
			_is_dragging_vector = _selected_movable != null
			if _selected_movable != null and _selected_movable.has_method("preview_gravity_impulse"):
				_selected_movable.call("preview_gravity_impulse", _planned_impulse)
			_refresh_movable_highlights()
		else:
			if _selected_movable != null and _selected_movable.has_method("queue_gravity_impulse"):
				_selected_movable.call("queue_gravity_impulse", _planned_impulse)
			_is_dragging_vector = false
			_selected_movable = null
			_update_hovered_movable()
	elif event.pressed and _selected_movable != null:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_planned_impulse_from_scroll(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_planned_impulse_from_scroll(-1.0)


func _adjust_planned_impulse_from_drag(relative_mouse_motion: Vector2) -> void:
	var right := camera.global_basis.x.normalized()
	var up := camera.global_basis.y.normalized()
	_planned_impulse += right * relative_mouse_motion.x * planning_drag_strength
	_planned_impulse += up * -relative_mouse_motion.y * planning_drag_strength
	_planned_impulse = _planned_impulse.limit_length(maximum_planned_impulse)
	_preview_selected_impulse()


func _adjust_planned_impulse_from_scroll(direction: float) -> void:
	var forward := -camera.global_basis.z.normalized()
	_planned_impulse += forward * direction * planning_scroll_strength
	_planned_impulse = _planned_impulse.limit_length(maximum_planned_impulse)
	_preview_selected_impulse()


func _update_hovered_movable() -> void:
	_hovered_movable = _find_movable_under_crosshair()
	_refresh_movable_highlights()


func _find_movable_under_crosshair() -> Node3D:
	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var end := origin + -camera.global_basis.z.normalized() * planning_ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider: Node = result.get("collider") as Node
	if collider != null and collider.is_in_group("gravity_movable"):
		return collider as Node3D

	return null


func _highlight_all_movable(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", enabled, false)


func _refresh_movable_highlights() -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		var is_selected := node == _selected_movable or node == _hovered_movable
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", _is_tactical_planning, is_selected)


func _apply_all_planned_impulses() -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if node.has_method("apply_planned_impulse"):
			node.call("apply_planned_impulse")


func _preview_selected_impulse() -> void:
	if _selected_movable != null and _selected_movable.has_method("preview_gravity_impulse"):
		_selected_movable.call("preview_gravity_impulse", _planned_impulse)
