# SaveData.gd
# Permanent progress (coins + upgrade levels per character), saved to user://save.cfg.
# Needs no autoload or scene: call it anywhere, e.g. SaveData.get_coins().
# Uses static variables, which require Godot 4.1+.
#
# Coins are shared by all characters. Upgrade LEVELS are tracked per character:
# get_level(), bonus(), get_cost() and try_buy() all use the character picked with
# SaveData.set_character(id, upgrade_ids) (the Player does this when it becomes a character).
class_name SaveData
extends RefCounted

const SAVE_PATH := "user://save.cfg"
const LEGACY_CHARACTER := "cat"  # Saves from before characters existed belong to the cat

# Every upgrade the shop can sell. Each character lists which of these it can buy
# (CharacterData.upgrade_ids). To add a new one, add an entry here, apply its bonus in
# Player.apply_upgrades() using SaveData.bonus("your_id"), then add the id to the
# characters that should offer it.
#   base_cost / growth : cost of level N is ceil(base_cost * growth^N)
#   per_level          : bonus gained per level (meaning depends on the upgrade)
const UPGRADES := {
	"max_health": {
		"name": "Max Health",
		"desc": "+1 max HP per level",
		"base_cost": 15, "growth": 1.6, "max_level": 5, "per_level": 1.0,
	},
	"damage": {
		"name": "Slash Damage",
		"desc": "+1 attack damage per level",
		"base_cost": 20, "growth": 1.6, "max_level": 5, "per_level": 1.0,
	},
	"attack_range": {
		"name": "Slash Range",
		"desc": "+15% attack range per level",
		"base_cost": 12, "growth": 1.6, "max_level": 5, "per_level": 0.15,
	},
	"attack_speed": {
		"name": "Attack Speed",
		"desc": "+15% attack speed per level",
		"base_cost": 18, "growth": 1.6, "max_level": 5, "per_level": 0.15,
	},
	"speed": {
		"name": "Move Speed",
		"desc": "+25 move speed per level",
		"base_cost": 10, "growth": 1.6, "max_level": 5, "per_level": 25.0,
	},
	"regen": {
		"name": "Regeneration",
		"desc": "+20% HP regeneration speed per level",
		"base_cost": 25, "growth": 1.6, "max_level": 5, "per_level": 0.2,
	},
	"projectile_count": {
		"name": "Extra Projectiles",
		"desc": "+1 projectile per shot per level",
		"base_cost": 60, "growth": 2.0, "max_level": 3, "per_level": 1.0,
	},
	"knockback": {
		"name": "Knockback",
		"desc": "+25% knockback power per level",
		"base_cost": 14, "growth": 1.6, "max_level": 5, "per_level": 0.25,
	},
	"dash_distance": {
		"name": "Dash Distance",
		"desc": "+20% dash distance per level",
		"base_cost": 12, "growth": 1.6, "max_level": 5, "per_level": 0.2,
	},
}

static var _coins: int = 0
static var _levels: Dictionary = {}  # character id -> { upgrade id -> level }
static var _current: String = "cat"  # Whose upgrades the functions below use
static var _available: PackedStringArray = PackedStringArray()  # Upgrades the current character can buy (empty = all)
static var _overrides: Dictionary = {}  # Current character's shop wording changes (see CharacterData.upgrade_overrides)
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
	_levels_for(_current)  # Make sure the current character gets a section
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "coins", _coins)
	cfg.set_value("progress", "last_character", _last_character)
	for character_id in _levels:
		var levels: Dictionary = _levels[character_id]
		for id in UPGRADES:
			cfg.set_value("upgrades_" + str(character_id), id, int(levels.get(id, 0)))
	cfg.save(SAVE_PATH)


# Picks whose upgrade levels get_level / bonus / get_cost / try_buy use, and which
# upgrades the shop offers. An empty list means every upgrade is offered.
static func set_character(character_id: String, upgrade_ids: PackedStringArray = PackedStringArray(), upgrade_overrides: Dictionary = {}) -> void:
	_current = character_id
	_available = upgrade_ids
	_overrides = upgrade_overrides


static func get_character() -> String:
	return _current


# The character picked on the selection screen last time ("" if none yet). Saved to disk.
static func get_last_character() -> String:
	_ensure_loaded()
	return _last_character


static func set_last_character(character_id: String) -> void:
	_ensure_loaded()
	_last_character = character_id
	save_data()


# Upgrade ids the current character can buy, in shop order.
static func available_upgrades() -> Array:
	var result := []
	for id in UPGRADES:
		if is_available(id):
			result.append(id)
	return result


static func is_available(id: String) -> bool:
	return _available.is_empty() or _available.has(id)


# The shop info for an upgrade as the current character sees it (name/desc may be overridden).
static func upgrade_info(id: String) -> Dictionary:
	var info: Dictionary = UPGRADES[id].duplicate()
	if _overrides.has(id):
		info.merge(_overrides[id], true)
	return info


static func get_coins() -> int:
	_ensure_loaded()
	return _coins


static func add_coins(amount: int) -> void:
	_ensure_loaded()
	_coins = maxi(_coins + amount, 0)
	save_data()


static func get_level(id: String) -> int:
	return get_level_for(_current, id)


# The level of an upgrade for any character (the selection screen uses this to show stats)
static func get_level_for(character_id: String, id: String) -> int:
	_ensure_loaded()
	return int(_levels_for(character_id).get(id, 0))


static func is_maxed(id: String) -> bool:
	return get_level(id) >= int(UPGRADES[id]["max_level"])


static func get_cost(id: String) -> int:
	var info: Dictionary = UPGRADES[id]
	return ceili(float(info["base_cost"]) * pow(float(info["growth"]), get_level(id)))


# Total bonus from an upgrade at its current level (level * per_level).
static func bonus(id: String) -> float:
	return bonus_for(_current, id)


# Same, for any character
static func bonus_for(character_id: String, id: String) -> float:
	return get_level_for(character_id, id) * float(UPGRADES[id]["per_level"])


# Spends coins and raises the current character's level. Returns true if the purchase went through.
static func try_buy(id: String) -> bool:
	_ensure_loaded()
	if not UPGRADES.has(id) or not is_available(id) or is_maxed(id):
		return false
	var cost := get_cost(id)
	if _coins < cost:
		return false
	_coins -= cost
	_levels_for(_current)[id] = get_level(id) + 1
	save_data()
	return true


# Wipes all coins and every character's upgrade levels, and overwrites the save file.
static func reset() -> void:
	_loaded = true  # Don't let a later _ensure_loaded() reload the old file
	_coins = 0
	_levels.clear()
	save_data()
