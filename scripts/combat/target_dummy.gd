extends StaticBody3D

@export var maximum_health := 60
@export var health_bar_width := 1.32

@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: MeshInstance3D = $HealthBar/Fill

var current_health: int = 0
var _camera: Camera3D
var _highlight_material: StandardMaterial3D = StandardMaterial3D.new()
var _selected_material: StandardMaterial3D = StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("gravity_target")
	current_health = maximum_health
	_camera = get_viewport().get_camera_3d()
	_highlight_material.albedo_color = Color(1.0, 0.24, 0.18, 0.42)
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selected_material.albedo_color = Color(1.0, 0.78, 0.18, 0.62)
	_selected_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selected_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


func set_tactical_highlight(enabled: bool, selected: bool = false) -> void:
	if selected:
		_set_overlay(_selected_material)
	elif enabled:
		_set_overlay(_highlight_material)
	else:
		_set_overlay(null)


func _update_health_bar() -> void:
	var health_ratio: float = float(current_health) / float(maximum_health)
	health_fill.scale.x = health_ratio
	health_fill.position.x = -health_bar_width * (1.0 - health_ratio) * 0.5


func _set_overlay(material: Material) -> void:
	for child in get_children():
		if child is MeshInstance3D:
			child.material_overlay = material
