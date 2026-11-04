# CharacterData.gd
# One playable character, stored as a small resource file (.tres) you can edit in the
# Inspector. To add a character: right-click in the FileSystem dock > Create New >
# Resource > CharacterData, then fill in the fields.
class_name CharacterData
extends Resource

@export var id: String = ""            # Unique short name used in the save file (e.g. "cat"). Never change it once players have progress
@export var display_name: String = ""  # Shown on the selection screen
@export_multiline var description: String = ""  # A short summary of the character's abilities, shown on the selection screen

# Must contain the animations "walk" and "up", because player.gd plays those.
@export var sprite_frames: SpriteFrames
@export var sprite_tint: Color = Color.WHITE  # Multiplies the sprite's colors. Handy for placeholder art (white = unchanged)

# Starting stats. Shop upgrades are added on top of these at the start of each run.
@export var speed: int = 400
@export var base_max_health: int = 3
@export var base_attack_damage: int = 1
@export var regen_interval: float = 0.0  # Seconds to regenerate 1 HP while hurt. 0 = no regeneration

# A scene whose root node uses a script that extends Attack (for example a SlashAttack).
# Reach, cooldown, swing time and slash art are all set on that scene's root node.
@export var attack_scene: PackedScene

# Optional second attack, fired with the right mouse button. Same rules as attack_scene
# (root script must extend Attack). Leave empty for characters that don't have one yet.
@export var secondary_attack_scene: PackedScene

# Which shop upgrades this character can buy (ids from SaveData.UPGRADES).
# Leave empty to offer every upgrade.
@export var upgrade_ids: PackedStringArray

# Optional per-character wording for the shop, so the dragon can say "Explosion Size"
# instead of "Slash Range". Format: { "upgrade id": { "name": "...", "desc": "..." } }
# Anything you leave out keeps the default text from SaveData.UPGRADES.
@export var upgrade_overrides: Dictionary = {}


# Is `other` the same character as this one? Compares ids, so it stays correct even if Godot
# hands out a second copy of the same .tres. Use this instead of `==` between characters.
func is_same_as(other: CharacterData) -> bool:
	return other != null and other.id == id
