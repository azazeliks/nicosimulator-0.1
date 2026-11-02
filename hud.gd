# HUD.gd
extends CanvasLayer

signal start_game

# These are built in code (see _ready), so hud.tscn doesn't need any changes.
var _health_bar: ProgressBar
var _health_label: Label
var _coins_label: Label
var _result_label: Label
var _shop_button: Button
var _shop_root: Control
var _shop_coins_label: Label
var _shop_rows: VBoxContainer


func _ready() -> void:
	_build_health_bar()
	_build_coins_label()
	_build_result_label()
	_build_shop_button()
	_build_shop()  # Built last so it draws on top of everything else
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


func update_score(score):
	$ScoreLabel.text = str(score)


func _on_start_button_pressed():
	$StartButton.hide()
	_shop_button.hide()
	_result_label.hide()
	start_game.emit()


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
	_health_bar.size = Vector2(220, 26)
	_health_bar.custom_minimum_size = Vector2(220, 26)
	_health_bar.show_percentage = false
	_health_bar.visible = false  # Appears once a run starts
	add_child(_health_bar)

	_health_label = Label.new()
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

	var title := Label.new()
	title.text = "Upgrade Shop"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)

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
	_refresh_shop()
	$StartButton.disabled = true
	_shop_root.show()


func _close_shop() -> void:
	_shop_root.hide()
	$StartButton.disabled = false


# Rebuilds the list of upgrades from SaveData (called on open and after each purchase)
func _refresh_shop() -> void:
	_shop_coins_label.text = "Coins: %d" % SaveData.get_coins()
	update_coins(SaveData.get_coins())

	for child in _shop_rows.get_children():
		_shop_rows.remove_child(child)
		child.queue_free()

	for id in SaveData.UPGRADES:
		var info: Dictionary = SaveData.UPGRADES[id]

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


func _on_buy_pressed(id: String) -> void:
	SaveData.try_buy(id)
	_refresh_shop()
