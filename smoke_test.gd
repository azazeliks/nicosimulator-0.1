# SmokeTest.gd
# A quick "does everything still hold together?" check. Open smoke_test.tscn and press F6
# (Run Current Scene). It takes about 10 seconds, prints a summary in the Output panel and
# closes itself.
#
# What it does: loads every character in the roster, checks their data, plays each one's
# attacks next to a test mob for about a second, builds the shop, character screen, pause
# menu and HUD, and walks through opening and closing the shop.
#
# It only READS your save file. It never buys, earns or saves anything, so your coins and
# upgrades are safe.
#
# Reading the result:
#   - "ALL ... CHECKS PASSED" at the end and no red text in Output / Debugger > Errors = good.
#   - Anything listed under "PROBLEMS" is a check that failed: copy it to me.
#   - Red errors or yellow warnings that appear while it runs are also problems, even if the
#     summary says PASSED (this script can't see those), so copy those too.
extends Node

var _checks := 0
var _problems: Array[String] = []


func _ready() -> void:
	print("=== SMOKE TEST START ===")
	_test_upgrade_table()
	_test_roster_data()
	_test_save_data_reads()
	_test_screens()
	await _test_characters_in_play()
	await _test_paralysis()
	await _test_hud_flow()
	_report()
	get_tree().quit()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_problems.append(message)


func _report() -> void:
	print("")
	if _problems.is_empty():
		print("ALL %d CHECKS PASSED (now make sure Output / Debugger > Errors has no red or yellow lines)" % _checks)
	else:
		print("%d of %d CHECKS FAILED. PROBLEMS:" % [_problems.size(), _checks])
		for problem in _problems:
			print("  - " + problem)
	print("=== SMOKE TEST END ===")


# ------------------------------------------------------------------ data checks

func _test_upgrade_table() -> void:
	for id in SaveData.UPGRADES:
		var info: Dictionary = SaveData.UPGRADES[id]
		for key in ["name", "desc", "base_cost", "growth", "max_level", "per_level"]:
			_check(info.has(key), "Upgrade '%s' is missing '%s' in SaveData.UPGRADES" % [id, key])


func _test_roster_data() -> void:
	var roster: Array[CharacterData] = CharacterRoster.all()
	_check(roster.size() == CharacterRoster.PATHS.size(), "Roster: only %d of %d characters loaded" % [roster.size(), CharacterRoster.PATHS.size()])
	var seen := {}
	for data in roster:
		var who := "Character '%s'" % data.id
		_check(data.id != "", "A character has an empty id")
		_check(not seen.has(data.id), "%s: id is used twice" % who)
		seen[data.id] = true
		_check(data.display_name != "", "%s: display_name is empty" % who)
		_check(data.is_same_as(data), "%s: is_same_as() fails on itself" % who)
		_check(data.sprite_frames != null and data.sprite_frames.has_animation(&"walk"), "%s: sprite_frames needs a 'walk' animation" % who)
		_check(data.attack_scene != null, "%s: attack_scene is empty" % who)
		for id in data.upgrade_ids:
			_check(SaveData.UPGRADES.has(id), "%s: upgrade_ids has unknown upgrade '%s'" % [who, id])
		for id in data.upgrade_overrides:
			_check(SaveData.UPGRADES.has(id), "%s: upgrade_overrides has unknown upgrade '%s'" % [who, id])
		# The attack scenes must build and extend Attack
		for scene in [data.attack_scene, data.secondary_attack_scene]:
			if scene == null:
				continue
			var node = scene.instantiate()
			_check(node is Attack, "%s: an attack scene's root script does not extend Attack" % who)
			node.free()


func _test_save_data_reads() -> void:
	# Reads only. Nothing here changes or saves anything.
	for data in CharacterRoster.all():
		var who := "Character '%s'" % data.id
		var offered := SaveData.available_upgrades(data)
		_check(not offered.is_empty(), "%s: no upgrades on offer in the shop" % who)
		for id in offered:
			var info := SaveData.upgrade_info(data, id)
			_check(info.has("name") and info.has("desc"), "%s: upgrade '%s' has no name/desc" % [who, id])
			_check(SaveData.get_cost(data, id) > 0, "%s: upgrade '%s' costs 0" % [who, id])
			_check(SaveData.get_level(data, id) >= 0, "%s: upgrade '%s' has a negative level" % [who, id])
			_check(SaveData.bonus(data, id) >= 0.0, "%s: upgrade '%s' has a negative bonus" % [who, id])
		for id in data.upgrade_overrides:
			var shown := SaveData.upgrade_info(data, id)
			var wanted: Dictionary = data.upgrade_overrides[id]
			for key in wanted:
				_check(shown.get(key) == wanted[key], "%s: override '%s' for '%s' is not applied" % [who, key, id])


