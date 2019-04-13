if fs.setPermissions == nil then error("This requires CCKernel2.") end
args = { ... }
if args[3] == nil or args[1] == "--help" then
    print("Usage: chmod <file> <uid> <perms>")
    return
end
if not fs.exists(args[1]) then error(args[1] .. ": File not found") end
local uid
if args[2] == "*" then uid = "*" else uid = tonumber(args[2]) end
if uid == nil then uid = users.getUIDFromName(args[2]) end
if uid == nil then error("Could not parse number or name " .. args[2]) end
local perms = tonumber(args[3])
if perms == nil then 
    local r = string.find(args[3], "r") ~= nil and fs.permissions.read or 0
    local w = string.find(args[3], "w") ~= nil and fs.permissions.write or 0
    local x = string.find(args[3], "x") ~= nil and fs.permissions.execute or 0
    local d = string.find(args[3], "d") ~= nil and fs.permissions.delete or 0
    local s = string.find(args[3], "s") ~= nil and fs.permissions.setuid or 0
    perms = bit.bor(bit.bor(bit.bor(bit.bor(r, w), x), d), s)
    if perms == 0 then perms = nil end
end
if perms == nil then error("Could not parse number or string " .. args[3]) end
fs.setPermissions(args[1], uid, perms)
