# SaveData.gd
# Permanent progress (coins + upgrade levels per character), saved to user://save.cfg.
# Needs no autoload or scene: call it anywhere, e.g. SaveData.get_coins().
# Uses static variables, which require Godot 4.1+.
#
# Coins are shared by all characters. Upgrade LEVELS are tracked per character, and every
# function that deals with levels takes the CharacterData it is about as its first argument:
# SaveData.get_level(character, SaveData.MAX_HEALTH). Nothing here remembers "the current
# character", so there is no state to forget to reset.
class_name SaveData
extends RefCounted

const SAVE_PATH := "user://save.cfg"
const LEGACY_CHARACTER := "cat"  # Saves from before characters existed belong to the cat

# Upgrade ids. Use these names instead of typing the text: a typo in SaveData.MAX_HELATH is an
# error as soon as the game starts, while a typo in "max_helath" silently does nothing.
# The TEXT of each id is saved in save.cfg and in the character .tres files, so never change it.
const MAX_HEALTH := "max_health"
const DAMAGE := "damage"
const ATTACK_RANGE := "attack_range"
const ATTACK_SPEED := "attack_speed"
const SPEED := "speed"
const REGEN := "regen"
const PROJECTILE_COUNT := "projectile_count"
const KNOCKBACK := "knockback"
const DASH_DISTANCE := "dash_distance"

# Every upgrade the shop can sell. Each character lists which of these it can buy
# (CharacterData.upgrade_ids). To add a new one, add a constant above and an entry here, apply
# its bonus in Player.apply_upgrades() (or in the attack that uses it, with bonus(SaveData.YOUR_ID)),
# then add the id to the characters that should offer it.
#   base_cost / growth : cost of level N is ceil(base_cost * growth^N)
#   per_level          : bonus gained per level (meaning depends on the upgrade)
const UPGRADES := {
	MAX_HEALTH: {
		"name": "Max Health",
		"desc": "+1 max HP per level",
		"base_cost": 15, "growth": 1.6, "max_level": 5, "per_level": 1.0,
	},
	DAMAGE: {
		"name": "Slash Damage",
		"desc": "+1 attack damage per level",
		"base_cost": 20, "growth": 1.6, "max_level": 5, "per_level": 1.0,
	},
	ATTACK_RANGE: {
		"name": "Slash Range",
		"desc": "+15% attack range per level",
		"base_cost": 12, "growth": 1.6, "max_level": 5, "per_level": 0.15,
	},
	ATTACK_SPEED: {
		"name": "Attack Speed",
		"desc": "+15% attack speed per level",
		"base_cost": 18, "growth": 1.6, "max_level": 5, "per_level": 0.15,
	},
	SPEED: {
		"name": "Move Speed",
		"desc": "+25 move speed per level",
		"base_cost": 10, "growth": 1.6, "max_level": 5, "per_level": 25.0,
	},
	REGEN: {
		"name": "Regeneration",
		"desc": "+20% HP regeneration speed per level",
		"base_cost": 25, "growth": 1.6, "max_level": 5, "per_level": 0.2,
	},
	PROJECTILE_COUNT: {
		"name": "Extra Projectiles",
		"desc": "+1 projectile per shot per level",
		"base_cost": 60, "growth": 2.0, "max_level": 3, "per_level": 1.0,
	},
	KNOCKBACK: {
		"name": "Knockback",
		"desc": "+25% knockback power per level",
		"base_cost": 14, "growth": 1.6, "max_level": 5, "per_level": 0.25,
	},
	DASH_DISTANCE: {
		"name": "Dash Distance",
		"desc": "+20% dash distance per level",
		"base_cost": 12, "growth": 1.6, "max_level": 5, "per_level": 0.2,
	},
}

static var _coins: int = 0
static var _levels: Dictionary = {}  # character id -> { upgrade id -> level }
static var _last_character: String = ""  # Character picked on the selection screen last time
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # No save yet: start fresh
	_coins = maxi(int(cfg.get_value("progress", "coins", 0)), 0)
	_last_character = str(cfg.get_value("progress", "last_character", ""))
	# One "upgrades_<character id>" section per character
	for section in cfg.get_sections():
		if section.begins_with("upgrades_"):
			_read_levels(cfg, section, section.trim_prefix("upgrades_"))
	# Old saves had a single shared "upgrades" section. Give those levels to the cat
	# so nothing is lost. (The next save writes the new layout.)
	if cfg.has_section("upgrades") and not cfg.has_section("upgrades_" + LEGACY_CHARACTER):
		_read_levels(cfg, "upgrades", LEGACY_CHARACTER)