# ------------------------------------------------------------------ screens

func _test_screens() -> void:
	var roster := CharacterRoster.all()
	if roster.is_empty():
		_check(false, "Roster is empty, so the screens can't be tested")
		return

	var shop := ShopScreen.new()
	add_child(shop)
	for data in roster:
		shop.open(data)
		_check(shop.visible, "Shop didn't show when opened for '%s'" % data.id)
	shop.free()

	var select := CharacterSelectScreen.new()
	add_child(select)
	select.open()
	_check(select.visible, "Character screen didn't show")
	_check(select.selected != null, "Character screen has nobody selected")
	select.free()

	var pause := PauseMenu.new()
	add_child(pause)
	pause.free()


# ------------------------------------------------------------ characters in play

func _test_characters_in_play() -> void:
	var player_scene: PackedScene = load("res://player.tscn")
	var mob_scene: PackedScene = load("res://mob.tscn")
	_check(player_scene != null and mob_scene != null, "player.tscn or mob.tscn didn't load")
	if player_scene == null or mob_scene == null:
		return

	var test_mob = mob_scene.instantiate()
	add_child(test_mob)
	_check(test_mob.is_in_group(Groups.MOBS), "mob.tscn is not in the group Groups.MOBS ('%s'): check its Node > Groups tab" % Groups.MOBS)
	_check(test_mob.has_method("take_damage"), "A mob has no take_damage()")
	test_mob.free()

	var player = player_scene.instantiate()
	add_child(player)
	_check(player.is_in_group(Groups.PLAYER), "Player is not in the group Groups.PLAYER")

	for data in CharacterRoster.all():
		var who := "Character '%s'" % data.id
		player.set_character(data)
		player.start(Vector2(300, 300))
		_check(player.alive, "%s: player didn't start" % who)
		_check(player.attack != null, "%s: player has no attack" % who)
		_check(player.health == player.max_health and player.max_health >= 1, "%s: starting health is wrong" % who)
		if player.attack == null:
			continue

		# A mob to hit, to the right of the player
		var mob = mob_scene.instantiate()
		mob.position = Vector2(430, 300)
		add_child(mob)

		_check(player.attack.try_attack(Vector2(430, 300)), "%s: primary attack refused to start on a fresh run" % who)
		if player.secondary_attack != null:
			_check(player.secondary_attack.try_attack(Vector2(430, 300)), "%s: secondary attack refused to start on a fresh run" % who)
		await get_tree().create_timer(0.7).timeout

		# Again in another direction (the second slash swings the other way, dashes go elsewhere)
		player.attack.try_attack(Vector2(300, 150))
		if player.secondary_attack != null:
			player.secondary_attack.try_attack(Vector2(150, 300))
		await get_tree().create_timer(0.7).timeout

		player.stop_run()
		_check(not player.alive, "%s: stop_run() didn't end the run" % who)
		get_tree().call_group(Groups.MOBS, "queue_free")
		await get_tree().process_frame

	player.free()


# ------------------------------------------------------------ paralysis

