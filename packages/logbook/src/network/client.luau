--!strict
--[[

logs get received from the server

normal process:
- the client should receive the shim, process the shim and create the necessary datastructure
- client should then receive supplementary log properties, which fill out the buffer. if the client determines a slice is missing, add it to a queue of slices to process

erroneous processes 1
- client does NOT receive the shim
- client receives supplementary log properties for a log it does not know about
	in this case, the client should request the log again, store the packet data in a temporary buffer in the mean time.

erroneous processes 2
- client receives shim
- client receives supplementary log properties, but something is missing?
	in this case, the client still writes to the properties buffer, but also adds the missing packet to the queue.
	if this packet has not been received in this frame, assume something went wrong. re-request the packet.
	mark the properties buffer to be missing data from x to y

erroneous processes 3
- client receives next shim, previous log is missing in its entirety?
	in this case, the client should request the previous log again

? it might be interesting to look into doing bitpacking, to expand the allowed number of templates to 2^20 or 2^24
todo: we still need to request for missing packets.

]]

const logbook = require("../logbook")
const serde = require("../serde")
const source = require("../source")

type LogId = number
type LostSlice = { from: number, upto: number } -- upto is not including

type AdditionalSourceLogData = {
	read logs: { [LogId]: logbook.SerializedLogEvent },
	read serialized_upto: { [LogId]: number },
	read max_serialized_upto: { [LogId]: number },
	read missing_template: { [number]: { LogId } },
	logs_counter: number, -- initialized at -1

	read orphaned_slices: { [LogId]: { buffer } },
	read lost_slices: { [LogId]: { LostSlice } },
	read missing_logs: { [LogId]: true },
}

const FLAG_NEW_TEMPLATE = 0b1000_0000_0000_0000_0000_0000_0000_0000

const MAP_LOG_LEVEL_ID_TO_LEVEL = {
	[0] = "error",
	[1] = "warn",
	[2] = "info",
	[3] = "debug",
	[4] = "trace",

	error = 0,
	warn = 1,
	info = 2,
	debug = 3,
	trace = 4,
}

const MISSING_TEMPLATE_PLACEHOLDER = "missing template, attempting to recover"
const MAP_SOURCE_ID_TO_LOG_IDS: { [number]: AdditionalSourceLogData } = {}
const QUEUE_SOURCES_WITH_MISSED_LOGS: { [number]: boolean } = {}

const function get_log_data_for_source_id(source_id: number)
	const logs = MAP_SOURCE_ID_TO_LOG_IDS[source_id]

	if logs then
		return logs
	end

	const logs_data: AdditionalSourceLogData = {
		logs = setmetatable({}, { __mode = "v" }),
		serialized_upto = {},
		max_serialized_upto = {},
		orphaned_slices = {},
		missing_logs = {},
		missing_template = {},
		lost_slices = {},
		logs_counter = -1,
	}

	MAP_SOURCE_ID_TO_LOG_IDS[source_id] = logs_data

	return logs_data
end

const function get_orphaned_slices(source_id: number, log_id: number)
	const data = get_log_data_for_source_id(source_id)
	const slices = data.orphaned_slices[log_id]

	if slices then
		return slices
	end

	const new_slices = {}

	return new_slices
end

const function handle_missing_log_shims(
	source_id: number,
	next_log_id: number,
	check_current_log: boolean
)
	const logs_data = get_log_data_for_source_id(source_id)
	const previous_received_log_id = logs_data.logs_counter
	logs_data.logs_counter = next_log_id

	-- when check_current_log is true, it means we don't actually know if the current log exists.
	-- when check_current_log is false, it means we know the current log exists (probably cuz we received it)
	-- we also remove the current log from the missing log counter, if its there
	if check_current_log == false then
		logs_data.missing_logs[next_log_id] = nil
	end

	-- logs counter is not yet initialized
	if previous_received_log_id == -1 then
		return
	end

	-- we are further ahead than expected, everything is ok!
	-- it is also ok if the next log is just 1 ahead, since that means there's no gap
	if previous_received_log_id + 1 >= previous_received_log_id then
		return
	end

	-- oh no! we missed a log
	-- get the missing log(s), add it to the queue of missing logs
	for i = previous_received_log_id + 1, next_log_id do
		logs_data.missing_logs[i] = true
	end

	-- mark that we are missing logs
	QUEUE_SOURCES_WITH_MISSED_LOGS[source_id] = true
end

const function reconcile_slice_into_buffer(
	properties: buffer,
	b: buffer,
	pos: number
)
	const write_from = buffer.readu32(b, pos)
	const total_encoded_registry_values = buffer.readu8(b, pos + 4) -- gng what am i meant to do w this
	const offset =
		serde.find_registry_offset(b, total_encoded_registry_values, pos + 5)

	if offset == nil then
		error(
			`missing offset when trying to find idx {total_encoded_registry_values} from {pos + 5}. should be unreachable?`
		)
	end

	buffer.copy(properties, write_from, b, pos + 5, offset - pos + 5)

	return write_from, offset
