const source = require("./source")
const FLAG_NEW_TEMPLATE = 0b1000_0000_0000_0000_0000_0000_0000_0000
const

const function on_server_receive_base_timestamp(timestamp: number) end

-- the server sent the client a bunch of shims that we can display
const function on_server_receive_new_log_shims(shims: buffer)
	const origin = source.server_source
	assert(origin.origin ~= "self")

	const b = shims
	const length = buffer.len(b)
	local pos = 0

	const function get_new_template(
		b: buffer,
		pos: number,
		template_id: number
	): string
		const template_length = buffer.readu16(b, pos + 8)
		const template = buffer.readstring(b, pos + 10, template_length)
		origin.map_templatestring_to_id[template] = template_id
		origin.map_id_to_templatestring[template_id] = template
		pos += 10 + template_length
	end

	const function get_template_string(template_id: number)
		return origin.map_id_to_templatestring[template_id]
	end

	while pos < length do
		const log_id = buffer.readu32(b, pos)
		const log_level = buffer.readu8(b, pos + 1)
		const log_template_id = buffer.readu16(b, pos + 2)
		const timestamp = origin.timestamp + buffer.readu32(b, pos + 4)
		const total_length = buffer.readu32(b, pos + 8)
		const total_encoded_registry_values = buffer.readu8(b, pos + 12)

		const new_template = bit32.btest(log_id, FLAG_NEW_TEMPLATE) -- indicates we received a new template.

		const template = if new_template
			then get_new_template(b, pos + 13, log_template_id)
			else get_template_string(log_template_id)

		pos += if new_template then 15 + #template else 13
	end
end

-- the server sent the client packets containg Properties that we can add to existing logs
const function on_server_receive_log_packet(incoming: buffer) end
