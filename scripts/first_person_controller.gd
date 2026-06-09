extends CharacterBody3D

signal health_changed(current_health: int, maximum_health: int)
signal gold_changed(gold: int)
signal mental_fatigue_changed(current_fatigue: float, maximum_fatigue: float)
signal time_stop_changed(remaining_time: float, maximum_time: float, status: String)
signal sprint_stamina_changed(current_stamina: float, maximum_stamina: float)
signal stats_changed(stats: Dictionary)

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
@export var sprint_stamina_capacity := 100.0
@export var sprint_stamina_drain_rate := 24.0
@export var sprint_stamina_recovery_rate := 18.0

@export_group("Stats")
@export var strength := 1.0
@export var stamina := 1.0
@export var maximum_stat_value := 20.0
@export var strength_physical_bonus_per_point := 0.12
@export var strength_mental_bonus_per_point := 0.15
@export var stamina_physical_bonus_per_point := 0.12
@export var stamina_mental_bonus_per_point := 0.15
@export var strength_gain_per_punch := 0.035
@export var strength_gain_per_gravity_impulse := 0.001
@export var stamina_gain_per_sprint_second := 0.04
@export var stamina_gain_per_focus_spent := 0.001

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
@export var area_gravity_radius := 7.5
@export var area_gravity_impulse := 26.0
@export var momentum_reduction_step := 12.0
@export var time_stop_duration := 6.0
@export var time_stop_cooldown := 4.0
@export var maximum_mental_fatigue := 100.0
@export var fatigue_per_powered_item := 8.0
@export var fatigue_per_impulse := 1.0
@export var mental_fatigue_recovery_rate := 12.0

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
var _mental_fatigue := 0.0
var _mental_fatigue_planning_baseline := 0.0
var _time_stop_remaining := 0.0
var _time_stop_cooldown_remaining := 0.0
var _sprint_stamina := 0.0

const DEFAULT_ACTION_EVENTS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"stats_menu": [KEY_TAB],
	"gravity_plan": [MOUSE_BUTTON_RIGHT],
	"gravity_select": [MOUSE_BUTTON_LEFT],
	"gravity_pull_to_head": [MOUSE_BUTTON_MIDDLE],
	"gravity_plan_up": [KEY_E],
	"gravity_plan_down": [KEY_Q],
	"gravity_area_push": [KEY_SHIFT],
	"gravity_area_pull": [KEY_CTRL],
	"gravity_reduce_momentum": [KEY_F],
	"punch": [MOUSE_BUTTON_LEFT],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_default_input_actions()
	add_to_group("player")
	_right_fist_start_position = right_fist.position
	_sprint_stamina = _get_effective_sprint_stamina_capacity()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(current_health, maximum_health)
	gold_changed.emit(gold)
	_emit_mental_fatigue_changed()
	_emit_time_stop_changed()
	_emit_sprint_stamina_changed()
	_emit_stats_changed()


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

	if event.is_action_pressed("stats_menu"):
		if not _is_game_menu_open() and not _is_tactical_planning:
			_toggle_stats_menu()
		return

	if _is_tactical_planning and _is_action_pressed_by_event(event, "gravity_area_push"):
		_apply_area_gravity_impulse(false)
		return
	elif _is_tactical_planning and _is_action_pressed_by_event(event, "gravity_area_pull"):
		_apply_area_gravity_impulse(true)
		return
	elif _is_tactical_planning and _is_action_pressed_by_event(event, "gravity_reduce_momentum"):
		_reduce_selected_momentum()
		return

	if (
		event is InputEventMouseButton
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		if _is_action_pressed_by_event(event, "gravity_plan"):
			_toggle_tactical_planning()
		elif _is_tactical_planning:
			_handle_planning_mouse_button(event)
		elif _is_action_pressed_by_event(event, "punch"):
			_punch()

	if event.is_action_pressed("ui_cancel"):
		if _is_stats_menu_open():
			_toggle_stats_menu()
		elif _is_tactical_planning:
			_set_tactical_planning(false)
		elif _toggle_game_menu():
			pass
		else:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _is_game_menu_open() or _is_stats_menu_open():
		return

	if _is_tactical_planning:
		_time_stop_remaining -= _delta
		_emit_time_stop_changed()
		if _time_stop_remaining <= 0.0:
			_set_tactical_planning(false)
			return

		_update_hovered_nodes()
		_update_selected_impulse_from_keys()
	else:
		if _time_stop_cooldown_remaining > 0.0:
			_time_stop_cooldown_remaining = maxf(_time_stop_cooldown_remaining - _delta, 0.0)
			_emit_time_stop_changed()
		_recover_mental_fatigue(_delta)


func _physics_process(delta: float) -> void:
	if _is_tactical_planning or _is_game_menu_open() or _is_stats_menu_open():
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_direction := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_direction := (transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)).normalized()
	var wants_sprint := Input.is_action_pressed("sprint") and input_direction != Vector2.ZERO
	var can_sprint := wants_sprint and _sprint_stamina > 0.0
	var target_speed := sprint_speed if can_sprint else walk_speed
	var target_velocity := move_direction * target_speed
	var current_acceleration := acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, current_acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, current_acceleration * delta)

	move_and_slide()
	_update_sprint_stamina(delta, can_sprint)


