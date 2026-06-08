extends CanvasLayer

@onready var root: Control = $Root
@onready var settings_list: VBoxContainer = %SettingsList
@onready var settings_panel: PanelContainer = %SettingsPanel

var _player: Node
var _settings_controls: Dictionary = {}

var _settings := [
	{"label": "Mouse Look", "property": "mouse_sensitivity", "min": 0.0005, "max": 0.01, "step": 0.0005},
	{"label": "Default Force", "property": "planning_default_magnitude", "min": 1.0, "max": 60.0, "step": 1.0},
	{"label": "Direction Sensitivity", "property": "planning_direction_turn_rate", "min": 0.25, "max": 12.0, "step": 0.25},
	{"label": "Scroll Force Step", "property": "planning_scroll_magnitude_step", "min": 0.5, "max": 12.0, "step": 0.5},
	{"label": "Maximum Force", "property": "maximum_planned_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Auto Target Force", "property": "auto_target_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Pull To Head Force", "property": "pull_to_head_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Punch Damage", "property": "punch_damage", "min": 1.0, "max": 50.0, "step": 1.0},
	{"label": "Punch Range", "property": "punch_range", "min": 0.5, "max": 5.0, "step": 0.1},
	{"label": "Punch Push", "property": "punch_impulse", "min": 0.0, "max": 40.0, "step": 1.0},
	{"label": "Punch Cooldown", "property": "punch_cooldown", "min": 0.05, "max": 2.0, "step": 0.05},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_menu")
	root.visible = false
	settings_panel.visible = false
	_build_settings()
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group("player")
	_sync_settings_from_player()


func open_menu() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_sync_settings_from_player()
	root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	root.visible = false
	settings_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_menu() -> void:
	if root.visible:
		close_menu()
	else:
		open_menu()


func is_open() -> bool:
	return root.visible


func _on_resume_pressed() -> void:
	close_menu()


func _on_reset_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible


func _build_settings() -> void:
	for setting in _settings:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(460, 34)
		settings_list.add_child(row)

		var label := Label.new()
		label.text = setting["label"]
		label.custom_minimum_size = Vector2(210, 0)
		row.add_child(label)

		var slider := HSlider.new()
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.min_value = setting["min"]
		slider.max_value = setting["max"]
		slider.step = setting["step"]
		row.add_child(slider)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(64, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)

		var property_name: String = setting["property"]
		_settings_controls[property_name] = {
			"slider": slider,
			"value_label": value_label,
			"step": float(setting["step"]),
		}
		slider.value_changed.connect(
			func(value: float) -> void:
				_apply_setting(property_name, value)
		)


func _sync_settings_from_player() -> void:
	if _player == null:
		return

	for property_name in _settings_controls.keys():
		var value: float = float(_player.get(property_name))
		var slider: HSlider = _settings_controls[property_name]["slider"]
		slider.set_value_no_signal(value)
		_update_value_label(property_name, value)


func _apply_setting(property_name: String, value: float) -> void:
	if _player == null:
		return

	var current_value = _player.get(property_name)
	if current_value is int:
		_player.set(property_name, roundi(value))
	else:
		_player.set(property_name, value)

	_update_value_label(property_name, value)


func _update_value_label(property_name: String, value: float) -> void:
	var value_label: Label = _settings_controls[property_name]["value_label"]
	var step: float = _settings_controls[property_name]["step"]
	if step < 0.1:
		value_label.text = "%.4f" % value
	elif step < 1.0:
		value_label.text = "%.2f" % value
	else:
		value_label.text = "%.0f" % value
