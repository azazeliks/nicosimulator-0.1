# Groups.gd
# The names of the node groups the game uses, in one place. Write Groups.MOBS instead of the
# text "mobs": a typo in the text fails silently (the group is just empty), while a typo in
# Groups.MOBS is an error the moment the game starts.
# mob.tscn has "mobs" saved inside it (Node tab > Groups), so that one must stay spelled "mobs".
class_name Groups
extends RefCounted

const MOBS := "mobs"                # Every living mob (all attacks' hit tests look here)
const PLAYER := "player"            # The player (mobs chase whoever is in here)
const PROJECTILES := "projectiles"  # Dragon fireballs in flight
const KNIVES := "knives"            # Nico's thrown knives in flight
