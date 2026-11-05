export type Table = { [any]: any }
export type RegistryValue = string | Table

export type Packet = {
	input: buffer,

	read registry_jump_table: { [number]: number },
}

const INTERIM_BUFFER_SIZE = 2 ^ 18
const MAX_STRING_SIZE = 2 ^ 15
const MAX_SHORT_STRING_SIZE = 50
const MAX_FUNCTION_NAME = 50
const MAX_TOSTRING = 100
const MAX_REGISTRY_VALUES = 2 ^ 12

const I8_UPPER_BOUNDS = 2 ^ 8 - 1
const I8_LOWER_BOUNDS = -2 ^ 8

const I16_UPPER_BOUNDS = 2 ^ 16 - 1
const I16_LOWER_BOUNDS = -2 ^ 16

const I32_UPPER_BOUNDS = 2 ^ 31 - 1
const I32_LOWER_BOUNDS = -2 ^ 31

const REG_TYPE_TABLE = 0
const REG_TYPE_LONGSTRING = 1

const TYPE_NIL = 0
const TYPE_NUMBER = 1
const TYPE_STRING = 2
const TYPE_TRUE = 3
const TYPE_FALSE = 4
const TYPE_TABLE = 5
const TYPE_LONGSTRING = 6
const TYPE_FUNCTION = 7
const TYPE_CFUNCTION = 8
const TYPE_VECTOR = 9

const TYPE_INT8 = 10
const TYPE_INT16 = 11
const TYPE_INT32 = 12

const TYPE_MISC = 16

const TYPE_STOP = 255

const SYMBOL_DOES_NOT_EXIST = table.freeze({ err = "doesnotexist" })

const MAP_REGISTRY_VALUE_TO_IDX: { [RegistryValue]: number } = {}
const PROCESSING_REGISTRY_VALUES_CACHE: { RegistryValue } = {} -- an array
const INTERIM_BUFFER = buffer.create(INTERIM_BUFFER_SIZE)

const function tostring_keys(props: Table): { [string]: any }
	const copy = {}

	for key, value in props do
		copy[tostring(key)] = value
	end

	return copy
end

