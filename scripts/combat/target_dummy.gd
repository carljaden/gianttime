extends StaticBody3D

@export var maximum_health := 60
@export var health_bar_width := 1.32

@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: MeshInstance3D = $HealthBar/Fill

var current_health: int = 0
var _camera: Camera3D


func _ready() -> void:
	current_health = maximum_health
	_camera = get_viewport().get_camera_3d()
	_update_health_bar()


func _process(_delta: float) -> void:
	if _camera != null:
		health_bar.look_at(_camera.global_position, Vector3.UP)


func take_damage(amount: int) -> void:
	current_health = maxi(current_health - amount, 0)
	_update_health_bar()
	print("Training target took %s damage. HP: %s/%s" % [amount, current_health, maximum_health])

	if current_health == 0:
		queue_free()


func _update_health_bar() -> void:
	var health_ratio: float = float(current_health) / float(maximum_health)
	health_fill.scale.x = health_ratio
	health_fill.position.x = -health_bar_width * (1.0 - health_ratio) * 0.5
