-- provides an interface for managing the sources that logs arrive from.
-- sources are associated with numbers.

const vm_id = require("./vm_id")

export type Source =
	{
		read origin: "self",
		read vm: number,

		read source_id: number,
		read map_id_to_templatestring: { [number]: string },
		read map_templatestring_to_id: { [string]: number },
	}
	| {
		read origin: "other_player",
		read player: Player,

		read source_id: number,
		read map_id_to_templatestring: { [number]: string },
		read map_templatestring_to_id: { [string]: number },
		timestamp: number,
	}
	| {
		read origin: "server",

		read source_id: number,
		read map_id_to_templatestring: { [number]: string },
		read map_templatestring_to_id: { [string]: number },
		timestamp: number,
	}

-- keeps track of the next source id, as well as allowing us to count the amount of sources that have been made.
local SOURCE_ID_COUNTER = 0

const function get_new_source_id()
	const source_id = SOURCE_ID_COUNTER
	SOURCE_ID_COUNTER += 1
	return source_id
end

const function create_self_source(vm_id: number): Source
	const source_id = get_new_source_id()

	return {
		origin = "self",
		vm = vm_id,
		source_id = source_id,
		map_id_to_templatestring = {},
		map_templatestring_to_id = {},
	}
end

const SELF_SOURCES: { [number]: Source } = {}

const function get_self_source(vm_id: number): Source
	const source = SELF_SOURCES[vm_id] or create_self_source(vm_id)
	SELF_SOURCES[vm_id] = source

	return source
end

-- do not call this on the server Pls ty
const function create_server_source(): Source
	const source_id = get_new_source_id()

	return {
		origin = "server",
		source_id = source_id,
		map_id_to_templatestring = {},
		map_templatestring_to_id = {},
	}
end

const function create_other_player_source(player: Player): Source
	const source_id = get_new_source_id()

	return {
		origin = "other_player",
		player = player,

		source_id = source_id,
		map_id_to_templatestring = {},
		map_templatestring_to_id = {},
	}
end

const OTHER_PLAYER_SOURCES: { [Player]: Source } = {}

const function get_other_source(player: Player): Source
	const source = OTHER_PLAYER_SOURCES[player]
		or create_other_player_source(player)
	OTHER_PLAYER_SOURCES[player] = source

	return source
end

return {
	self_source = get_self_source(vm_id),
	get_self_source = get_self_source,

	server_source = create_server_source(),
	get_other_player_source = get_other_source,
}
