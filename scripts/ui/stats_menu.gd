extends CanvasLayer

@onready var root: Control = $Root
@onready var stats_list: VBoxContainer = %StatsList

var _player: Node
var _value_labels: Dictionary = {}

var _rows := [
	{"key": "strength", "label": "Strength"},
	{"key": "strength_physical", "label": "Physical Strength"},
	{"key": "punch_damage", "label": "Punch Damage"},
	{"key": "strength_mental", "label": "Mental Strength"},
	{"key": "max_object_power", "label": "Max Object Power"},
	{"key": "push_pull_power", "label": "Push/Pull Power"},
	{"key": "stamina", "label": "Stamina"},
	{"key": "stamina_physical", "label": "Physical Stamina"},
	{"key": "punch_cooldown", "label": "Punch Cooldown"},
	{"key": "sprint", "label": "Sprint"},
	{"key": "stamina_mental", "label": "Mental Stamina"},
	{"key": "focus_capacity", "label": "Focus Capacity"},
	{"key": "physical_speed", "label": "Physical Speed"},
	{"key": "run_speed", "label": "Run Speed"},
	{"key": "mental_speed", "label": "Mental Speed"},
	{"key": "focus_recovery", "label": "Focus Recovery"},
	{"key": "time_stop_cooldown", "label": "Time Reset"},
	{"key": "hover_range", "label": "Hover Range"},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("stats_menu")
	root.visible = false
	_build_rows()
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	_sync_stats()


func _process(_delta: float) -> void:
	if root.visible:
		_sync_stats()


func open_menu() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sync_stats()
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_menu() -> void:
	if root.visible:
		close_menu()
	else:
		open_menu()


func is_open() -> bool:
	return root.visible


func _on_close_pressed() -> void:
	close_menu()


func _build_rows() -> void:
	for row_data in _rows:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(430, 30)
		stats_list.add_child(row)

		var label := Label.new()
		label.text = row_data["label"]
		label.custom_minimum_size = Vector2(210, 0)
		row.add_child(label)

		var value_label := Label.new()
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		_value_labels[row_data["key"]] = value_label


func _sync_stats() -> void:
	if _player == null or not _player.has_method("get_stats_snapshot"):
		return

	var stats: Dictionary = _player.call("get_stats_snapshot")
	_set_value("strength", "%.2f / %.0f" % [stats["strength"], stats["max_stat"]])
	_set_value("strength_physical", "+%s%%" % roundi((float(stats["strength_physical_scale"]) - 1.0) * 100.0))
	_set_value("punch_damage", str(stats["punch_damage"]))
	_set_value("strength_mental", "+%s%%" % roundi((float(stats["strength_mental_scale"]) - 1.0) * 100.0))
	_set_value("max_object_power", "%.1f" % stats["max_object_power"])
	_set_value("push_pull_power", "%.1f" % stats["push_pull_power"])
	_set_value("stamina", "%.2f / %.0f" % [stats["stamina"], stats["max_stat"]])
	_set_value("stamina_physical", "+%s%%" % roundi((float(stats["stamina_physical_scale"]) - 1.0) * 100.0))
	_set_value("punch_cooldown", "%.2fs" % stats["punch_cooldown"])
	_set_value("sprint", "%s / %s" % [roundi(stats["sprint"]), roundi(stats["sprint_capacity"])])
	_set_value("stamina_mental", "+%s%%" % roundi((float(stats["stamina_mental_scale"]) - 1.0) * 100.0))
	_set_value("focus_capacity", "%s" % roundi(stats["focus_capacity"]))
	_set_value("physical_speed", "%.2f / %.0f (+%s%%)" % [
		stats["physical_speed"],
		stats["max_stat"],
		roundi((float(stats["physical_speed_scale"]) - 1.0) * 100.0)
	])
	_set_value("run_speed", "%.1f" % stats["run_speed"])
	_set_value("mental_speed", "%.2f / %.0f (+%s%%)" % [
		stats["mental_speed"],
		stats["max_stat"],
		roundi((float(stats["mental_speed_scale"]) - 1.0) * 100.0)
	])
	_set_value("focus_recovery", "%.1f/s" % stats["focus_recovery"])
	_set_value("time_stop_cooldown", "%.1fs" % stats["time_stop_cooldown"])
	_set_value("hover_range", "%.1f" % stats["hover_range"])


func _set_value(key: String, text: String) -> void:
	if _value_labels.has(key):
		var label: Label = _value_labels[key]
		label.text = text
