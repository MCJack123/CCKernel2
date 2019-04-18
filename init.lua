if kernel == nil then print("This requires CCKernel2.") end

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
    else kernel.kill(serviceDatabase[sname], signal.SIGTERM) end
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

local nativeShutdown = os.shutdown
local nativeReboot = os.reboot

function os.shutdown()
    reachTarget("shutdown")
    for k,v in pairs(serviceDatabase) do stopService(k) end
    nativeShutdown()
end

function os.reboot()
    reachTarget("reboot")
    for k,v in pairs(serviceDatabase) do stopService(k) end
    nativeReboot()
end

local startTarget = bit.bmask(kernel.getArgs(), kernel.arguments.single) and "singleuser" or "multiuser"

if not reachTarget(startTarget) then return status("Could not start CCKernel2.", false) end

_G.services = {}
services.start = startService
services.stop = stopService
services.restart = restartService
function services.pid(sname, pid) return serviceDatabase[sname] end
function services.status(sname) if serviceDatabase[sname] == nil then return false else return kernel.getProcesses()[serviceDatabase[sname]] ~= nil end end

os.sleep(3)
shell.run(bit.bmask(kernel.getArgs(), kernel.arguments.single) and "shell" or "login")

for k,v in pairs(serviceDatabase) do stopService(k) end
os.shutdown = nativeShutdown
os.reboot = nativeReboot
_G.services = nil

-- TODO: give services a fake term using a log instead of the real term