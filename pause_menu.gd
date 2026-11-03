# PauseMenu.gd
# The pause screen: press Escape during a run to freeze the game and show Resume / Exit.
# Exit tells Main (exit_requested) to end the run and go back to the title screen.
# Built in code, so no scene changes are needed: Main creates one in _ready().
# It keeps running while the rest of the game is paused (process_mode ALWAYS), which is
# what lets Escape un-pause again.
class_name PauseMenu
extends CanvasLayer

signal exit_requested  # Exit was pressed. Main ends the run and shows the title screen

# Main sets this: Escape only pauses while a run is going (not on the title, shop or
# character screens). Un-pausing with Escape always works.
var run_active := false

var _root: Control
var _resume_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100  # Draws above the HUD
	_register_input()
	_build()
	_root.hide()


# Creates the "pause" action (Escape) in code, unless one already exists in the Input Map.
func _register_input() -> void:
	if InputMap.has_action("pause"):
		return
	InputMap.add_action("pause")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", ev)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if get_tree().paused:
		if _root.visible:
			_resume()
	elif run_active:
		_pause()
	else:
		return
	get_viewport().set_input_as_handled()


func _pause() -> void:
	get_tree().paused = true
	_root.show()
	_resume_button.grab_focus()


func _resume() -> void:
	_root.hide()
	get_tree().paused = false


func _on_exit_pressed() -> void:
	_root.hide()
	exit_requested.emit()  # Main un-pauses the game as part of leaving the run


func _build() -> void:
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dark overlay; it also soaks up clicks so nothing underneath can be pressed
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	column.add_child(title)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	_resume_button.custom_minimum_size = Vector2(220, 48)
	_resume_button.pressed.connect(_resume)
	column.add_child(_resume_button)

	var exit_button := Button.new()
	exit_button.text = "Exit to main menu"
	exit_button.custom_minimum_size = Vector2(220, 48)
	exit_button.pressed.connect(_on_exit_pressed)
	column.add_child(exit_button)
