# ShopScreen.gd
# The upgrade shop: a full-screen overlay built in code. It shows one character's upgrades at
# a time (the buttons at the top switch whose) and sells them for coins through SaveData.
# Open it with open(character): it starts on that character. Looking at another character in
# the shop does NOT change who is played, it only changes whose upgrades are shown.
# While the shop is open, SaveData's current character follows the one the shop is showing (so
# the rows, costs and purchases use that character). Whoever opens the shop must put SaveData
# back on the character being played when it closes: listen to the `closed` signal.
class_name ShopScreen
extends Control

signal coins_changed(total: int)  # After opening and after every purchase, so the HUD's coin counter can follow
signal closed                     # The Close button was pressed (the shop has already hidden itself)

var _title: Label
var _coins_label: Label
var _rows: VBoxContainer
var _picker: HBoxContainer       # One button per character: whose upgrades the shop is showing
var _character: CharacterData    # The character whose upgrades the shop shows


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


# Shows the shop, starting on the given character (normally the one that is selected to play)
func open(start_character: CharacterData) -> void:
	_character = start_character
	_apply_character_to_save()
	_refresh()
	show()


func _on_close_pressed() -> void:
	hide()
	closed.emit()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
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
	box.custom_minimum_size = Vector2(500, 0)
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	_title = Label.new()
	_title.text = "Upgrade Shop"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)

	_picker = HBoxContainer.new()
	_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	_picker.add_theme_constant_override("separation", 8)
	box.add_child(_picker)

	_coins_label = Label.new()
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_coins_label)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	box.add_child(_rows)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(_on_close_pressed)
	box.add_child(close)


# Rebuilds the list of upgrades from SaveData (called on open and after each purchase)
func _refresh() -> void:
	if _character != null:
		_title.text = "Upgrade Shop - %s" % _character.display_name
	_refresh_picker()
	_coins_label.text = "Coins: %d" % SaveData.get_coins()
	coins_changed.emit(SaveData.get_coins())

	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	for id in SaveData.available_upgrades():  # Only what the current character can buy
		var info: Dictionary = SaveData.upgrade_info(id)  # Includes this character's wording changes

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_rows.add_child(row)

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
func _apply_character_to_save() -> void:
	if _character != null:
		SaveData.set_character(_character.id, _character.upgrade_ids, _character.upgrade_overrides)


# One toggle button per character; the one being viewed is shown pressed
func _refresh_picker() -> void:
	for child in _picker.get_children():
		_picker.remove_child(child)
		child.queue_free()
	var group := ButtonGroup.new()
	for data in CharacterRoster.all():
		var button := Button.new()
		button.text = data.display_name
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = data == _character
		button.custom_minimum_size = Vector2(100, 34)
		button.pressed.connect(_on_character_picked.bind(data))
		_picker.add_child(button)


func _on_character_picked(data: CharacterData) -> void:
	if data == _character:
		return
	_character = data
	_apply_character_to_save()
	_refresh.call_deferred()  # Deferred: it rebuilds the button that was just clicked


func _on_buy_pressed(id: String) -> void:
	SaveData.try_buy(id)
	_refresh()
