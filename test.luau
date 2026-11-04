const oi = require "./src"

oi.default()
	:add_sink(
		oi.stdio_output_sink { format = "full", include_timestamp = true }
	)
oi.info("test", nil)