end

const function find_last_missing_slice(slices: { LostSlice }, from: number)
	for i, slice in slices do
		if slice.from > from then
			return i - 1
		end
	end

	return #slices
end

const function mark_slice_as_used(
	source_id: number,
	log_id: number,
	from: number,
	upto: number
)
	const logs_data = get_log_data_for_source_id(source_id)

	if logs_data.lost_slices[log_id] == nil then
		logs_data.lost_slices[log_id] = {}
	end

	const serialized_upto = logs_data.serialized_upto[log_id] -- not including
	const lost_slices = logs_data.lost_slices[log_id]
	const max_serialized_upto = logs_data.max_serialized_upto[log_id]

	-- just extend it
	if serialized_upto == from then
		logs_data.serialized_upto[log_id] = upto
	else -- we are missing some data inbetween the last slice and the given slice
		-- we need to figure out if we are marking an area that is already "lost"
		const previous_slice_index = find_last_missing_slice(lost_slices, from)
		const previous_slice = lost_slices[previous_slice_index]

		if previous_slice == nil then -- there was no slice at all, so this is the first one
			const lost_slice: LostSlice =
				{ from = max_serialized_upto, upto = from }
			table.insert(lost_slices, lost_slice)
		elseif previous_slice and from > max_serialized_upto then -- new missing slice
			const lost_slice: LostSlice =
				{ from = max_serialized_upto, upto = from }
			table.insert(lost_slices, lost_slice)
		elseif previous_slice and from == max_serialized_upto then
			-- nothing happens, since we just extend the part we already know
		elseif from == previous_slice.from and upto == previous_slice.upto then -- we are the missing slice
			table.remove(lost_slices, previous_slice_index)

			if previous_slice_index == 1 then -- if we are the first slice, we can extend the serialized upto part
				logs_data.serialized_upto[log_id] = upto
			end
		elseif from == previous_slice.from and upto < previous_slice.upto then -- we have the start of the missing slice
			previous_slice.from = upto

			if previous_slice_index == 1 then -- if we are the first slice, we can extend the serialized upto part
				logs_data.serialized_upto[log_id] = upto
			end
		elseif from > previous_slice.from and upto == previous_slice.upto then -- we have the end of the missing slice
			previous_slice.upto = from
		elseif from > previous_slice.from and upto < previous_slice.upto then -- we are a part of the missing slice :suffering: just not the start or end
			const slice_a: LostSlice =
				{ from = previous_slice.from, upto = from }
			const slice_b: LostSlice =
				{ from = upto, upto = previous_slice.upto }

			lost_slices[previous_slice_index] = slice_a --overwrite previous slice
			table.insert(lost_slices, previous_slice_index + 1, slice_b)
		else -- usually means we intersect multiple slices or smth, shouldnt happen though unless Roblox apparently allows data corruption
			-- ? we need to investigate how to make this code more error resilient
			error(`we are given a case we are not able to deal with\z
			\nlog max serialized {max_serialized_upto}\z
			\nlost slice from: {previous_slice.from} upto: {previous_slice.upto}\z
			\nreceived slice from: {from} upto: {upto}`)
		end
	end

	logs_data.max_serialized_upto[log_id] = math.max(max_serialized_upto, upto)
end

const function mark_missing_template(
	source_id: number,
	template_id: number,
	log_id: number
)
	const logs_data = get_log_data_for_source_id(source_id)
	const missing_data = logs_data.missing_template[template_id]

	if missing_data then
		table.insert(missing_data, log_id)
		return MISSING_TEMPLATE_PLACEHOLDER
	end

	logs_data.missing_template[template_id] = { log_id }

	return MISSING_TEMPLATE_PLACEHOLDER
end

-- handles setting the data necessary when receiving a new template
-- additionally also updates the logs with missing templates
const function receive_new_template(
	source_id: number,
	template_id: number,
	template_string: string
)
	const logs_data = get_log_data_for_source_id(source_id)
	const logs_with_missing_templates = logs_data.missing_template[template_id]

	for _, log_id in logs_with_missing_templates do
		const log = logs_data.logs[log_id]

		if log == nil then
			continue
		end -- log probably got gc'd

		log.template = template_string
	end

	return template_string
end

const function read_new_template(
	origin: source.Source,
	b: buffer,
	pos: number,
	template_id: number
): string
	const template_length = buffer.readu16(b, pos)
	const template = buffer.readstring(b, pos + 2, template_length)
	origin.map_templatestring_to_id[template] = template_id
	origin.map_id_to_templatestring[template_id] = template

	receive_new_template(origin.source_id, template_id, template)

	return template
end

const function on_server_receive_base_timestamp(timestamp: number)
	const origin = source.server_source
	assert(origin.origin ~= "self")

	origin.timestamp = timestamp
