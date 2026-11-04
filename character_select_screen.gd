# CharacterSelectScreen.gd
# The character selection screen: a full-screen overlay built in code, with one card per
# character (sprite, stats including bought upgrades, description). Click a card to pick it.
# Buttons: Upgrades (asks the HUD to open the shop), Play (starts a run) and Back (hides it).
# `selected` is the character that will be played; it starts as the one played last time.
# The HUD listens to the signals below.
class_name CharacterSelectScreen
extends Control

signal upgrades_requested                       # Upgrades pressed: the HUD opens the shop
signal play_requested(character: CharacterData)  # Play pressed: the HUD starts a run with this character

var selected: CharacterData  # The character that will be played (and whose upgrades the shop opens on)

var _cards: HBoxContainer


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pick_initial_character()
	_build()


# Shows the screen with up-to-date cards
func open() -> void:
	refresh()
	show()


# Rebuilds one card per character (called on open, after picking, and after the shop closes)
func refresh() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	for data in CharacterRoster.all():
		_cards.add_child(_make_card(data))


# Makes SaveData (and so the shop) use the selected character's upgrades
func apply_selected_to_save() -> void:
	if selected != null:
		SaveData.set_character(selected.id, selected.upgrade_ids, selected.upgrade_overrides)


# Starts on the character used last time, or the first one in the roster
func _pick_initial_character() -> void:
	selected = CharacterRoster.find_by_id(SaveData.get_last_character())
	if selected == null:
		var roster := CharacterRoster.all()
		if not roster.is_empty():
			selected = roster[0]
	apply_selected_to_save()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
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

	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	box.add_child(_cards)

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
	upgrades.pressed.connect(_on_upgrades_pressed)
	buttons.add_child(upgrades)

	var play := Button.new()
	play.text = "Play"
	play.custom_minimum_size = Vector2(140, 36)
	play.pressed.connect(_on_play_pressed)
	buttons.add_child(play)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 36)
	back.pressed.connect(hide)
	buttons.add_child(back)


func _make_card(data: CharacterData) -> PanelContainer:
	var is_selected := data == selected

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
		if data != selected:
			# Deferred, because picking rebuilds the cards (including the one being clicked)
			_on_character_picked.call_deferred(data)


func _on_character_picked(data: CharacterData) -> void:
	selected = data
	apply_selected_to_save()
	refresh()


func _on_upgrades_pressed() -> void:
	upgrades_requested.emit()


func _on_play_pressed() -> void:
	if selected == null:
		return
	SaveData.set_last_character(selected.id)  # Remembered for next time
	hide()
	play_requested.emit(selected)
