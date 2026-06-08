extends RigidBody3D

@export var damage_per_speed := 1.4
@export var minimum_damage := 4
@export var lifetime := 6.0

var _has_hit := false
var _queued_direction := Vector3.ZERO
var _queued_launch_speed := 0.0
var _queued_inherited_velocity := Vector3.ZERO


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(Callable(self, "queue_free"))


func launch(direction: Vector3, launch_speed: float, inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	_queued_direction = direction.normalized()
	_queued_launch_speed = launch_speed
	_queued_inherited_velocity = inherited_velocity
	call_deferred("_apply_launch_velocity")


func _apply_launch_velocity() -> void:
	await get_tree().physics_frame
	sleeping = false
	linear_velocity = _queued_inherited_velocity
	apply_central_impulse(_queued_direction * _queued_launch_speed * mass)
	angular_velocity = Vector3(9.0, 13.0, 6.0) * clampf(_queued_launch_speed / 12.0, 0.6, 3.0)


func _on_body_entered(body: Node) -> void:
	if _has_hit:
		return

	_has_hit = true
	var impact_speed: float = linear_velocity.length()
	var speed_damage: int = roundi(impact_speed * damage_per_speed)
	var damage: int = maxi(minimum_damage, speed_damage)

	if body.has_method("take_damage"):
		body.take_damage(damage)

	linear_velocity *= 0.2
	angular_velocity *= 0.35
	await get_tree().create_timer(0.15).timeout
	queue_free()
