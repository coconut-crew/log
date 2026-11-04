local obtain_unix_timestamp_impl = if DateTime
	then function() return DateTime.now().UnixTimestampMillis end
	else os.time

export type LoggingLevel = | "trace" | "debug" | "error" | "warn" | "info"

export type SourceKind = string

export type LogEvent = {
	level: LoggingLevel,
	timestamp: number,
	source_context: string?,
	source_kind: SourceKind,
	template: string,

	properties: { [string]: any },
}

export type LogSink = (message: LogEvent) -> ()
export type LogEnricher = (LogEvent) -> ()

export type Logger = {
	enrichers: { LogEnricher },
	sinks: { LogSink },

	info: (Logger, template: string, ...any) -> (),
	warn: (Logger, template: string, ...any) -> (),
	error: (Logger, template: string, ...any) -> (),
	debug: (Logger, template: string, ...any) -> (),
	trace: (Logger, template: string, ...any) -> (),

	add_sink: (Logger, sink: LogSink) -> (),
	add_enricher: (Logger, sink: LogSink) -> (),
}

export type LogConfiguration = {}

export type Renderer = {
	text: (Text) -> string,
	hole: (Hole, unknown) -> string,
}

export type Kind = | "text" | "hole" | "name" | "format" | "eof"

export type Issue = {
	read why: string,
	read span: vector,
}

export type Text = {
	kind: "text",
	text: string,
}

export type Format = {
	kind: "format",
	text: string,
}

export type Hole = {
	kind: "hole",

	type: "name",
	name: string,
	format: Format?,
}

const function char(c: string): number return string.byte(c) :: number end

local pos = 0
local len = 0
local input = buffer.create(0)

const function peek(): number
	if pos == len then return 0 end
	return buffer.readu8(input, pos) :: any
end

const function peek_2(): number
	if pos + 1 >= len then return 0 end
	return buffer.readu8(input, pos + 1) :: any
end

const function bump() pos = math.min((pos + 1) :: any, len) end

const function is_digit(c: number): boolean
	return char "0" <= c and c <= char "9"
end

const function is_alpha(c: number): boolean
	return (char "a" <= c and c <= char "z")
		or (char "A" <= c and c <= char "Z")
		or c == char "_"
end

const function read_format(): Format
	local c = peek()
	bump()

	const from = pos
	while true do
		c = peek()
		if c == char "}" then
			break
		else
			bump()
		end
	end

	return {
		kind = "format",
		text = buffer.readstring(input, from, pos - from),
	}
end

const function read_hole(): Hole
	bump()

	local format: Format?
	local c = peek()

	local from = pos
	local name

	while true do
		c = peek()

		if c == char ":" then
			name = buffer.readstring(input, from, pos - from)
			format = read_format()
		elseif is_alpha(c) then
			bump()
		elseif is_digit(c) then
			bump()
		elseif c == char "}" then
			if name == nil then
				name = buffer.readstring(input, from, pos - from)
			end

			bump()
			break
		elseif c == 0 then
			error "expected } but got eof"
		else
			error(`cannot parse {c} as part of hole`)
		end
	end

	assert(name ~= nil, "missing name for the hole")

	const hole = {
		kind = "hole",

		type = "name",
		format = format,

		name = name :: any,
	}

	return hole :: Hole
end

const function parse(b: buffer)
	pos = 0
	len = buffer.len(b)
	input = b

	const nodes = {}

	local text_start_from = 0

	const function output_text(): Text?
		if text_start_from == pos then return nil end

		return {
			kind = "text" :: "text",
			span = vector.create(text_start_from, pos),
			text = buffer.readstring(b, text_start_from, pos - text_start_from),
		}
	end

	while pos < len do
		const c: number = peek()
		const l: number = peek_2()

		if c == char "{" and l ~= char "{" then
			table.insert(nodes, output_text())
			table.insert(nodes, read_hole())
			text_start_from = pos
		elseif c == char "{" and l == char "{" then
			bump()
			bump()
		else
			bump()
		end
	end
	table.insert(nodes, output_text())

	return nodes
end
---

