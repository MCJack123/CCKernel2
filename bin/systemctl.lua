if services == nil then error("System has not been booted with CCInit as init system (PID 1). Can't operate.") end
local args = {...}
if args[1] == "list" then 
    local tab = {{"Service", "Status"}}
    for k,v in pairs(services.list()) do table.insert(tab, {k, v and "running" or "stopped"}) end
    textutils.tabulate(table.unpack(tab))
    return
end
if args[2] == nil or args[1] == nil then 
    print("Usage: systemctl list\n       systemctl <service> <start|stop|restart|status|pid>") 
    return
end
if args[1] == "start" then services.start(args[2])
elseif args[1] == "stop" then services.stop(args[2])
elseif args[1] == "restart" then services.restart(args[2])
elseif args[1] == "status" then
    local status = services.status(tostring(args[2]))
    write("Status of " .. args[2] .. ": ")
    term.blit(status and "running" or "stopped", status and "5555555" or "eeeeeee", "fffffff")
    print()
elseif args[1] == "pid" then print(tostring(services.pid(tostring(args[2]))))
else print("Usage: systemctl --status-all\n       systemctl <service> <start|stop|restart|status|pid>") end