func take_damage(amount: int) -> void:
	current_health = clampi(current_health - amount, 0, maximum_health)
	health_changed.emit(current_health, maximum_health)


func heal(amount: int) -> void:
	current_health = clampi(current_health + amount, 0, maximum_health)
	health_changed.emit(current_health, maximum_health)


func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func get_stats_snapshot() -> Dictionary:
	return {
		"strength": strength,
		"stamina": stamina,
		"max_stat": maximum_stat_value,
		"strength_physical_scale": _get_strength_physical_scale(),
		"strength_mental_scale": _get_strength_mental_scale(),
		"stamina_physical_scale": _get_stamina_physical_scale(),
		"stamina_mental_scale": _get_stamina_mental_scale(),
		"punch_damage": _get_effective_punch_damage(),
		"punch_cooldown": _get_effective_punch_cooldown(),
		"max_object_power": _get_effective_maximum_planned_impulse(),
		"push_pull_power": _get_effective_area_gravity_impulse(),
		"focus_capacity": _get_effective_maximum_mental_fatigue(),
		"sprint": _sprint_stamina,
		"sprint_capacity": _get_effective_sprint_stamina_capacity(),
	}


func refresh_mental_fatigue() -> void:
	strength = clampf(strength, 1.0, maximum_stat_value)
	stamina = clampf(stamina, 1.0, maximum_stat_value)
	_sprint_stamina = minf(_sprint_stamina, _get_effective_sprint_stamina_capacity())
	if _is_tactical_planning:
		_update_mental_fatigue()
	else:
		_mental_fatigue = clampf(_mental_fatigue, 0.0, _get_effective_maximum_mental_fatigue())
		_emit_mental_fatigue_changed()
	_emit_time_stop_changed()
	_emit_sprint_stamina_changed()
	_emit_stats_changed()


func _toggle_tactical_planning() -> void:
	if not _is_tactical_planning and _time_stop_cooldown_remaining > 0.0:
		return

	_set_tactical_planning(not _is_tactical_planning)


func _set_tactical_planning(enabled: bool) -> void:
	if enabled == _is_tactical_planning:
		return

	var was_planning := _is_tactical_planning
	_is_tactical_planning = enabled
	get_tree().paused = enabled

	if enabled:
		velocity = Vector3.ZERO
		_mental_fatigue_planning_baseline = _mental_fatigue
		_time_stop_remaining = time_stop_duration
		_emit_time_stop_changed()
		_highlight_all_tactical_nodes(true)
		_update_hovered_nodes()
	else:
		_selected_movable = null
		_hovered_movable = null
		_hovered_target = null
		_update_mental_fatigue()
		_apply_all_planned_impulses()
		_highlight_all_tactical_nodes(false)
		_emit_time_stop_changed()
		if was_planning:
			_time_stop_cooldown_remaining = time_stop_cooldown
			_emit_time_stop_changed()