const function serialize(logproperties: Table)
	const properties = tostring_keys(logproperties)

	local registry_value_counter = 0 -- this counter is responsible for generating ids for the defer queue
	local processed_registry_value_counter = 0 -- this counter is responsible for getting the id of values as they exit the queue (is fine!)
	local pos = 0

	const registry_value_queue = PROCESSING_REGISTRY_VALUES_CACHE
	const b = INTERIM_BUFFER

	const map_registry_value_to_id = MAP_REGISTRY_VALUE_TO_IDX

	const function defer_registry_value_to_queue(value: RegistryValue)
		const registry_id = map_registry_value_to_id[value]

		if registry_id then
			return registry_id
		end

		const new_registry_id = registry_value_counter
		table.insert(registry_value_queue, value)
		map_registry_value_to_id[value] = new_registry_id

		-- increment the counter so that ids dont get reused
		registry_value_counter += 1

		return new_registry_id
	end

	const function serialize_key_value(value: unknown)
		const type_value = type(value)
		print(pos, type_value)

		if type_value == "number" then
			const is_integer = value == value // 1
				and value >= I32_LOWER_BOUNDS
				and value <= I32_UPPER_BOUNDS

			if
				is_integer
				and value >= I8_LOWER_BOUNDS
				and value <= I8_UPPER_BOUNDS
			then
				buffer.writeu8(b, pos, TYPE_INT8)
				buffer.writei8(b, pos + 1, value)
				pos += 2
			elseif
				is_integer
				and value >= I16_LOWER_BOUNDS
				and value <= I16_UPPER_BOUNDS
			then
				buffer.writeu8(b, pos, TYPE_INT16)
				buffer.writei16(b, pos + 1, value)
				pos += 3
			elseif is_integer then
				buffer.writeu8(b, pos, TYPE_INT32)
				buffer.writei32(b, pos + 1, value)
				pos += 5
			else
				buffer.writeu8(b, pos, TYPE_NUMBER)
				buffer.writef64(b, pos + 1, value)
				pos += 9
			end

			return
		elseif type_value == "string" and #value < MAX_SHORT_STRING_SIZE then -- intern string if short enough
			buffer.writeu8(b, pos, TYPE_STRING)

			buffer.writeu8(b, pos + 1, math.min(#value, MAX_SHORT_STRING_SIZE))
			buffer.writestring(b, pos + 2, value)
			pos += 2 + #value
			return
		elseif type_value == "string" and #value > MAX_SHORT_STRING_SIZE then -- extern string, defer
			const ptr = defer_registry_value_to_queue(value)

			buffer.writeu8(b, pos, TYPE_LONGSTRING)
			buffer.writeu16(b, pos + 1, ptr)

			pos += 3
			return
		elseif type_value == "boolean" then
			buffer.writeu8(
				b,
				pos,
				if value == true then TYPE_TRUE else TYPE_FALSE
			)
			pos += 1
			return
		elseif type_value == "table" then
			const ptr = defer_registry_value_to_queue(value)

			buffer.writeu8(b, pos, TYPE_TABLE)
			buffer.writeu16(b, pos + 1, ptr)

			pos += 3
			return
		elseif type_value == "vector" then
			buffer.writeu8(b, pos, TYPE_VECTOR)
			buffer.writef32(b, pos + 1, value.x)
			buffer.writef32(b, pos + 5, value.y)
			buffer.writef32(b, pos + 9, value.z)

			pos += 13
			return
		elseif type_value == "function" then
			const source, line, name = debug.info(value, "sln")

			if source == "[C]" then
				const name_length = math.min(#name, MAX_FUNCTION_NAME) -- we need to track length here since we dont strip function name data

				buffer.writeu8(b, pos, TYPE_CFUNCTION)
				buffer.writeu8(b, pos + 1, name_length)
				buffer.writestring(b, pos + 2, name, name_length)
				pos += 2 + name_length
			else
				const source_length = math.min(#name, MAX_FUNCTION_NAME) -- we need to track length here since we dont strip function name data
				const name_length = math.min(#name, MAX_FUNCTION_NAME) -- we need to track length here since we dont strip function name data

				buffer.writeu8(b, pos, TYPE_FUNCTION)
				buffer.writeu32(b, pos + 1, line)
				buffer.writeu8(b, pos + 5, source_length)
				buffer.writeu8(b, pos + 6, name_length)
				buffer.writestring(b, pos + 7, source, source_length)
				buffer.writestring(
					b,
					pos + 7 + source_length,
					name,
					name_length
				)

				pos += 7 + source_length + name_length
			end

			return
		elseif type_value == "nil" then
			buffer.writeu8(b, pos, TYPE_NIL)
			pos += 1
			return
		else
			const typeof_value = typeof(value)
			const tostringed = tostring(value)
			const length = math.min(#tostringed, MAX_TOSTRING)

			buffer.writeu8(b, pos, TYPE_MISC)
			buffer.writeu8(b, pos + 1, length)
			buffer.writeu8(b, pos + 2, #typeof_value)
			buffer.writestring(b, pos + 3, typeof_value)
			buffer.writestring(b, pos + 3 + #typeof_value, tostringed, length)

			pos += 3 + #typeof_value + length
			return
		end

		-- const typeof_value = typeof(value)
	end

	const function serialize_registry_value(value: RegistryValue)
		const registry_id = processed_registry_value_counter

		if typeof(value) == "table" then
			buffer.writeu8(b, pos, REG_TYPE_TABLE)
			const size_pos = pos + 1 -- we store the current offset so we can write the size afterwards.
			-- that allows us to navigate the packet faster if we need to eg find a registry value
			pos += 5

			for key, value in pairs(value) do
				serialize_key_value(key)
				serialize_key_value(value)
			end

			buffer.writeu8(b, pos, TYPE_STOP)
			buffer.writeu32(b, size_pos, pos + 1)
			pos += 1
		elseif typeof(value) == "string" then
			const length = math.min(MAX_STRING_SIZE, #value)
			buffer.writeu8(b, pos, REG_TYPE_LONGSTRING)
			buffer.writeu16(b, pos + 1, length)
			buffer.writestring(b, pos + 3, value, length)

			pos += 3 + #value
		end

		-- we increment the counter to indicate we processed this id.
		processed_registry_value_counter += 1
		return registry_id
	end

	-- serialize registry loop
	defer_registry_value_to_queue(properties)

	while
		registry_value_counter > processed_registry_value_counter
		and processed_registry_value_counter ~= MAX_REGISTRY_VALUES
	do
		const popped = table.remove(registry_value_queue)

		assert(
			popped ~= nil,
			"queue is empty, but counter is still incremented"
		)

		serialize_registry_value(popped)
	end

	const copy = buffer.create(pos + 10)
	buffer.copy(copy, 0, b, 0, pos + 10)

	table.clear(MAP_REGISTRY_VALUE_TO_IDX)
	table.clear(PROCESSING_REGISTRY_VALUES_CACHE)
	buffer.fill(INTERIM_BUFFER, 0, 0)

	return copy
end

const function read_properties(properties: buffer)
	const b = properties

	const function find_registry_offset(idx: number): number?
		local pos = 0

		while idx > 0 or pos > buffer.len(b) do
			const registry_type = buffer.readu8(b, pos)

			if registry_type == REG_TYPE_TABLE then
				const skip_ahead_to = buffer.readu32(b, pos + 1)
				pos = skip_ahead_to
			elseif registry_type == REG_TYPE_LONGSTRING then
				const skip_ahead_bytes = buffer.readu16(b, pos + 1)
				pos += skip_ahead_bytes + 3
			end

			idx -= 1 -- decrement idx, when idx reaches 0 we reached the desired offset
		end

		-- if the idx is not zero, we did not find it.
		return if idx == 0 then pos else nil
	end

	const function read_value(offset: number): unknown
		const type_of = buffer.readu8(b, offset)

		offset += 1

		if type_of == TYPE_NIL then
			return nil, offset
		elseif type_of == TYPE_NUMBER then
			return buffer.readf64(b, offset), offset + 8
		elseif type_of == TYPE_STRING then
			const length = buffer.readu8(b, offset)
			return buffer.readstring(b, offset + 1, length), offset + 1 + length
		elseif type_of == TYPE_TRUE then
			return true, offset
		elseif type_of == TYPE_FALSE then
			return false, offset
		elseif type_of == TYPE_TABLE then
			return { kind = "table", ptr = buffer.readu16(b, offset) },
				offset + 2
		elseif type_of == TYPE_LONGSTRING then
			return { kind = "string", ptr = buffer.readu16(b, offset) },
				offset + 2
		elseif type_of == TYPE_FUNCTION then
			const line_number = buffer.readu32(b, offset)
			const source_length = buffer.readu8(b, offset + 4)
			const name_length = buffer.readu8(b, offset + 5)

			const source = buffer.readstring(b, offset + 6, source_length)
			const name =
				buffer.readstring(b, offset + 6 + source_length, name_length)

			return {
				kind = "function",
				source = source,
				name = name,
				line = line_number,
			},
				offset + 6 + source_length + name_length
		elseif type_of == TYPE_CFUNCTION then
			const name_length = buffer.readu8(b, offset)
			const name = buffer.readstring(b, offset, name_length)

			return { kind = "cfunction", name = name }, offset + 1 + name_length
		elseif type_of == TYPE_VECTOR then
			return vector.create(
				buffer.readf32(b, offset),
				buffer.readf32(b, offset + 4),
				buffer.readf32(b, offset + 8)
			),
				offset + 12
		elseif type_of == TYPE_INT8 then
			return buffer.readi8(b, offset), offset + 1
		elseif type_of == TYPE_INT16 then
			return buffer.readi16(b, offset), offset + 2
		elseif type_of == TYPE_INT32 then
			return buffer.readi32(b, offset), offset + 4
		elseif type_of == TYPE_MISC then
			const length = buffer.readu8(b, offset)
			const typeof_length = buffer.readu8(b, offset + 1)

			const typeof_string =
				buffer.readstring(b, offset + 2, typeof_length)
			const value_string =
				buffer.readstring(b, offset + 2 + typeof_length, length)

			return {
				kind = "misc",
				typeof = typeof_string,
				value = value_string,
			},
				offset + 2 + length + typeof_length
		elseif type_of == TYPE_STOP then
			return nil, offset
		else
			return nil, offset
		end
	end

	const function read_registry_value(registry_idx: number)
		const offset = find_registry_offset(registry_idx)

		if offset == nil then
			return SYMBOL_DOES_NOT_EXIST
		end

		const regtype = buffer.readu8(b, offset)

		if regtype == REG_TYPE_LONGSTRING then
			const length = buffer.readu16(b, offset + 1)
			return buffer.readstring(b, offset + 3, length)
		elseif regtype == REG_TYPE_TABLE then
			const props = {}
			local pos = offset + 5
			local key, value

			while true do
				key, pos = read_value(pos)

				if key == nil then
					break
				end

				value, pos = read_value(pos)

				props[key] = value
			end

			return props
		else
			error(`unimplemented reg type {regtype}`)
		end
	end

	return {
		read_registry_value = read_registry_value,
	}
end

return {
	serialize = serialize,
	read = read_properties,
}
