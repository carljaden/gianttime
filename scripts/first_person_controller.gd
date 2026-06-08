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
@export var planning_default_magnitude := 16.0
@export var planning_direction_turn_rate := 2.0
@export var planning_scroll_magnitude_step := 3.0
@export var maximum_planned_impulse := 38.0
@export var planning_ray_length := 80.0
@export var auto_target_impulse := 34.0
@export var pull_to_head_impulse := 30.0

@export_group("Melee")
@export var punch_damage := 8
@export var punch_range := 1.8
@export var punch_impulse := 8.0
@export var punch_cooldown := 0.35

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var right_fist: Node3D = $CameraPivot/Camera3D/Fists/RightFist

var _gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _look_rotation := Vector2.ZERO
var _is_tactical_planning := false
var _selected_movable: Node3D
var _hovered_movable: Node3D
var _hovered_target: Node3D
var _planned_impulse := Vector3.ZERO
var _planned_direction := Vector3.ZERO
var _planned_magnitude := 0.0
var _can_punch := true
var _right_fist_start_position := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("player")
	_right_fist_start_position = right_fist.position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(current_health, maximum_health)
	gold_changed.emit(gold)


func _input(event: InputEvent) -> void:
	if (
		event is InputEventMouseMotion
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
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
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_punch()

	if event.is_action_pressed("ui_cancel"):
		if _is_tactical_planning:
			_set_tactical_planning(false)
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _is_tactical_planning:
		_update_hovered_nodes()
		_update_selected_impulse_from_keys()


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
		_highlight_all_tactical_nodes(true)
		_update_hovered_nodes()
	else:
		_selected_movable = null
		_hovered_movable = null
		_hovered_target = null
		_apply_all_planned_impulses()
		_highlight_all_tactical_nodes(false)


func _handle_planning_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_handle_planning_left_click()
	elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed and _selected_movable != null:
		_pull_selected_toward_head()
	elif event.pressed and _selected_movable != null:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_planned_impulse_from_scroll(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_planned_impulse_from_scroll(-1.0)


func _handle_planning_left_click() -> void:
	var clicked_movable := _find_movable_under_crosshair()
	var clicked_target := _find_target_under_crosshair()

	if clicked_movable != null:
		_select_movable(clicked_movable)
	elif clicked_target != null and _selected_movable != null:
		_target_selected_movable(clicked_target)
	else:
		_select_movable(null)

	_refresh_tactical_highlights()


func _select_movable(movable: Node3D) -> void:
	_selected_movable = movable
	_planned_impulse = Vector3.ZERO
	_planned_direction = Vector3.ZERO
	_planned_magnitude = 0.0

	if _selected_movable != null and _selected_movable.has_method("preview_gravity_impulse"):
		_selected_movable.call("preview_gravity_impulse", _planned_impulse)


func _target_selected_movable(target: Node3D) -> void:
	var direction := target.global_position - _selected_movable.global_position
	if direction.length() < 0.05:
		return

	_planned_direction = direction.normalized()
	_planned_magnitude = auto_target_impulse
	_update_planned_impulse()
	_queue_selected_impulse()


func _pull_selected_toward_head() -> void:
	var direction := camera.global_position - _selected_movable.global_position
	if direction.length() < 0.05:
		return

	_planned_direction = direction.normalized()
	_planned_magnitude = pull_to_head_impulse
	_update_planned_impulse()
	_queue_selected_impulse()


func _update_selected_impulse_from_keys() -> void:
	if _selected_movable == null:
		return

	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var horizontal_forward := -camera.global_basis.z
	horizontal_forward.y = 0.0

	if horizontal_forward.length() < 0.05:
		horizontal_forward = -global_basis.z

	horizontal_forward = horizontal_forward.normalized()
	var horizontal_right := camera.global_basis.x
	horizontal_right.y = 0.0
	horizontal_right = horizontal_right.normalized()
	var impulse_delta := Vector3.ZERO
	impulse_delta += horizontal_right * input_direction.x
	impulse_delta += horizontal_forward * -input_direction.y

	if Input.is_key_pressed(KEY_E):
		impulse_delta += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		impulse_delta += Vector3.DOWN

	if impulse_delta == Vector3.ZERO:
		return

	var target_direction := impulse_delta.normalized()
	if _planned_direction == Vector3.ZERO:
		_planned_direction = target_direction
	else:
		var turn_amount := clampf(planning_direction_turn_rate * get_process_delta_time(), 0.0, 1.0)
		_planned_direction = _planned_direction.slerp(target_direction, turn_amount).normalized()

	if _planned_magnitude <= 0.0:
		_planned_magnitude = planning_default_magnitude
	_update_planned_impulse()
	_queue_selected_impulse()


func _adjust_planned_impulse_from_scroll(direction: float) -> void:
	if _planned_direction == Vector3.ZERO:
		_planned_direction = -camera.global_basis.z.normalized()

	_planned_magnitude = clampf(
		_planned_magnitude + direction * planning_scroll_magnitude_step,
		0.0,
		maximum_planned_impulse
	)
	_update_planned_impulse()
	_queue_selected_impulse()


func _update_hovered_nodes() -> void:
	_hovered_movable = _find_movable_under_crosshair()
	_hovered_target = _find_target_under_crosshair()
	_refresh_tactical_highlights()


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


func _find_target_under_crosshair() -> Node3D:
	var space_state := get_world_3d().direct_space_state
	var origin := camera.global_position
	var end := origin + -camera.global_basis.z.normalized() * planning_ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var collider: Node = result.get("collider") as Node
	if collider != null and collider.is_in_group("gravity_target"):
		return collider as Node3D

	return null


func _highlight_all_tactical_nodes(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", enabled, false)
	for node in get_tree().get_nodes_in_group("gravity_target"):
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", enabled, false)


func _refresh_tactical_highlights() -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		var is_selected := node == _selected_movable or node == _hovered_movable
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", _is_tactical_planning, is_selected)
	for node in get_tree().get_nodes_in_group("gravity_target"):
		var is_selected := node == _hovered_target
		if node.has_method("set_tactical_highlight"):
			node.call("set_tactical_highlight", _is_tactical_planning, is_selected)


func _apply_all_planned_impulses() -> void:
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if node.has_method("apply_planned_impulse"):
			node.call("apply_planned_impulse")


func _queue_selected_impulse() -> void:
	if _selected_movable != null and _selected_movable.has_method("queue_gravity_impulse"):
		_selected_movable.call("queue_gravity_impulse", _planned_impulse)


func _update_planned_impulse() -> void:
	if _planned_direction == Vector3.ZERO or _planned_magnitude <= 0.0:
		_planned_impulse = Vector3.ZERO
	else:
		_planned_impulse = _planned_direction.normalized() * _planned_magnitude


func _punch() -> void:
	if not _can_punch:
		return

	_can_punch = false
	_animate_punch()
	_apply_punch_hit()
	get_tree().create_timer(punch_cooldown).timeout.connect(
		func() -> void:
			_can_punch = true
	)


func _animate_punch() -> void:
	var tween := create_tween()
	tween.tween_property(right_fist, "position", _right_fist_start_position + Vector3(-0.04, 0.04, -0.34), 0.08)
	tween.tween_property(right_fist, "position", _right_fist_start_position, 0.16)


func _apply_punch_hit() -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = camera.global_position
	var direction: Vector3 = -camera.global_basis.z.normalized()
	var end: Vector3 = origin + direction * punch_range
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [self]

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return

	var collider: Node = result.get("collider") as Node
	if collider == null:
		return

	if collider.has_method("take_damage"):
		collider.call("take_damage", punch_damage)

	if collider is RigidBody3D:
		(collider as RigidBody3D).apply_central_impulse(direction * punch_impulse)
