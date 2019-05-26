if kernel == nil then error("This requires CCKernel2.") end

CCLog.default.consoleLogLevel = CCLog.logLevels.warning

function status(message, stat)
    if stat == nil then 
        write("        ")
        kernel.log:info(message)
    elseif stat then 
        term.blit("[ OK ]  ", "05555000", "ffffffff")
        kernel.log:info(message)
    else 
        term.blit("[FAIL]  ", "0eeee000", "ffffffff") 
        kernel.log:error(message)
    end
    print(message)
    return stat
end

print("Welcome to CCKernel2!")

if not fs.isDir("/etc/init") then error("CCInit is not installed properly, please reinstall.") end
--[[
* /etc/init/ stores initialization files
  * user/ stores services run after boot
    * All services are executed in a random-ish order, but with dependencies respected
  * system/ stores services and targets run at boot
    * targets/ stores the targets to be started
      * multiuser.ltn is started on normal boot
      * singleuser.ltn is started in single user mode
      * shutdown.ltn is started on shutdown
      * reboot.ltn is started on reboot
      * early.ltn is started before multiuser and singleuser
    * services/ stores the services that the targets require
]] 

local function readService(service)
    local path = nil
    if fs.exists("/etc/init/user/" .. service .. ".ltn") then path = "/etc/init/user/" .. service .. ".ltn"
    elseif fs.exists("/etc/init/system/services/" .. service .. ".ltn") then path = "/etc/init/system/services/" .. service .. ".ltn"
    else return nil end
    return textutils.unserializeFile(path)
end

serviceDatabase = {}

function startService(sname)
    if serviceDatabase[sname] ~= nil then return true end
    if sname == "initd" then
        status("Starting Init Daemon...")
        serviceDatabase[sname] = kernel.fork("initd", initd)
        kernel.setProcessProperty(serviceDatabase[sname], "loggedin", false)
        return status("Started Init Daemon.", true)
    end
    local service = readService(sname)
    if service == nil then return status("Could not find service " .. sname .. ".", false) end
    if service.dependencies ~= nil and #service.dependencies > 0 then
        for k,v in ipairs(service.dependencies) do if not startService(sname) then return false end end
    end
    status("Starting " .. service.description .. "...")
    if service.prestart ~= nil and #service.prestart > 0 then for k,v in ipairs(service.prestart) do 
        if not os.run(_ENV, table.unpack(v)) then
            kernel.log:error("Failed to run prestart script " .. v[1] .. ".", "CCInit")
            return status("Failed to start service " .. service.description .. ". See the logs for more info.", false)
        end
    end end
    serviceDatabase[sname] = kernel.exec(table.unpack(service.exec))
    kernel.setProcessProperty(serviceDatabase[sname], "term", CCLog(sname):terminal())
    kernel.setProcessProperty(serviceDatabase[sname], "loggedin", false)
    if service.poststart ~= nil and #service.poststart > 0 then for k,v in ipairs(service.poststart) do 
        if not os.run(_ENV, table.unpack(v)) then
            kernel.log:error("Failed to run poststart script " .. v[1] .. ".", "CCInit")
            stopService(sname)
            return status("Failed to start service " .. service.description .. ". See the logs for more info.", false)
        end
    end end
    return status("Started " .. service.description .. ".", true)
end

function stopService(sname)
    if serviceDatabase[sname] == nil then return true end
    if sname == "initd" then
        status("Stopping Init Daemon...")
        kernel.kill(serviceDatabase[sname], signal.SIGTERM) 
        return status("Stopped Init Daemon.", true)
    end
    local service = readService(sname)
    if service == nil then return status("Could not find service " .. sname .. ".", false) end
    status("Stopping " .. service.description .. "...")
    if service.prestop ~= nil and #service.prestop > 0 then for k,v in ipairs(service.prestop) do 
        if not os.run(_ENV, table.unpack(v))  then
            kernel.log:error("Failed to run prestop script " .. v[1] .. ".", "CCInit")
            return status("Failed to stop service " .. service.description .. ". See the logs for more info.", false)
        end
    end end
    if service.stop ~= nil then os.run(_ENV, table.unpack(service.stop))
    else 
        kernel.kill(serviceDatabase[sname], signal.SIGTERM) 
        --os.pullEvent()
    end
    serviceDatabase[sname] = nil
    if service.poststop ~= nil and #service.poststop > 0 then for k,v in ipairs(service.poststop) do 
        if not os.run(_ENV, table.unpack(v))  then
            kernel.log:error("Failed to run poststop script " .. v[1] .. ".", "CCInit")
            return status("Failed to completely stop service " .. service.description .. ". See the logs for more info.", false)
        end
    end end
    return status("Stopped " .. service.description .. ".", true)
