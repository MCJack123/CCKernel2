-- This file must be setuid + owner = 0
term.clear()
term.setCursorPos(1, 1)
print(os.version() .. " tty" .. tostring(kernel.getvt()) .. "\n")
if fs.setPermissions == nil then error("This requires CCKernel2.") end
if users.getuid() ~= 0 then error("login must run as user 0") end
CCLog.default.consoleLogLevel = CCLog.logLevels.error
while true do
    kernel.setProcessProperty(_PID, "loggedin", false)
    write("Login: ")
    local uid = users.getUIDFromName(read())
    write("Password: ")
    local password = read("")
    if not users.checkPassword(uid, password) then print("Login incorrect\n") else
        kernel.setProcessProperty(_PID, "loggedin", true)
        users.setuid(uid)
        local oldDir = shell.dir()
        shell.setDir("~")
        shell.run("shell")
        shell.setDir(oldDir)
        kernel.setProcessProperty(_PID, "loggedin", false)
        term.clear()
        term.setCursorPos(1, 1)
        local ptab = kernel.getProcesses()
        local loggedin = false
        for k,v in pairs(ptab) do if v.loggedin and k ~= 1 then loggedin = true end end
        if loggedin == false then services.running = false end
        return
    end
end