func _test_paralysis() -> void:
	var player_scene: PackedScene = load("res://player.tscn")
	var mob_scene: PackedScene = load("res://mob.tscn")
	# A dash can't leave the screen, so the window must be big enough for it (a headless run starts tiny)
	if get_viewport().get_visible_rect().size.x < 1000.0:
		get_window().size = Vector2i(1547, 758)
		await get_tree().process_frame
	var seven := CharacterRoster.find_by_id("android")
	if player_scene == null or mob_scene == null or seven == null or seven.secondary_attack_scene == null:
		_check(false, "Paralysis test: couldn't set up (player.tscn, mob.tscn or Seven's dash is missing)")
		return

	# A mob frozen by hand: it doesn't move, then it carries on at the same velocity
	var lone = mob_scene.instantiate()
	lone.position = Vector2(900, 100)
	add_child(lone)
	lone.linear_velocity = Vector2(0, 100)
	lone.paralyze(0.3)
	_check(lone.is_paralyzed(), "paralyze() didn't freeze the mob")
	lone.knockback(Vector2.RIGHT, 500.0, 0.2)
	await get_tree().create_timer(0.2).timeout
	_check(lone.global_position.distance_to(Vector2(900, 100)) < 3.0, "A paralysed mob moved (or was knocked back)")
	await get_tree().create_timer(0.4).timeout
	_check(not lone.is_paralyzed(), "A mob stayed paralysed too long")
	_check(lone.linear_velocity.length() > 50.0, "A mob didn't carry on moving after the paralysis ended")
	lone.free()

	# A paralysed mob touching the player does no damage; a normal one does
	var victim = player_scene.instantiate()
	add_child(victim)
	victim.set_character(seven)
	victim.start(Vector2(300, 300))
	var toucher = mob_scene.instantiate()
	toucher.position = Vector2(300, 300)
	add_child(toucher)
	toucher.paralyze(5.0)
	await get_tree().create_timer(0.3).timeout
	_check(victim.health == victim.max_health, "A paralysed mob hurt the player")
	toucher.free()
	var live_mob = mob_scene.instantiate()
	live_mob.position = Vector2(300, 300)
	add_child(live_mob)
	await get_tree().create_timer(0.3).timeout
	_check(victim.health < victim.max_health, "A normal mob touching the player did no damage (the paralysis check may be too broad)")
	live_mob.free()
	victim.stop_run()
	victim.free()

	# The blast art spins clockwise from 180 degrees back to facing the dash, then stays put
	var spinner = load("res://android_dash_attack.tscn").instantiate()
	add_child(spinner)
	spinner._blast_rotation = 1.0
	_check(is_equal_approx(spinner._blast_art_angle(0.0), 1.0 - PI), "Blast art spin: wrong starting angle")
	_check(spinner._blast_art_angle(0.25) > spinner._blast_art_angle(0.0), "Blast art spin: not turning clockwise")
	_check(is_equal_approx(spinner._blast_art_angle(spinner.blast_art_spin_time), 1.0), "Blast art spin: doesn't end facing the dash direction")
	_check(is_equal_approx(spinner._blast_art_angle(5.0), 1.0), "Blast art spin: keeps turning after it has finished")
	spinner.free()

	# Seven's dash freezes the mob it hits until the blast has landed, then lets it go
	var player = player_scene.instantiate()
	add_child(player)
	player.set_character(seven)
	player.start(Vector2(300, 300))
	var mob = mob_scene.instantiate()
	mob.position = Vector2(430, 300)
	add_child(mob)
	mob.linear_velocity = Vector2(0, 150)
	_check(player.secondary_attack.try_attack(Vector2(900, 300)), "Paralysis test: Seven's dash refused to start")
	await get_tree().create_timer(0.35).timeout
	_check(mob.is_paralyzed(), "Seven's dash didn't paralyse the mob it hit")
	_check(absf(mob.global_position.y - 300.0) < 5.0, "The mob kept moving while it should be paralysed")
	await get_tree().create_timer(1.1).timeout
	_check(not mob.is_paralyzed(), "The mob was still paralysed long after Seven's blast")
	player.stop_run()
	get_tree().call_group(Groups.MOBS, "queue_free")
	await get_tree().process_frame
	player.free()


# ----------------------------------------------------------------- HUD + shop

func _test_hud_flow() -> void:
	var hud_scene: PackedScene = load("res://hud.tscn")
	_check(hud_scene != null, "hud.tscn didn't load")
	if hud_scene == null:
		return
	var hud = hud_scene.instantiate()
	add_child(hud)
	await get_tree().process_frame

	hud.update_health(3, 3)
	hud.show_title(10, 2, SaveData.get_coins())
	hud._on_start_button_pressed()  # START: opens the character screen
	_check(hud._select_screen.visible, "START didn't open the character screen")
	hud._open_shop()  # Upgrades button
	_check(hud._shop_screen.visible, "The shop didn't open")
	_check(hud.get_node("StartButton").disabled, "START should be disabled while the shop is open")
	hud._shop_screen._on_close_pressed()
	_check(not hud._shop_screen.visible, "The shop didn't close")
	_check(not hud.get_node("StartButton").disabled, "START should be enabled again after the shop closes")
	hud.free()
