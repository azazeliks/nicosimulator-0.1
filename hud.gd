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
var _shop_root: Control
var _shop_coins_label: Label
var _shop_rows: VBoxContainer
var _shop_title: Label
var _shop_picker: HBoxContainer   # One button per character: whose upgrades the shop is showing
var _shop_character: CharacterData  # The character whose upgrades the shop shows (starts as the selected one)
var _select_root: Control
var _select_cards: HBoxContainer
var _selected: CharacterData  # The character that will be played (and whose upgrades the shop shows)


func _ready() -> void:
	_build_health_bar()
	_build_coins_label()
	_build_result_label()
	_build_shop_button()
	_build_reset_button()
	_pick_initial_character()
	_build_select_screen()
	_build_shop()  # Built last so it draws on top of everything else (including the character screen)
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
	_open_select()


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


# ---------------------------------------------------------------------- shop

func _build_shop() -> void:
	_shop_root = Control.new()
	_shop_root.visible = false
	_shop_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shop_root)
	_shop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_shop_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_shop_title = Label.new()
	_shop_title.text = "Upgrade Shop"
	_shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_shop_title)

	_shop_picker = HBoxContainer.new()
	_shop_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_picker.add_theme_constant_override("separation", 8)
	box.add_child(_shop_picker)

	_shop_coins_label = Label.new()
	_shop_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_shop_coins_label)

	_shop_rows = VBoxContainer.new()
	_shop_rows.add_theme_constant_override("separation", 10)
	box.add_child(_shop_rows)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _open_shop() -> void:
	_shop_character = _selected  # Starts on the selected character; the buttons at the top switch it
	_apply_shop_character_to_save()
	_refresh_shop()
	$StartButton.disabled = true
	_shop_root.show()


func _close_shop() -> void:
	_shop_root.hide()
	$StartButton.disabled = false
	_apply_selected_to_save()  # Back to the character that will be played
	if _select_root.visible:
		_refresh_select()  # Stats on the cards may have changed after buying upgrades


# Rebuilds the list of upgrades from SaveData (called on open and after each purchase)
func _refresh_shop() -> void:
	if _shop_character != null:
		_shop_title.text = "Upgrade Shop - %s" % _shop_character.display_name
	_refresh_shop_picker()
	_shop_coins_label.text = "Coins: %d" % SaveData.get_coins()
	update_coins(SaveData.get_coins())

	for child in _shop_rows.get_children():
		_shop_rows.remove_child(child)
		child.queue_free()

	for id in SaveData.available_upgrades():  # Only what the current character can buy
		var info: Dictionary = SaveData.upgrade_info(id)  # Includes this character's wording changes

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_shop_rows.add_child(row)

		var label := Label.new()
		label.text = "%s   (Lv %d/%d)\n%s" % [
			info["name"], SaveData.get_level(id), info["max_level"], info["desc"]
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var buy := Button.new()
		buy.custom_minimum_size = Vector2(120, 0)
		if SaveData.is_maxed(id):
			buy.text = "MAX"
			buy.disabled = true
		else:
			var cost := SaveData.get_cost(id)
			buy.text = "%d coins" % cost
			buy.disabled = SaveData.get_coins() < cost
			buy.pressed.connect(_on_buy_pressed.bind(id))
		row.add_child(buy)


# Makes SaveData (and so the shop rows, costs and purchases) use the shop's character
func _apply_shop_character_to_save() -> void:
	if _shop_character != null:
		SaveData.set_character(_shop_character.id, _shop_character.upgrade_ids, _shop_character.upgrade_overrides)


# One toggle button per character; the one being viewed is shown pressed
func _refresh_shop_picker() -> void:
	for child in _shop_picker.get_children():
		_shop_picker.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	for data in CharacterRoster.all():
		var button := Button.new()
		button.text = data.display_name
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = data == _shop_character
		button.custom_minimum_size = Vector2(100, 34)
		button.pressed.connect(_on_shop_character_picked.bind(data))
		_shop_picker.add_child(button)


func _on_shop_character_picked(data: CharacterData) -> void:
	if data == _shop_character:
		return
	_shop_character = data
	_apply_shop_character_to_save()
	_refresh_shop.call_deferred()  # Deferred: it rebuilds the button that was just clicked


func _on_buy_pressed(id: String) -> void:
	SaveData.try_buy(id)
	_refresh_shop()


# ------------------------------------------------------------ character select

# Starts on the character used last time, or the first one in the roster
func _pick_initial_character() -> void:
	_selected = CharacterRoster.find_by_id(SaveData.get_last_character())
	if _selected == null:
		var roster := CharacterRoster.all()
		if not roster.is_empty():
			_selected = roster[0]
	_apply_selected_to_save()


# Makes SaveData (and so the shop) use the selected character's upgrades
func _apply_selected_to_save() -> void:
	if _selected != null:
		SaveData.set_character(_selected.id, _selected.upgrade_ids, _selected.upgrade_overrides)


func _build_select_screen() -> void:
	_select_root = Control.new()
	_select_root.visible = false
	_select_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_select_root)
	_select_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_select_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_select_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	_select_cards = HBoxContainer.new()
	_select_cards.add_theme_constant_override("separation", 14)
	box.add_child(_select_cards)

	var note := Label.new()
	note.text = "Stats include the upgrades you have bought for each character."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	var upgrades := Button.new()
	upgrades.text = "Upgrades"
	upgrades.custom_minimum_size = Vector2(140, 36)
	upgrades.pressed.connect(_open_shop)
	buttons.add_child(upgrades)

	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(140, 36)
	play.pressed.connect(_on_play_pressed)
	buttons.add_child(play)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 36)
	back.pressed.connect(_close_select)
	buttons.add_child(back)