static func _read_levels(cfg: ConfigFile, section: String, character_id: String) -> void:
	var levels := _levels_for(character_id)
	for id in UPGRADES:
		var saved_level := int(cfg.get_value(section, id, 0))
		levels[id] = clampi(saved_level, 0, int(UPGRADES[id]["max_level"]))


# The level table of one character (created empty if it doesn't exist yet)
static func _levels_for(character_id: String) -> Dictionary:
	if not _levels.has(character_id):
		_levels[character_id] = {}
	return _levels[character_id]


static func save_data() -> void:
	_ensure_loaded()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "coins", _coins)
	cfg.set_value("progress", "last_character", _last_character)
	for character_id in _levels:
		var levels: Dictionary = _levels[character_id]
		for id in UPGRADES:
			cfg.set_value("upgrades_" + str(character_id), id, int(levels.get(id, 0)))
	var error := cfg.save(SAVE_PATH)
	if error != OK:
		# Without this message a failed save would be invisible: the game would carry on and
		# the coins and upgrades would be gone next time it is opened.
		push_error("SaveData: could not save progress to %s (error code %d)." % [SAVE_PATH, error])


# The character picked on the selection screen last time ("" if none yet). Saved to disk.
static func get_last_character() -> String:
	_ensure_loaded()
	return _last_character


static func set_last_character(character_id: String) -> void:
	_ensure_loaded()
	_last_character = character_id
	save_data()


# ------------------------------------------------------ what a character can buy

# Upgrade ids the character can buy, in shop order.
static func available_upgrades(character: CharacterData) -> Array:
	var result := []
	for id in UPGRADES:
		if is_available(character, id):
			result.append(id)
	return result


# An empty upgrade_ids list on the character means every upgrade is offered.
static func is_available(character: CharacterData, id: String) -> bool:
	return character.upgrade_ids.is_empty() or character.upgrade_ids.has(id)


# The shop info for an upgrade as this character sees it (name/desc may be overridden).
static func upgrade_info(character: CharacterData, id: String) -> Dictionary:
	var info: Dictionary = UPGRADES[id].duplicate()
	if character.upgrade_overrides.has(id):
		info.merge(character.upgrade_overrides[id], true)
	return info


# ------------------------------------------------------------------- coins

static func get_coins() -> int:
	_ensure_loaded()
	return _coins


static func add_coins(amount: int) -> void:
	_ensure_loaded()
	_coins = maxi(_coins + amount, 0)
	save_data()


# --------------------------------------------------------- levels and buying

static func get_level(character: CharacterData, id: String) -> int:
	_ensure_loaded()
	return int(_levels_for(character.id).get(id, 0))


static func is_maxed(character: CharacterData, id: String) -> bool:
	return get_level(character, id) >= int(UPGRADES[id]["max_level"])


static func get_cost(character: CharacterData, id: String) -> int:
	var info: Dictionary = UPGRADES[id]
	return ceili(float(info["base_cost"]) * pow(float(info["growth"]), get_level(character, id)))


# Total bonus from an upgrade at this character's level (level * per_level).
static func bonus(character: CharacterData, id: String) -> float:
	return get_level(character, id) * float(UPGRADES[id]["per_level"])


# Spends coins and raises the character's level. Returns true if the purchase went through.
static func try_buy(character: CharacterData, id: String) -> bool:
	_ensure_loaded()
	if not UPGRADES.has(id) or not is_available(character, id) or is_maxed(character, id):
		return false
	var cost := get_cost(character, id)
	if _coins < cost:
		return false
	_coins -= cost
	_levels_for(character.id)[id] = get_level(character, id) + 1
	save_data()
	return true


# Wipes all coins and every character's upgrade levels, and overwrites the save file.
static func reset() -> void:
	_loaded = true  # Don't let a later _ensure_loaded() reload the old file
	_coins = 0
	_levels.clear()
	save_data()
