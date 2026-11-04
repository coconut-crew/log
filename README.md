# log

a logging package meant to serve as an interface for logging.

loosely based off of rust's log package, slightly modified.

new logs using `log.info("hello {name}", { name = "alice" })`. levels exist (in order of severity) error, warn, info, debug, trace.

create new loggers through `log.create()`. obtain the default logger that the library uses globally through `log.default()`. add sinks, which consume logs with `logger:add_sink(sink)`, and add enrichers which enrich logs with additional data through `logger:add_enricher(enricher)`. enrichers operate in the order they are added in. you cannot remove any sinks or enrichers after the fact. sinks operate in a random order.

call `logger.info`, or other logging functions directly onto the logger to log directly to that logger. call `log.set_logger(logger)` to change the logger that the library logs to. reset to the default logger with `log.set_logger(log.default())`.

log provides several default sinks:

- roblox output sink
this renders the text and outputs it to the Roblox output. it can be added through `logger:add_sink(log.roblox_output({ format = "full" }))`

- roblox structured log sink
this outputs logs directly to Roblox's structured logs system. it can be added through `logger:add_sink(log.roblox_structured_log_output())`.

- output with ansi colors
this outputs logs to stdout. it can be added through `logger:add_sink(log.stdio_output_sink({ format = "full" }))`.

- pipe
this pipes all logs given to a logger to another logger when they come in.
it can be added through `logger:add_sink(log.pipe(into))`. be aware of recursion, when a log gets piped to another logger, all enrichers and sinks will run again.

it is recommended to use `log.set_unix_timestamp_provider`. by default, it is set to `os.time` in Luau, and `DateTime.now().UnixTimestampMillis` in Roblox. for other runtimes, it is recommended to invoke this function with your own provider.
