-- This file must be setuid + owner = 0
if fs.setPermissions == nil then error("This requires CCKernel2.") end
if not fs.hasPermissions(shell.getRunningProgram(), "*", fs.permissions.setuid) then
    if fs.getOwner(shell.getRunningProgram()) == nil or fs.getOwner(shell.getRunningProgram()) == users.getuid() then
        fs.addPermissions(shell.getRunningProgram(), "*", fs.permissions.setuid)
        if fs.getOwner(shell.getRunningProgram()) == nil then fs.setOwner(shell.getRunningProgram(), 0) end
        print("Please try again.")
        return
    else error("sudo must be owned by 0 and have the setuid bit set") end
end
local i = 0
while i < 3 do
    write("[sudo] password for " .. users.getShortName(_G._SETUID) .. ": ")
    local password = read("")
    if users.checkPassword(_G._SETUID, password) then return shell.run(...) end
    print("Sorry, try again.")
    i = i + 1
end
error("3 incorrect password attempts")