extends CanvasLayer

@onready var root: Control = $Root
@onready var settings_list: VBoxContainer = %SettingsList
@onready var settings_panel: PanelContainer = %SettingsPanel

var _player: Node
var _settings_controls: Dictionary = {}
var _keybind_buttons: Dictionary = {}
var _rebinding_action := ""

const DEFAULT_ACTION_EVENTS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
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

var _settings := [
	{"label": "Mouse Look", "property": "mouse_sensitivity", "min": 0.0005, "max": 0.01, "step": 0.0005},
	{"label": "Default Force", "property": "planning_default_magnitude", "min": 1.0, "max": 60.0, "step": 1.0},
	{"label": "Direction Sensitivity", "property": "planning_direction_turn_rate", "min": 0.25, "max": 12.0, "step": 0.25},
	{"label": "Scroll Force Step", "property": "planning_scroll_magnitude_step", "min": 0.5, "max": 12.0, "step": 0.5},
	{"label": "Maximum Force", "property": "maximum_planned_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Auto Target Force", "property": "auto_target_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Pull To Head Force", "property": "pull_to_head_impulse", "min": 5.0, "max": 100.0, "step": 1.0},
	{"label": "Area Radius", "property": "area_gravity_radius", "min": 1.0, "max": 18.0, "step": 0.5},
	{"label": "Area Push/Pull", "property": "area_gravity_impulse", "min": 1.0, "max": 80.0, "step": 1.0},
	{"label": "Momentum Slow", "property": "momentum_reduction_step", "min": 0.0, "max": 80.0, "step": 1.0},
	{"label": "Time Stop Duration", "property": "time_stop_duration", "min": 0.5, "max": 20.0, "step": 0.5},
	{"label": "Time Stop Cooldown", "property": "time_stop_cooldown", "min": 0.0, "max": 20.0, "step": 0.5},
	{"label": "Focus Capacity", "property": "maximum_mental_fatigue", "min": 10.0, "max": 300.0, "step": 5.0},
	{"label": "Focus Per Object", "property": "fatigue_per_powered_item", "min": 0.0, "max": 50.0, "step": 1.0},
	{"label": "Focus Per Force", "property": "fatigue_per_impulse", "min": 0.1, "max": 5.0, "step": 0.1},
	{"label": "Focus Recovery", "property": "mental_fatigue_recovery_rate", "min": 0.0, "max": 80.0, "step": 1.0},
	{"label": "Punch Damage", "property": "punch_damage", "min": 1.0, "max": 50.0, "step": 1.0},
	{"label": "Punch Range", "property": "punch_range", "min": 0.5, "max": 5.0, "step": 0.1},
	{"label": "Punch Push", "property": "punch_impulse", "min": 0.0, "max": 40.0, "step": 1.0},
	{"label": "Punch Cooldown", "property": "punch_cooldown", "min": 0.05, "max": 2.0, "step": 0.05},
]

var _keybinds := [
	{"label": "Move Forward", "action": "move_forward"},
	{"label": "Move Back", "action": "move_back"},
	{"label": "Move Left", "action": "move_left"},
	{"label": "Move Right", "action": "move_right"},
	{"label": "Jump", "action": "jump"},
	{"label": "Sprint", "action": "sprint"},
	{"label": "Stop Time", "action": "gravity_plan"},
	{"label": "Select/Throw", "action": "gravity_select"},
	{"label": "Pull To Head", "action": "gravity_pull_to_head"},
	{"label": "Plan Up", "action": "gravity_plan_up"},
	{"label": "Plan Down", "action": "gravity_plan_down"},
	{"label": "Sphere Push", "action": "gravity_area_push"},
	{"label": "Sphere Pull", "action": "gravity_area_pull"},
	{"label": "Slow Momentum", "action": "gravity_reduce_momentum"},
	{"label": "Punch", "action": "punch"},
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("game_menu")
	root.visible = false
	settings_panel.visible = false
	_ensure_default_input_actions()
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
	_rebinding_action = ""
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _rebinding_action.is_empty():
		return

	if not root.visible:
		_rebinding_action = ""
		return

	var captured_event := _get_rebind_event(event)
	if captured_event == null:
		return

	InputMap.action_erase_events(_rebinding_action)
	InputMap.action_add_event(_rebinding_action, captured_event)
	_refresh_keybind_button(_rebinding_action)
	_rebinding_action = ""
	get_viewport().set_input_as_handled()


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
	_add_settings_header("Tuning")
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

	_add_settings_header("Keybinds")
	for keybind in _keybinds:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(460, 34)
		settings_list.add_child(row)

		var label := Label.new()
		label.text = keybind["label"]
		label.custom_minimum_size = Vector2(210, 0)
		row.add_child(label)

		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)

		var action_name: String = keybind["action"]
		_keybind_buttons[action_name] = button
		button.pressed.connect(
			func() -> void:
				_begin_rebind(action_name)
		)
		_refresh_keybind_button(action_name)


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

	if _player.has_method("refresh_mental_fatigue"):
		_player.call("refresh_mental_fatigue")

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


func _add_settings_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(460, 28)
	settings_list.add_child(label)


func _begin_rebind(action_name: String) -> void:
	if not InputMap.has_action(action_name):
		return

	if not _rebinding_action.is_empty():
		_refresh_keybind_button(_rebinding_action)

	_rebinding_action = action_name
	var button: Button = _keybind_buttons[action_name]
	button.text = "Press a key or mouse button"
	button.grab_focus()


func _refresh_keybind_button(action_name: String) -> void:
	if not _keybind_buttons.has(action_name):
		return

	var button: Button = _keybind_buttons[action_name]
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		button.text = "Unbound"
	else:
		button.text = events[0].as_text()


func _get_rebind_event(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return null

		var captured_key := InputEventKey.new()
		captured_key.keycode = key_event.keycode
		captured_key.physical_keycode = key_event.physical_keycode
		captured_key.key_label = key_event.key_label
		captured_key.location = key_event.location
		return captured_key

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return null
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP or mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return null

		var captured_mouse := InputEventMouseButton.new()
		captured_mouse.button_index = mouse_event.button_index
		return captured_mouse

	return null


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
