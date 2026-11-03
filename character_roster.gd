# CharacterRoster.gd
# The list of playable characters, in the order the selection screen shows them.
# To add a character: make its .tres (see CharacterData) and add its path below.
class_name CharacterRoster
extends RefCounted

const PATHS := [
	"res://cat.tres",
	"res://android.tres",
	"res://bruiser.tres",
	"res://dragon.tres",
]


static func all() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for path in PATHS:
		var data := load(path) as CharacterData
		if data != null:
			result.append(data)
		else:
			push_error("CharacterRoster: could not load %s" % path)
	return result


# Returns null if no character has that id.
static func find_by_id(character_id: String) -> CharacterData:
	for data in all():
		if data.id == character_id:
			return data
	return null