func _handle_planning_mouse_button(event: InputEventMouseButton) -> void:
	if _is_action_pressed_by_event(event, "gravity_select"):
		_handle_planning_left_click()
	elif _is_action_pressed_by_event(event, "gravity_pull_to_head") and _selected_movable != null:
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
	_planned_magnitude = _get_effective_auto_target_impulse()
	_constrain_planned_magnitude_for_fatigue()
	_update_planned_impulse()
	_queue_selected_impulse()


func _pull_selected_toward_head() -> void:
	var direction := camera.global_position - _selected_movable.global_position
	if direction.length() < 0.05:
		return

	_planned_direction = direction.normalized()
	_planned_magnitude = _get_effective_pull_to_head_impulse()
	_constrain_planned_magnitude_for_fatigue()
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

	if Input.is_action_pressed("gravity_plan_up"):
		impulse_delta += Vector3.UP
	if Input.is_action_pressed("gravity_plan_down"):
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
		_planned_magnitude = _get_effective_planning_default_magnitude()
	_constrain_planned_magnitude_for_fatigue()
	_update_planned_impulse()
	_queue_selected_impulse()


func _adjust_planned_impulse_from_scroll(direction: float) -> void:
	if _planned_direction == Vector3.ZERO:
		_planned_direction = -camera.global_basis.z.normalized()

	_planned_magnitude = clampf(
		_planned_magnitude + direction * planning_scroll_magnitude_step,
		0.0,
		_get_effective_maximum_planned_impulse()
	)
	_constrain_planned_magnitude_for_fatigue()
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
			var applied_impulse: Vector3 = node.call("apply_planned_impulse")
			if applied_impulse != Vector3.ZERO:
				_gain_strength(applied_impulse.length() * strength_gain_per_gravity_impulse)
				_gain_stamina(_get_fatigue_cost_for_impulse(applied_impulse) * stamina_gain_per_focus_spent)


func _apply_area_gravity_impulse(pull: bool) -> void:
	if _is_game_menu_open() or not _is_tactical_planning:
		return

	_set_tactical_planning(false)

	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if not (node is RigidBody3D):
			continue

		var body := node as RigidBody3D
		var offset := body.global_position - global_position
		var distance := offset.length()
		if distance < 0.05 or distance > area_gravity_radius:
			continue

		var direction := -offset.normalized() if pull else offset.normalized()
		var distance_falloff := 1.0 - distance / area_gravity_radius
		var impulse := direction * _get_effective_area_gravity_impulse() * lerpf(0.35, 1.0, distance_falloff)
		var fatigue_cost := _get_fatigue_cost_for_impulse(impulse)
		if not _try_add_mental_fatigue(fatigue_cost):
			continue

		body.sleeping = false
		body.apply_central_impulse(impulse)
		_gain_strength(impulse.length() * strength_gain_per_gravity_impulse)
		_gain_stamina(fatigue_cost * stamina_gain_per_focus_spent)


func _reduce_selected_momentum() -> void:
	if _selected_movable == null or not _selected_movable.has_method("reduce_linear_momentum"):
		return

	_selected_movable.call("reduce_linear_momentum", momentum_reduction_step)


func _queue_selected_impulse() -> void:
	if _selected_movable != null and _selected_movable.has_method("queue_gravity_impulse"):
		_selected_movable.call("queue_gravity_impulse", _planned_impulse)
	_update_mental_fatigue()


func _update_planned_impulse() -> void:
	if _planned_direction == Vector3.ZERO or _planned_magnitude <= 0.0:
		_planned_impulse = Vector3.ZERO
	else:
		_planned_impulse = _planned_direction.normalized() * _planned_magnitude


func _constrain_planned_magnitude_for_fatigue() -> void:
	if _selected_movable == null:
		return

	var other_fatigue := _get_planned_fatigue(_selected_movable)
	var available_fatigue := _get_effective_maximum_mental_fatigue() - _mental_fatigue_planning_baseline - other_fatigue
	if available_fatigue < fatigue_per_powered_item:
		_planned_magnitude = 0.0
		return
	if fatigue_per_impulse <= 0.0:
		return

	var maximum_allowed_magnitude := (available_fatigue - fatigue_per_powered_item) / fatigue_per_impulse
	_planned_magnitude = clampf(_planned_magnitude, 0.0, maximum_allowed_magnitude)


