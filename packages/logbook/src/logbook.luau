const source = require("./source")
const serde = require("./serde")
const log = require("@pkgs/log")

export type Level = log.LoggingLevel
export type SerializedLogEvent = {
	read level: Level,
	read template: string,
	read timestamp: number,
	read source: number,

	properties: { b: buffer, upto: number },
}

const SOFT_CAP_LOGS = 5_000
const OVERFLOW_CAP_LOGS = 300 -- the amount of additional logs we can have.
const MAX_LOGS_UNTIL_FORCE_EVICTION = SOFT_CAP_LOGS + OVERFLOW_CAP_LOGS -- the max amount of logs stored until we forcefully evict some

const SHARED_LOGS: { SerializedLogEvent } = {}

const function evict_logs()
	const size = #SHARED_LOGS
	const keep_from = #SHARED_LOGS - SOFT_CAP_LOGS + 1

	-- we can evict all the logs in a single table move call.
	table.move(SHARED_LOGS, keep_from, size + #SHARED_LOGS - keep_from, 1)
end

const function append_unserialized_log(
	source: source.Source,
	log: log.LogEvent
): SerializedLogEvent
	const properties = serde.serialize(log.properties)
	const event = {
		level = log.level,
		template = log.template,
		timestamp = log.timestamp,
		source = source.source_id,

		properties = properties,
	}

	table.insert(SHARED_LOGS, event)

	if #SHARED_LOGS > MAX_LOGS_UNTIL_FORCE_EVICTION then
		evict_logs()
	end
end

const function append_serialized_log(
	source: source.Source,
	log: SerializedLogEvent
): SerializedLogEvent
	const event = {
		level = log.level,
		template = log.template,
		timestamp = log.timestamp,
		source = source.source_id,

		properties = log.properties,
	}

	table.insert(SHARED_LOGS, event)

	if #SHARED_LOGS > MAX_LOGS_UNTIL_FORCE_EVICTION then
		evict_logs()
	end
end

return {
	evict_logs = evict_logs,

	append_unserialized_log = append_unserialized_log,
	append_serialized_log = append_serialized_log,

	SHARED_LOGS = SHARED_LOGS,
}