func _open_select() -> void:
	_refresh_select()
	_select_root.show()


func _close_select() -> void:
	_select_root.hide()


# Rebuilds one card per character (called on open, after picking, and after the shop closes)
func _refresh_select() -> void:
	for child in _select_cards.get_children():
		_select_cards.remove_child(child)
		child.queue_free()
	for data in CharacterRoster.all():
		_select_cards.add_child(_make_card(data))


func _make_card(data: CharacterData) -> PanelContainer:
	var is_selected := data == _selected

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	style.set_border_width_all(4 if is_selected else 1)
	style.border_color = Color(1.0, 0.85, 0.3) if is_selected else Color(0.4, 0.4, 0.45)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	# Clicking anywhere on the card picks the character. The card catches the click; everything
	# inside it ignores the mouse so the click always reaches the card.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_card_gui_input.bind(data))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	# Sprite preview (the character's first walking frame, with its tint)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(120, 120)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if data.sprite_frames != null and data.sprite_frames.has_animation(&"walk"):
		preview.texture = data.sprite_frames.get_frame_texture(&"walk", 0)
	preview.modulate = data.sprite_tint
	box.add_child(preview)

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 22)
	box.add_child(name_label)

	# Stats, including whatever upgrades have been bought for this character
	var hp := data.base_max_health + int(SaveData.bonus_for(data.id, "max_health"))
	var move := data.speed + int(SaveData.bonus_for(data.id, "speed"))
	var dmg := data.base_attack_damage + int(SaveData.bonus_for(data.id, "damage"))
	var stats_text := "HP: %d\nSpeed: %d\nDamage: %d" % [hp, move, dmg]
	if data.regen_interval > 0.0:
		var interval := data.regen_interval / (1.0 + SaveData.bonus_for(data.id, "regen"))
		stats_text += "\nRegen: 1 HP / %.1f s" % interval
	var stats := Label.new()
	stats.text = stats_text
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)

	var desc := Label.new()
	desc.text = data.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(230, 0)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(desc)
	return card


# A left click anywhere on a card selects that character
func _on_card_gui_input(event: InputEvent, data: CharacterData) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if data != _selected:
			# Deferred, because picking rebuilds the cards (including the one being clicked)
			_on_character_picked.call_deferred(data)


func _on_character_picked(data: CharacterData) -> void:
	_selected = data
	_apply_selected_to_save()
	_refresh_select()


func _on_play_pressed() -> void:
	if _selected == null:
		return
	SaveData.set_last_character(_selected.id)  # Remembered for next time
	_select_root.hide()
	$StartButton.hide()
	_shop_button.hide()
	_reset_button.hide()
	_result_label.hide()
	start_game.emit(_selected)
