const oi = require "./src"

oi.default()
	:add_sink(
		oi.stdio_output_sink { format = "full", include_timestamp = true }
	)
oi.info("test", nil)

-- oi.roblox_output {}
-- oi.roblox_structured_log_output()
-- oi.pipe()
oi.default():add_sink(oi.roblox)

print(_RUNTIME)
