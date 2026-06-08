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

@export_group("Spells")
@export var fling_rock_scene: PackedScene = preload("res://scenes/spells/fling_rock_projectile.tscn")
@export var fling_rock_spawn_distance := 1.4
@export var fling_rock_cooldown := 0.35
@export var fling_rock_min_speed := 7.0
@export var fling_rock_max_speed := 34.0
@export var fling_rock_full_charge_time := 1.4

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var _gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _look_rotation := Vector2.ZERO
var _can_cast_fling_rock := true
var _is_charging_fling_rock := false
var _fling_rock_charge_started_at := 0.0


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(current_health, maximum_health)
	gold_changed.emit(gold)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
		and event.button_index == MOUSE_BUTTON_LEFT
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		if event.pressed:
			_begin_charging_fling_rock()
		else:
			_release_fling_rock()

	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
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
	gold = max(gold + amount, 0)
	gold_changed.emit(gold)


func _begin_charging_fling_rock() -> void:
	if not _can_cast_fling_rock or fling_rock_scene == null:
		return

	_is_charging_fling_rock = true
	_fling_rock_charge_started_at = Time.get_ticks_msec() / 1000.0


func _release_fling_rock() -> void:
	if not _is_charging_fling_rock:
		return

	var charge_time := (Time.get_ticks_msec() / 1000.0) - _fling_rock_charge_started_at
	var charge_percent := clampf(charge_time / fling_rock_full_charge_time, 0.0, 1.0)
	var launch_speed := lerpf(fling_rock_min_speed, fling_rock_max_speed, charge_percent)
	_is_charging_fling_rock = false
	_cast_fling_rock(launch_speed)


func _cast_fling_rock(launch_speed: float) -> void:
	if not _can_cast_fling_rock or fling_rock_scene == null:
		return

	_can_cast_fling_rock = false

	var direction := -camera.global_basis.z.normalized()
	var projectile := fling_rock_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = camera.global_position + direction * fling_rock_spawn_distance

	if projectile is PhysicsBody3D:
		(projectile as PhysicsBody3D).add_collision_exception_with(self)

	if projectile.has_method("launch"):
		projectile.call("launch", direction, launch_speed, velocity)

	get_tree().create_timer(fling_rock_cooldown).timeout.connect(
		func() -> void:
			_can_cast_fling_rock = true
	)
