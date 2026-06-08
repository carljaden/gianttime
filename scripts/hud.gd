extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var health_text: Label = %HealthText
@onready var fatigue_bar: ProgressBar = %FatigueBar
@onready var fatigue_text: Label = %FatigueText
@onready var time_stop_bar: ProgressBar = %TimeStopBar
@onready var time_stop_label: Label = %TimeStopLabel
@onready var time_stop_text: Label = %TimeStopText
@onready var gold_text: Label = %GoldText

var _player


func _ready() -> void:
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")

	if _player == null:
		_set_health(0, 100)
		_set_mental_fatigue(0.0, 100.0)
		_set_time_stop(0.0, 1.0, "ready")
		_set_gold(0)
		return

	if _player.has_signal("health_changed"):
		_player.health_changed.connect(_set_health)
	if _player.has_signal("gold_changed"):
		_player.gold_changed.connect(_set_gold)
	if _player.has_signal("mental_fatigue_changed"):
		_player.mental_fatigue_changed.connect(_set_mental_fatigue)
	if _player.has_signal("time_stop_changed"):
		_player.time_stop_changed.connect(_set_time_stop)

	var current_health: int = int(_player.get("current_health"))
	var maximum_health: int = int(_player.get("maximum_health"))
	var gold: int = int(_player.get("gold"))
	var current_fatigue: float = float(_player.get("_mental_fatigue"))
	var maximum_fatigue: float = float(_player.get("maximum_mental_fatigue"))
	var time_stop_duration: float = float(_player.get("time_stop_duration"))
	_set_health(current_health, maximum_health)
	_set_mental_fatigue(current_fatigue, maximum_fatigue)
	_set_time_stop(0.0, time_stop_duration, "ready")
	_set_gold(gold)


func _set_health(current_health: int, maximum_health: int) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_text.text = "%s / %s" % [current_health, maximum_health]


func _set_mental_fatigue(current_fatigue: float, maximum_fatigue: float) -> void:
	fatigue_bar.max_value = maximum_fatigue
	fatigue_bar.value = current_fatigue
	fatigue_text.text = "%s / %s" % [roundi(current_fatigue), roundi(maximum_fatigue)]


func _set_time_stop(remaining_time: float, maximum_time: float, status: String = "active") -> void:
	time_stop_bar.max_value = maxf(maximum_time, 0.01)
	time_stop_bar.value = clampf(remaining_time, 0.0, time_stop_bar.max_value)
	if status == "cooldown":
		time_stop_label.text = "Cooldown"
		time_stop_text.text = "%.1fs" % maxf(remaining_time, 0.0)
	elif status == "ready":
		time_stop_label.text = "Time"
		time_stop_text.text = "Ready"
	else:
		time_stop_label.text = "Time"
		time_stop_text.text = "%.1fs" % maxf(remaining_time, 0.0)


func _set_gold(gold: int) -> void:
	gold_text.text = str(gold)
