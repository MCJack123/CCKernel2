-- This file must be setuid + owner = 0
if fs.setPermissions == nil then error("This requires CCKernel2.") end
if not fs.hasPermissions(shell.getRunningProgram(), "*", fs.permissions.setuid) or _G._UID ~= 0 then
    if fs.getOwner(shell.getRunningProgram()) == nil or fs.getOwner(shell.getRunningProgram()) == users.getuid() then
        fs.addPermissions(shell.getRunningProgram(), "*", fs.permissions.setuid)
        if fs.getOwner(shell.getRunningProgram()) == nil then fs.setOwner(shell.getRunningProgram(), 0) end
        print("Please try again.")
        return
    else error("su must be owned by 0 and have the setuid bit set") end
end
print(os.version() .. "\n")
while true do
    write("Login: ")
    local uid = users.getUIDFromName(read())
    write("Password: ")
    local password = read("")
    if not users.checkPassword(uid, password) then print("Login incorrect\n")
    else
        users.setuid(uid)
        shell.run("/rom/programs/shell.lua")
        return
    end
end