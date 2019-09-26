if fs.setPermissions == nil then error("This requires CCKernel2.") end
args = { ... }
if args[2] == nil or args[1] == "--help" then
    print("Usage: chown <file> <uid>")
    return
end
if not fs.exists(args[1]) then error(args[1] .. ": File not found") end
local uid
if args[2] == "*" then uid = "*" else uid = tonumber(args[2]) end
if uid == nil then uid = users.getUIDFromName(args[2]) end
if uid == nil then error("Could not parse number or name " .. args[2]) end
fs.setOwner(args[1], uid)