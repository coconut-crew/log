const log = require("@pkgs/log")
const logbook = require("@self/logbook")
const source = require("@self/source")

const function LOG_SINK(event: log.LogEvent)
	logbook.append_unserialized_log(source.self_source, event)
end

const function on_actor_receive_log(vm_id: number, event: log.LogEvent)
	const origin = source.get_self_source(vm_id)
	logbook.append_serialized_log(origin, log)
end

const function connect_default_lifecycle() end

return {
	sink = LOG_SINK,
}