end

-- the server sent the client a bunch of shims that we can display
const function on_server_receive_new_log_shims(shims: buffer)
	const origin = source.server_source
	assert(origin.origin ~= "self")

	const b = shims
	const length = buffer.len(b)
	local pos = 0

	const function get_template_string(template_id: number)
		return origin.map_id_to_templatestring[template_id]
	end

	const source_data = get_log_data_for_source_id(origin.source_id)

	while pos < length do
		const log_id_and_flags = buffer.readu32(b, pos)
		const log_level = buffer.readu8(b, pos + 1)
		const log_template_id = buffer.readu16(b, pos + 2)
		const timestamp = origin.timestamp + buffer.readu32(b, pos + 4)
		const total_length = buffer.readu32(b, pos + 8)
		const total_registry_values = buffer.readu8(b, pos + 12)

		const log_id =
			bit32.band(bit32.bnot(FLAG_NEW_TEMPLATE), log_id_and_flags)
		const new_template = bit32.btest(log_id_and_flags, FLAG_NEW_TEMPLATE) -- indicates we received a new template.

		const template = if new_template
			then read_new_template(origin, b, pos + 13, log_template_id)
			else get_template_string(log_template_id) or mark_missing_template(
				origin.source_id,
				log_template_id,
				log_id
			)
		-- mark the template as missing

		pos += if new_template then 15 + #template else 13

		-- we need to check for if a previous log was missing
		handle_missing_log_shims(origin.source_id, log_id - 1, false) -- the previous log should exist

		const log_buffer = buffer.create(total_length)

		const upto = serde.find_registry_offset(b, total_registry_values, pos)

		if upto == nil then
			error(
				`missing offset when trying to find idx {total_registry_values} from {pos}. should be unreachable?`
			)
		end

		const length_slice = upto - pos
		const log = {
			level = MAP_LOG_LEVEL_ID_TO_LEVEL[log_level],
			template = template,
			timestamp = timestamp,
			source = origin.source_id,

			properties = log_buffer,
		}

		buffer.copy(log_buffer, 0, b, pos, length_slice)

		source_data.logs[log_id] = log
		source_data.serialized_upto[log_id] = length_slice
		source_data.max_serialized_upto[log_id] = length_slice -- we dont need to mark these slices as used since we do it here manually

		-- check for slices that mightve need to get processed, but lacked a shim, which we now have
		-- we can also check for missing slices :<
		const adopting_slices = source_data.orphaned_slices[log_id]
		if adopting_slices then
			for _, slice in adopting_slices do
				mark_slice_as_used(
					origin.source_id,
					log_id,
					reconcile_slice_into_buffer(log_buffer, slice, 0)
				)
			end

			-- we adopted the slices :)
			source_data.orphaned_slices[log_id] = nil
		end

		logbook.append_serialized_log(origin, log)
		pos = upto
	end
end

-- the server sent the client packets containg Properties that we can add to existing logs
const function on_server_receive_log_packet(incoming: buffer)
	const origin = source.server_source
	assert(origin.origin ~= "self")

	const b = incoming
	const length = buffer.len(b)
	local pos = 0
	const source_data = get_log_data_for_source_id(origin.source_id)

	const function process_packet(b: buffer, pos: number)
		const log_id = buffer.readu32(b, pos)
		const total_registry_values = buffer.readu8(b, pos + 8)

		-- pos += 9

		-- we need to check if the log exists
		const log = source_data.logs[log_id] -- log does not exist...

		if log ~= nil then
			const write_from, upto =
				reconcile_slice_into_buffer(log.properties, b, pos)
			mark_slice_as_used(origin.source_id, log_id, write_from, upto)

			pos = upto
		else -- log does not exist??
			const offset =
				serde.find_registry_offset(b, total_registry_values, pos + 9)

			if offset == nil then
				error(
					`missing offset when trying to find idx {total_registry_values} from {pos + 5}. should be unreachable?`
				)
			end
			const orphaned = get_orphaned_slices(origin.source_id, log_id)
			const slice = buffer.create(offset - pos)

			buffer.copy(slice, 0, b, pos + 4, offset)

			table.insert(orphaned, slice)
			pos = offset
		end
	end

	while pos < length do
		process_packet(b, pos)
	end
end

const function on_server_receive_template(templates: buffer)
	const origin = source.server_source
	const b = templates
	local pos = 0

	while pos < buffer.len(templates) do
		const template_id = buffer.readu16(b, pos)

		pos += 4 + #read_new_template(origin, b, pos + 2, template_id)
	end
end

return {
	on_server_receive_base_timestamp = on_server_receive_base_timestamp,
	on_server_receive_new_log_shims = on_server_receive_new_log_shims,
	on_server_receive_log_packet = on_server_receive_log_packet,
	on_server_receive_template = on_server_receive_template,
}
