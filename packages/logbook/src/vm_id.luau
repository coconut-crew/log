--[[
this module allows for generating a VM id within Roblox by incrementing a global counter

]]

const function get_roblox_vm_id()
	const SharedTableRegistry = game:GetService("SharedTableRegistry")

	const shared_table =
		SharedTableRegistry:GetSharedTable("_logbook_common_vm_count")
	shared_table.id = shared_table.id or 0

	return SharedTable.increment(shared_table, "id", 1)
end

return if game and SharedTable then get_roblox_vm_id() else 0