end

function restartService(sname) return stopService(sname) and startService(sname) end

local function reachTarget(tname)
    local target = textutils.unserializeFile("/etc/init/system/targets/" .. tname .. ".ltn")
    if target == nil then return status("Could not find target " .. sname .. ".", false) end
    if target.prerun ~= nil and #target.prerun > 0 then for k,v in ipairs(target.prerun) do
        if not reachTarget(v) then return status("Failed to reach target " .. target.description .. ".", false) end
    end end
    for k,v in ipairs(target.requires) do if not startService(v) then
        return status("Failed to reach target " .. target.description .. ".", false)
    end end
    return status("Reached target " .. target.description .. ".", true)
end

function initd()
    while true do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "service_start" then startService(p1)
        elseif ev == "service_stop" then stopService(p1)
        elseif ev == "service_restart" then restartService(p1)
        elseif ev == "service_get_pid" then kernel.send(p1 or 0, "service_pid", serviceDatabase[p2])
        elseif ev == "service_get_status" then
            local retval = false
            if serviceDatabase[p2] ~= nil then 
                retval = kernel.getProcesses()[serviceDatabase[p2]] ~= nil 
                if not retval then serviceDatabase[p2] = nil end
            end
            kernel.send(p1 or 0, "service_status", retval)
        elseif ev == "service_get_list" then
            local retval = {initd = true}
            local ptab = kernel.getProcesses()
            local list = fs.list("/etc/init/system/services")
            for k,v in pairs(list) do 
                if v ~= ".permissions" then
                    local service = string.gsub(v, ".ltn", "")
                    local status = false
                    if serviceDatabase[service] ~= nil then 
                        status = ptab[serviceDatabase[service]] ~= nil 
                        if not status then serviceDatabase[service] = nil end
                    end
                    retval[service] = status
                end
            end
            kernel.send(p1 or 0, "service_list", retval)
        end
    end
end

local nativeShutdown = os.shutdown
local nativeReboot = os.reboot

function os.shutdown()
    reachTarget("shutdown")
    local stop = {}
    for k,v in pairs(serviceDatabase) do stop[k] = v end
    for k,v in pairs(stop) do stopService(k) end
    status("Starting Shutdown...")
    nativeShutdown()
end

function os.reboot()
    reachTarget("reboot")
    local stop = {}
    for k,v in pairs(serviceDatabase) do stop[k] = v end
    for k,v in pairs(stop) do stopService(k) end
    status("Starting Reboot...")
    nativeReboot()
end

local startTarget = bit.bmask(kernel.getArgs(), kernel.arguments.single) and "singleuser" or "multiuser"
if not reachTarget(startTarget) then return status("Could not start CCKernel2.", false) end

_G.services = {}
function services.start(sname) kernel.send(serviceDatabase["initd"], "service_start", sname) end
function services.stop(sname) kernel.send(serviceDatabase["initd"], "service_stop", sname) end
function services.restart(sname) kernel.send(serviceDatabase["initd"], "service_restart", sname) end
function services.pid(sname)
    kernel.send(serviceDatabase["initd"], "service_get_pid", _PID, sname)
    return select(2, os.pullEvent("service_pid"))
end
function services.status(sname)
    kernel.send(serviceDatabase["initd"], "service_get_status", _PID, sname)
    return select(2, os.pullEvent("service_status"))
end
function services.list()
    kernel.send(serviceDatabase["initd"], "service_get_list", _PID)
    return select(2, os.pullEvent("service_list"))
end
services.running = true

os.sleep(2)

if bit.bmask(kernel.getArgs(), kernel.arguments.single) then
    write("Press return to enter maintenance mode: ")
    read()
end

while services.running do
    shell.run(bit.bmask(kernel.getArgs(), kernel.arguments.single) and "shell" or "login")
    --kernel.setProcessProperty(_PID, "loggedin", false)
    local ptab = kernel.getProcesses()
    local loggedin = false
    for k,v in pairs(ptab) do if v.loggedin and k ~= _PID then loggedin = true end end
    if loggedin == false then break end
end

local stop = {}
for k,v in pairs(serviceDatabase) do stop[k] = v end
for k,v in pairs(stop) do stopService(k) end
os.shutdown = nativeShutdown
os.reboot = nativeReboot
_G.services = nil
kernel.setProcessProperty(_PID, "loggedin", false)
kernel.kill(0, signal.SIGKILL)