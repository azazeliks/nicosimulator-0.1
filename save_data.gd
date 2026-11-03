# SaveData.gd
# Permanent progress (coins + upgrade levels), saved to user://save.cfg.
# Needs no autoload or scene: call it anywhere, e.g. SaveData.get_coins().
# Uses static variables, which require Godot 4.1+.
class_name SaveData
extends RefCounted

const SAVE_PATH := "user://save.cfg"

# Every upgrade the shop sells. To add a new one, add an entry here, then
# apply its bonus in Player.apply_upgrades() using SaveData.bonus("your_id").
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
		"name": "Sweep Range",
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
}

static var _coins: int = 0
static var _levels: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # No save yet: start fresh
	_coins = maxi(int(cfg.get_value("progress", "coins", 0)), 0)
	for id in UPGRADES:
		var saved_level := int(cfg.get_value("upgrades", id, 0))
		_levels[id] = clampi(saved_level, 0, int(UPGRADES[id]["max_level"]))


static func save_data() -> void:
	_ensure_loaded()
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "coins", _coins)
	for id in UPGRADES:
		cfg.set_value("upgrades", id, get_level(id))
	cfg.save(SAVE_PATH)


static func get_coins() -> int:
	_ensure_loaded()
	return _coins


static func add_coins(amount: int) -> void:
	_ensure_loaded()
	_coins = maxi(_coins + amount, 0)
	save_data()


static func get_level(id: String) -> int:
	_ensure_loaded()
	return int(_levels.get(id, 0))


static func is_maxed(id: String) -> bool:
	return get_level(id) >= int(UPGRADES[id]["max_level"])


static func get_cost(id: String) -> int:
	var info: Dictionary = UPGRADES[id]
	return ceili(float(info["base_cost"]) * pow(float(info["growth"]), get_level(id)))


# Total bonus from an upgrade at its current level (level * per_level).
static func bonus(id: String) -> float:
	return get_level(id) * float(UPGRADES[id]["per_level"])


# Spends coins and raises the level. Returns true if the purchase went through.
static func try_buy(id: String) -> bool:
	_ensure_loaded()
	if not UPGRADES.has(id) or is_maxed(id):
		return false
	var cost := get_cost(id)
	if _coins < cost:
		return false
	_coins -= cost
	_levels[id] = get_level(id) + 1
	save_data()
	return true


# Wipes all coins and upgrade levels, and overwrites the save file.
static func reset() -> void:
	_loaded = true  # Don't let a later _ensure_loaded() reload the old file
	_coins = 0
	_levels.clear()
	save_data()
