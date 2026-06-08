extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_text: Label = %HealthText
@onready var gold_text: Label = %GoldText

var _player


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")

	if _player == null:
		_set_health(0, 100)
		_set_gold(0)
		return

	if _player.has_signal("health_changed"):
		_player.health_changed.connect(_set_health)
	if _player.has_signal("gold_changed"):
		_player.gold_changed.connect(_set_gold)

	var current_health: int = int(_player.get("current_health"))
	var maximum_health: int = int(_player.get("maximum_health"))
	var gold: int = int(_player.get("gold"))
	_set_health(current_health, maximum_health)
	_set_gold(gold)


func _set_health(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_text.text = "%s / %s" % [current_health, maximum_health]


func _set_gold(gold: int) -> void:
	gold_text.text = str(gold)
