# HUD.gd
extends CanvasLayer

signal start_game(character: CharacterData)  # Sent when PLAY is pressed on the character screen

const HEALTH_BAR_SIZE := Vector2(400, 44)  # Size of the in-game health bar (top left)

# These are built in code (see _ready), so hud.tscn doesn't need any changes.
var _health_bar: ProgressBar
var _health_label: Label
var _coins_label: Label
var _result_label: Label
var _shop_button: Button
var _reset_button: Button
var _reset_dialog: ConfirmationDialog
var _select_screen: CharacterSelectScreen  # See character_select_screen.gd
var _shop_screen: ShopScreen               # See shop_screen.gd


func _ready() -> void:
	_build_health_bar()
	_build_coins_label()
	_build_result_label()
	_build_shop_button()
	_build_reset_button()
	_build_select_screen()
	_build_shop_screen()  # Built last so it draws on top of everything else (including the character screen)
	update_coins(SaveData.get_coins())


# ---------------------------------------------------------------- existing API

func show_message(text):
	$MessageLabel.text = text
	$MessageLabel.show()
	$MessageTimer.start()


func show_game_over(final_score: int = 0, earned: int = 0, total_coins: int = 0):
	update_coins(total_coins)
	_result_label.text = "Score: %d    |    Coins earned: %d" % [final_score, earned]
	_result_label.show()
	show_message("Ow")
	await $MessageTimer.timeout
	$MessageLabel.text = "Real Nico Simulator 2026"
	$MessageLabel.show()
	await get_tree().create_timer(1.0).timeout
	$StartButton.show()
	_shop_button.show()
	_reset_button.show()


# Back to the title screen right away (used when a run is abandoned from the pause menu).
# Unlike show_game_over() there is no "Ow" message and no waiting.
func show_title(final_score: int = 0, earned: int = 0, total_coins: int = 0) -> void:
	update_coins(total_coins)
	_result_label.text = "Score: %d    |    Coins earned: %d" % [final_score, earned]
	_result_label.show()
	_health_bar.hide()
	$MessageTimer.stop()  # A pending timer would hide the title text again (e.g. after "Get Ready!")
	$MessageLabel.text = "Real Nico Simulator 2026"
	$MessageLabel.show()
	$StartButton.show()
	_shop_button.show()
	_reset_button.show()


func update_score(score):
	$ScoreLabel.text = str(score)


# START now opens the character screen. The run begins when PLAY is pressed there.
func _on_start_button_pressed():
	_select_screen.open()


func _on_message_timer_timeout():
	$MessageLabel.hide()


# ------------------------------------------------------------------ new in-game UI

func update_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HP %d / %d" % [current, maximum]
	_health_bar.show()


func update_coins(total: int) -> void:
	_coins_label.text = "Coins: %d" % total


func _build_health_bar() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(16, 12)
	_health_bar.size = HEALTH_BAR_SIZE
	_health_bar.custom_minimum_size = HEALTH_BAR_SIZE
	_health_bar.show_percentage = false
	_health_bar.visible = false  # Appears once a run starts

	# Red fill on a dark background, with rounded corners and a thin border
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.12, 0.12)
	fill.set_corner_radius_all(6)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.15, 0.04, 0.04, 0.85)
	back.border_color = Color(0, 0, 0, 0.9)
	back.set_border_width_all(2)
	back.set_corner_radius_all(6)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_stylebox_override("background", back)
	add_child(_health_bar)

	_health_label = Label.new()
	_health_label.add_theme_font_size_override("font_size", 24)
	_health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_health_label.add_theme_constant_override("outline_size", 6)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_bar.add_child(_health_label)
	_health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_coins_label() -> void:
	_coins_label = Label.new()
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_coins_label)
	# Pin to the top-right corner
	_coins_label.anchor_left = 1.0
	_coins_label.anchor_right = 1.0
	_coins_label.offset_left = -216.0
	_coins_label.offset_right = -16.0
	_coins_label.offset_top = 8.0
	_coins_label.offset_bottom = 32.0


func _build_result_label() -> void:
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 22)
	_result_label.visible = false
	add_child(_result_label)
	# Full-width strip just under the score
	_result_label.anchor_right = 1.0
	_result_label.offset_top = 56.0
	_result_label.offset_bottom = 90.0


func _build_shop_button() -> void:
	_shop_button = Button.new()
	_shop_button.text = "SHOP"
	_shop_button.custom_minimum_size = Vector2(56, 31)
	add_child(_shop_button)
	_shop_button.position = $StartButton.position + Vector2(0, 45)
	_shop_button.pressed.connect(_open_shop)


func _build_reset_button() -> void:
	_reset_button = Button.new()
	_reset_button.text = "RESET"
	_reset_button.custom_minimum_size = Vector2(56, 31)
	add_child(_reset_button)
	_reset_button.position = $StartButton.position + Vector2(0, 90)
	_reset_button.pressed.connect(_on_reset_pressed)

	# Asks before deleting anything, since this can't be undone
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset progress"
	_reset_dialog.dialog_text = "Erase all coins and upgrades?\nThis cannot be undone."
	_reset_dialog.ok_button_text = "Erase"
	_reset_dialog.cancel_button_text = "Cancel"
	_reset_dialog.confirmed.connect(_on_reset_confirmed)
	add_child(_reset_dialog)


func _on_reset_pressed() -> void:
	_reset_dialog.popup_centered()


func _on_reset_confirmed() -> void:
	SaveData.reset()
	update_coins(SaveData.get_coins())


# ------------------------------------------------- shop and character screens
# Each screen builds and runs its own UI (shop_screen.gd, character_select_screen.gd).
# The HUD only creates them and connects their signals.

func _build_select_screen() -> void:
	_select_screen = CharacterSelectScreen.new()
	add_child(_select_screen)
	_select_screen.upgrades_requested.connect(_open_shop)
	_select_screen.play_requested.connect(_on_play_requested)


func _build_shop_screen() -> void:
	_shop_screen = ShopScreen.new()
	add_child(_shop_screen)
	_shop_screen.coins_changed.connect(update_coins)
	_shop_screen.closed.connect(_on_shop_closed)


# From the SHOP button or the character screen's Upgrades button. The shop opens on the
# selected character.
func _open_shop() -> void:
	$StartButton.disabled = true
	_shop_screen.open(_select_screen.selected)


func _on_shop_closed() -> void:
	$StartButton.disabled = false
	_select_screen.apply_selected_to_save()  # Back to the character that will be played
	if _select_screen.visible:
		_select_screen.refresh()  # Stats on the cards may have changed after buying upgrades


# PLAY was pressed on the character screen (it has already hidden itself)
func _on_play_requested(character: CharacterData) -> void:
	$StartButton.hide()
	_shop_button.hide()
	_reset_button.hide()
	_result_label.hide()
	start_game.emit(character)
