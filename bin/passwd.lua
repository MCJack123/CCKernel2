if kernel == nil then error("This requires CCKernel2.") end
args = {...}
local uid
if args[1] ~= nil then
    uid = users.getUIDFromName(args[1])
    if uid == nil then error("user '" .. args[1] .. "' does not exist") end
else uid = users.getuid() end
if users.getuid() ~= 0 and users.getuid() ~= uid then error("You cannot view or modify password information for " .. users.getShortName(uid) .. ".") end
print("Changing password for user " .. users.getShortName(uid) .. ".")
if users.getuid() ~= 0 then
    write("(current) Password: ")
    if not users.checkPassword(uid, read("")) then error("Authentication failure") end
end
write("New password: ")
local pass = read("")
write("Confirm new password: ")
if read("") ~= pass then error("Sorry, passwords do not match") end
users.setPassword(uid, pass)
print("Password successfully changed")