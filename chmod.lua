if fs.setPermissions == nil then error("This requires CCKernel2.") end
args = { ... }
if args[3] == nil or args[1] == "--help" then
    print("Usage: chmod <file> <uid> <perms>")
    return
end
if not fs.exists(args[1]) then error(args[1] .. ": File not found") end
local uid
if args[2] == "*" then uid = "*" else uid = tonumber(args[2]) end
if uid == nil then error("Could not parse number " .. args[2]) end
local perms = tonumber(args[3])
if perms == nil then error("Could not parse number " .. args[3]) end
fs.setPermissions(args[1], uid, perms)
