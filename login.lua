-- This file must be setuid + owner = 0
term.clear()
print(os.version() .. " tty" .. tostring(kernel.getvt()) .. "\n")
if fs.setPermissions == nil then error("This requires CCKernel2.") end
if users.getuid() ~= 0 then error("login must run as user 0") end
while true do
    write("Login: ")
    local uid = users.getUIDFromName(read())
    write("Password: ")
    local password = read("")
    if not users.checkPassword(uid, password) then print("Login incorrect\n")
    else
        os.queueEvent("kcall_login_changed", true)
        os.pullEvent("kcall_login_changed")
        users.setuid(uid)
        shell.run("shell")
        os.queueEvent("kcall_login_changed", false)
        os.pullEvent("kcall_login_changed")
        term.clear()
        return
    end
end