func _update_mental_fatigue() -> void:
	var planned_fatigue := _get_planned_fatigue()
	_mental_fatigue = clampf(_mental_fatigue_planning_baseline + planned_fatigue, 0.0, _get_effective_maximum_mental_fatigue())
	_emit_mental_fatigue_changed()


func _get_planned_fatigue(excluded_node: Node = null) -> float:
	var fatigue := 0.0
	for node in get_tree().get_nodes_in_group("gravity_movable"):
		if node == excluded_node:
			continue
		if node.has_method("get_mental_fatigue_cost"):
			fatigue += float(node.call("get_mental_fatigue_cost", fatigue_per_powered_item, fatigue_per_impulse))
	return fatigue


func _get_fatigue_cost_for_impulse(impulse: Vector3) -> float:
	if impulse == Vector3.ZERO:
		return 0.0

	return fatigue_per_powered_item + impulse.length() * fatigue_per_impulse


func _try_add_mental_fatigue(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if _mental_fatigue + amount > _get_effective_maximum_mental_fatigue():
		return false

	_mental_fatigue = clampf(_mental_fatigue + amount, 0.0, _get_effective_maximum_mental_fatigue())
	_mental_fatigue_planning_baseline = _mental_fatigue
	_emit_mental_fatigue_changed()
	return true


func _recover_mental_fatigue(delta: float) -> void:
	if _mental_fatigue <= 0.0 or mental_fatigue_recovery_rate <= 0.0:
		return

	_mental_fatigue = maxf(_mental_fatigue - mental_fatigue_recovery_rate * delta, 0.0)
	_emit_mental_fatigue_changed()


func _emit_mental_fatigue_changed() -> void:
	mental_fatigue_changed.emit(_mental_fatigue, _get_effective_maximum_mental_fatigue())


func _emit_time_stop_changed() -> void:
	if _is_tactical_planning:
		time_stop_changed.emit(maxf(_time_stop_remaining, 0.0), time_stop_duration, "active")
	elif _time_stop_cooldown_remaining > 0.0:
		time_stop_changed.emit(_time_stop_cooldown_remaining, time_stop_cooldown, "cooldown")
	else:
		time_stop_changed.emit(0.0, time_stop_duration, "ready")


func _update_sprint_stamina(delta: float, is_sprinting: bool) -> void:
	var maximum_sprint := _get_effective_sprint_stamina_capacity()
	var previous_stamina := _sprint_stamina

	if is_sprinting:
		_sprint_stamina = maxf(_sprint_stamina - sprint_stamina_drain_rate * delta, 0.0)
		_gain_stamina(stamina_gain_per_sprint_second * delta)
	else:
		_sprint_stamina = minf(
			_sprint_stamina + _get_effective_sprint_stamina_recovery_rate() * delta,
			maximum_sprint
		)

	if not is_equal_approx(previous_stamina, _sprint_stamina):
		_emit_sprint_stamina_changed()


func _get_stat_scale(stat_value: float, bonus_per_point: float) -> float:
	return 1.0 + maxf(stat_value - 1.0, 0.0) * bonus_per_point


func _get_strength_physical_scale() -> float:
	return _get_stat_scale(strength, strength_physical_bonus_per_point)


func _get_strength_mental_scale() -> float:
	return _get_stat_scale(strength, strength_mental_bonus_per_point)


func _get_stamina_physical_scale() -> float:
	return _get_stat_scale(stamina, stamina_physical_bonus_per_point)


func _get_stamina_mental_scale() -> float:
	return _get_stat_scale(stamina, stamina_mental_bonus_per_point)


func _get_effective_punch_damage() -> int:
	return maxi(roundi(float(punch_damage) * _get_strength_physical_scale()), 1)


func _get_effective_punch_impulse() -> float:
	return punch_impulse * _get_strength_physical_scale()


func _get_effective_punch_cooldown() -> float:
	return maxf(punch_cooldown / _get_stamina_physical_scale(), 0.05)


func _get_effective_sprint_stamina_capacity() -> float:
	return sprint_stamina_capacity * _get_stamina_physical_scale()


func _get_effective_sprint_stamina_recovery_rate() -> float:
	return sprint_stamina_recovery_rate * _get_stamina_physical_scale()


func _get_effective_maximum_planned_impulse() -> float:
	return maximum_planned_impulse * _get_strength_mental_scale()


func _get_effective_planning_default_magnitude() -> float:
	return minf(planning_default_magnitude * _get_strength_mental_scale(), _get_effective_maximum_planned_impulse())


func _get_effective_auto_target_impulse() -> float:
	return minf(auto_target_impulse * _get_strength_mental_scale(), _get_effective_maximum_planned_impulse())


func _get_effective_pull_to_head_impulse() -> float:
	return minf(pull_to_head_impulse * _get_strength_mental_scale(), _get_effective_maximum_planned_impulse())


func _get_effective_area_gravity_impulse() -> float:
	return area_gravity_impulse * _get_strength_mental_scale()


func _get_effective_maximum_mental_fatigue() -> float:
	return maximum_mental_fatigue * _get_stamina_mental_scale()


func _gain_strength(amount: float) -> void:
	if amount <= 0.0:
		return

	var previous_strength := strength
	strength = clampf(strength + amount, 1.0, maximum_stat_value)
	if not is_equal_approx(previous_strength, strength):
		_emit_stats_changed()


func _gain_stamina(amount: float) -> void:
	if amount <= 0.0:
		return

	var previous_stamina := stamina
	var previous_sprint_max := _get_effective_sprint_stamina_capacity()
	stamina = clampf(stamina + amount, 1.0, maximum_stat_value)
	if is_equal_approx(previous_stamina, stamina):
		return

	var new_sprint_max := _get_effective_sprint_stamina_capacity()
	_sprint_stamina += maxf(new_sprint_max - previous_sprint_max, 0.0)
	_sprint_stamina = minf(_sprint_stamina, new_sprint_max)
	_mental_fatigue = clampf(_mental_fatigue, 0.0, _get_effective_maximum_mental_fatigue())
	_emit_stats_changed()
	_emit_sprint_stamina_changed()
	_emit_mental_fatigue_changed()


func _emit_sprint_stamina_changed() -> void:
	sprint_stamina_changed.emit(_sprint_stamina, _get_effective_sprint_stamina_capacity())


func _emit_stats_changed() -> void:
	stats_changed.emit(get_stats_snapshot())


func _punch() -> void:
	if not _can_punch:
		return

	_can_punch = false
	_animate_punch()
	_apply_punch_hit()
	_gain_strength(strength_gain_per_punch)
	get_tree().create_timer(_get_effective_punch_cooldown()).timeout.connect(
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
		collider.call("take_damage", _get_effective_punch_damage())

	if collider is RigidBody3D:
		(collider as RigidBody3D).apply_central_impulse(direction * _get_effective_punch_impulse())


func _toggle_game_menu() -> bool:
	var menu := get_tree().get_first_node_in_group("game_menu")
	if menu == null or not menu.has_method("toggle_menu"):
		return false

	menu.call("toggle_menu")
	return true


func _toggle_stats_menu() -> bool:
	var menu := get_tree().get_first_node_in_group("stats_menu")
	if menu == null or not menu.has_method("toggle_menu"):
		return false

	menu.call("toggle_menu")
	return true


func _is_game_menu_open() -> bool:
	var menu := get_tree().get_first_node_in_group("game_menu")
	if menu == null or not menu.has_method("is_open"):
		return false

	return bool(menu.call("is_open"))


func _is_stats_menu_open() -> bool:
	var menu := get_tree().get_first_node_in_group("stats_menu")
	if menu == null or not menu.has_method("is_open"):
		return false

	return bool(menu.call("is_open"))


func _is_action_pressed_by_event(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(action)


func _ensure_default_input_actions() -> void:
	for action_name in DEFAULT_ACTION_EVENTS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		if not InputMap.action_get_events(action_name).is_empty():
			continue

		for event_code in DEFAULT_ACTION_EVENTS[action_name]:
			InputMap.action_add_event(action_name, _create_input_event(event_code))


func _create_input_event(event_code: int) -> InputEvent:
	if event_code >= MOUSE_BUTTON_LEFT and event_code <= MOUSE_BUTTON_XBUTTON2:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = event_code
		return mouse_event

	var key_event := InputEventKey.new()
	key_event.keycode = event_code
	return key_event