local CACHED_LOGS = setmetatable({}, { __mode = "vs" })

const function get_nodes(input: string): { Hole | Text }
	if CACHED_LOGS[input] then return CACHED_LOGS[input] end
	const nodes = parse(buffer.fromstring(input))
	CACHED_LOGS[input] = nodes
	return nodes
end

const function pipe_log(self: Logger, structured_log: LogEvent)
	for _, enrich in self.enrichers do
		enrich(structured_log)
	end

	for _, sink in self.sinks do
		sink(structured_log)
	end
end

const function log(
	self: Logger,
	level: LoggingLevel,
	template: string,
	ctx: { [string]: any }
)
	get_nodes(template)
	const structured_log: LogEvent = {
		level = level,
		timestamp = obtain_unix_timestamp_impl(),
		source_kind = "none",
		template = template,

		properties = ctx,
	}

	pipe_log(self, structured_log)
end

const function render(renderer: Renderer, log: LogEvent): string
	const nodes = get_nodes(log.template)
	const output = {}

	for idx, node in nodes do
		output[idx] = if node.kind == "hole"
			then renderer.hole(node, log.properties[node.name :: string])
			else renderer.text(node)
	end

	return table.concat(output)
end

const MAX_ELEMENTS = 10
const nodes = {}
const plain_text_renderer: Renderer = {
	text = function(node: Text) return node.text end,
	hole = function(node: Hole, value: unknown)
		if node.prefix == "$" then
			return tostring(value)
		else
			if typeof(value) == "table" then
				table.insert(nodes, "{")
				local length = 0
				for key, value in value do
					if #nodes > 0 then nodes[length] = nodes[length] .. "," end
					if length > MAX_ELEMENTS then
						table.insert(nodes, "...")
						break
					end

					if typeof(key) == "string" then
						table.insert(nodes, tostring(key))
					else
						table.insert(nodes, `[{tostring(key)}]`)
					end

					table.insert(nodes, "=")
					table.insert(nodes, tostring(value))

					length += 1
				end

				table.insert(nodes, "}")

				local s = table.concat(nodes, ",")
				table.clear(nodes)
				return s
			else
				return tostring(value)
			end
		end
	end,
}

const function logger_info(self, template, ctx) log(self, "info", template, ctx) end

const function logger_warn(self, template, ctx) log(self, "warn", template, ctx) end

const function logger_error(self, template, ctx)
	log(self, "error", template, ctx)
end

const function logger_debug(self, template, ctx)
	log(self, "debug", template, ctx)
end

const function logger_trace(self, template, ctx)
	log(self, "trace", template, ctx)
end

const function add_sink(self: Logger, sink: LogSink)
	table.insert(self.sinks, sink)
end

const function add_enricher(self: Logger, enricher: LogEnricher)
	table.insert(self.sinks, enricher)
end

const function create_logger(p: {
	enrichers: { LogEnricher }?,
	sinks: { LogSink }?,
}): Logger
	return {
		sinks = p.sinks or {},
		enrichers = p.enrichers or {},

		info = logger_info,
		warn = logger_warn,
		error = logger_error,
		debug = logger_debug,
		trace = logger_trace,

		add_sink = add_sink,
		add_enricher = add_enricher,
	}
end

const function roblox_output(p: {
	format: "short" | "full",
	throw_on_errors: boolean?,
	prefix: string?,
})
	return function(log: LogEvent)
		const tag = if p.format == "short" and log.level == "debug"
			then "DBG"
			elseif p.format == "short" and log.level == "error" then "ERR"
			elseif p.format == "short" and log.level == "info" then "INF"
			elseif p.format == "short" and log.level == "trace" then "TRC"
			elseif p.format == "short" and log.level == "warn" then "WRN"
			elseif log.level == "debug" then "DEBUG"
			elseif log.level == "error" then "ERROR"
			elseif log.level == "info" then "INFO"
			elseif log.level == "trace" then "trace"
			elseif log.level == "warn" then "WARN"
			else error "unknown log level"

		const text = `{if p.prefix then `[{p.prefix}] ` else ""}[{tag}] {render(
			plain_text_renderer,
			log
		)}`

		if
			log.level == "debug"
			or log.level == "info"
			or log.level == "trace"
		then
			print(text)
		elseif log.level == "error" and p.throw_on_errors then
			error(text)
		elseif log.level == "error" or log.level == "warn" then
			warn(text)
		end
	end
end

const function roblox_structured_log_sink()
	const LogService = game:GetService "LogService"

	const cached_template_strings = setmetatable({}, { __mode = "kvs" })
	const roblox_template_renderer: Renderer = {
		hole = function(hole) return `\{{hole.name}\}` end,
		text = function(text) return text.text end,
	}

	const function get_template(log: LogEvent)
		const cached_template = cached_template_strings[log.template]

		if cached_template ~= nil then return cached_template end

		const rendered = render(roblox_template_renderer, log)
		cached_template_strings[log.template] = rendered

		return rendered
	end

	return function(log: LogEvent)
		const level = if log.level == "info"
			then Enum.MessageType.MessageInfo
			elseif log.level == "error" then Enum.MessageType.MessageError
			elseif log.level == "warn" then Enum.MessageType.MessageWarning
			else Enum.MessageType.MessageOutput
		const template = get_template(log)

		LogService:Log(level, template, log.properties)
	end
end

const function stdio_output(p: {
	format: "short" | "full",
	include_timestamp: boolean?,
	prefix: string?,
})
	const RED = "\x1b[0;31m"
	const BLUE = "\x1b[0;34m"
	const GREEN = "\x1b[0;32m"
	const YELLOW = "\x1b[0;33m"
	const GRAY = "\x1b[0;37m"
	const RESET = "\x1b[0m"

	return function(log: LogEvent)
		const tag = if p.format == "short" and log.level == "debug"
			then `{GREEN}DBG{RESET}`
			elseif
				p.format == "short" and log.level == "error"
			then `{RED}ERR{RESET}`
			elseif
				p.format == "short" and log.level == "info"
			then `{BLUE}INF{RESET}`
			elseif
				p.format == "short" and log.level == "trace"
			then `{GRAY}TRC{RESET}`
			elseif
				p.format == "short" and log.level == "warn"
			then `{YELLOW}WRN{RESET}`
			elseif log.level == "debug" then `{GREEN}DEBUG{RESET}`
			elseif log.level == "error" then `{RED}ERROR{RESET}`
			elseif log.level == "info" then `{BLUE}INFO{RESET}`
			elseif log.level == "trace" then `{GRAY}TRACE{RESET}`
			elseif log.level == "warn" then `{YELLOW}WARN{RESET}`
			else error "unknown log level"

		const text =
			`{if p.prefix then `[{p.prefix}] ` else ""}[{tag}] {if p.include_timestamp
				then os.date("%x %X ", log.timestamp)
				else ""}{render(plain_text_renderer, log)}`

		print(text)
	end
end

const function pipe(into: Logger)
	return function(event: LogEvent)
		const copy = table.clone(event)
		copy.properties = if copy.properties
			then table.clone(copy.properties)
			else copy.properties

		pipe_log(into, copy)
	end
end

const default_logger = create_logger {}
local current_logger = default_logger

const oi = {
	set_logger = function(logger: Logger) current_logger = logger end,

	roblox_output = roblox_output,
	roblox_structured_log_output = roblox_structured_log_sink,
	stdio_output_sink = stdio_output,
	pipe = pipe,

	set_unix_timestamp_provider = function(provider: () -> number)
		obtain_unix_timestamp_impl = provider
	end,

	create = create_logger,
	default = function() return default_logger end,
	render = render,

	plain_text_renderer = plain_text_renderer,

	info = function(template, ctx) logger_info(current_logger, template, ctx) end,

	warn = function(template, ctx) logger_warn(current_logger, template, ctx) end,

	error = function(template, ctx) logger_error(current_logger, template, ctx) end,

	debug = function(template, ctx) logger_debug(current_logger, template, ctx) end,

	trace = function(template, ctx) logger_trace(current_logger, template, ctx) end,
}

return oi
