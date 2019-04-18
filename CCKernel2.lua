--[[ 
CCKernel 2
Features: multiprocessing, IPC, permissions, signaling, virtual terminals, file descriptors, debugging, multiple users, filesystem reorganization, I/O operations

* [check] For multiprocessing, we need a run loop that executes coroutines in a table one by one.
* [check] For IPC, we need to pull events sent from each coroutine into the run loop. Then we need to check the PID, name, etc. and resend the events into the parallel coroutines.
* [check] For permissions, we need to rewrite the fs API to do virtual permission checks before opening the file. Storing permissions may have to be inside a hidden file at the root directory, storing the bits for permissions for each file.
* [check] For signaling, we need IPC + checking the events sent for specific signals. If the name matches, then we either a) do what the signal means (SIGKILL, SIGTERM, SIGSTOP, etc.), or b) relay the signal into the program.
* [check] For virtual terminals, we need to have multiple copies of the term API that can be switched as needed.
  * These copies are implemented as windows that are set visible or invisible depending on the VT currently being used.
* [check] For file descriptors, we need to catch opening these files in the fs API, and return the respective file handle for the file descriptor. Possible descriptors:
  * /dev/random: file.read() returns math.random(0, 255)
  * /dev/zero: file.read() returns 0
  * /dev/null: file.write() does nothing
  * /dev/stdout: file.write() writes a character to the terminal
  * /dev/stdin: file.read() returns the next character in the input or 0
  * /dev/fifo[0-9]: FIFO (first in, first out) files
* [check] For debugging, we need to have a debug entrypoint in the kernel that the processes can call on an error. Unfortunately, we cannot catch errors outside of coroutines, so enabling debugging support in a program will be the task of the programmer. (We'll probably just run rom/programs/lua.lua with the coroutine environment.)
  * Actually, if the coroutine environment is not copied on execution, it may be possible to examine the environment outside of the program. Catching errors outside and resuming will not be possible, but stepping through to each os.pullEvent() may be possible.
* [check] For multiple users, we need to implement a custom runtime for each coroutine. (We'll figure this out as we go.)
* [check] For filesystem reorganization, we just need to remap the files in /rom to /bin, /lib, /share, /etc, etc. inside the fs API. /rom will still be accessible.
* For I/O operations, we need to rewrite term.write() and read() to use piped data first, then use the normal I/O data. Each process will need to be aware of where it's being piped to.

This will be quite complicated and will fundamentally reshape CraftOS, but it will give so many new features to CraftOS at its base. I'm hoping to keep this as compatible with base CraftOS as possible, retaining support for all (most) programs. 
]]--

if shell == nil then error("CCKernel2 must be run from the shell.") end
if kernel ~= nil then error("CCKernel2 cannot be run inside itself.") end
local myself = shell.getRunningProgram()
fs.makeDir("/var")
fs.makeDir("/var/logs")

local argv = {...}
local kernel_args = 0
local kernel_arguments = {
    single = 1
}
for k,v in pairs(argv) do if kernel_arguments[v] ~= nil then kernel_args = bit.bor(kernel_args, kernel_arguments[v]) end end

-- os.loadAPI paths
local apipath = "/rom/apis:/usr/lib"
function os.APIPath() return apipath end
function os.setAPIPath( _sPath )
    if type( _sPath ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sPath ) .. ")", 2 ) 
    end
    apipath = _sPath
end

local function apilookup( _sTopic )
    if type( _sTopic ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sTopic ) .. ")", 2 ) 
    end
 	-- Look on the path variable
    for sPath in string.gmatch(apipath, "[^:]+") do
    	sPath = fs.combine( sPath, _sTopic )
    	if fs.exists( sPath ) and not fs.isDir( sPath ) then
			return sPath
        elseif fs.exists( sPath..".lua" ) and not fs.isDir( sPath..".lua" ) then
		    return sPath..".lua"
    	end
    end
    
    -- Check shell
    if shell ~= nil then return shell.resolveProgram(_sTopic) end
    
	-- Not found
	return _sTopic
end

local tAPIsLoading = {}
function os.loadAPI( _sPath )
    if type( _sPath ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sPath ) .. ")", 2 ) 
    end

    _sPath = apilookup( _sPath )

    local sName = fs.getName( _sPath )
    if sName:sub(-4) == ".lua" then
        sName = sName:sub(1,-5)
    end
    if tAPIsLoading[sName] == true then
        printError( "API "..sName.." is already being loaded" )
        return false
    end
    tAPIsLoading[sName] = true

    local tEnv = {}
    setmetatable( tEnv, { __index = _G } )
    local fnAPI, err = loadfile( _sPath, tEnv )
    if fnAPI then
        local ok, err = pcall( fnAPI )
        if not ok then
            --os.debug(err)
            printError( err )
            tAPIsLoading[sName] = nil
            return false
        end
    else
        printError( err )
        tAPIsLoading[sName] = nil
        return false
    end
    
    local tAPI = {}
    for k,v in pairs( tEnv ) do
        if k ~= "_ENV" then
            tAPI[k] =  v
        end
    end

    _G[sName] = tAPI    
    tAPIsLoading[sName] = nil
    return true
end

os.loadAPI("CCOSCrypto")
_G.CCLog = dofile(apilookup("CCLog"))
CCLog.default.consoleLogLevel = CCLog.logLevels.info
local kernelLog = CCLog("CCKernel2")
kernelLog:open()

-- FS rewrite
-- Permissions will be in a table with the key being the user ID and the value being a bitmask of the permissions allowed for that user.
-- A key of "*" will specify all users.
local permissions = {
    none = 0x0,
    read = 0x1,
    write = 0x2,
    read_write = 0x3,
    delete = 0x4,
    read_delete = 0x5,
    write_delete = 0x6,
    deny_execute = 0x7,
    execute = 0x8,
    read_execute = 0x9,
    write_execute = 0xA,
    deny_delete = 0xB,
    delete_execute = 0xC,
    deny_write = 0xD,
    deny_read = 0xE,
    full = 0xF,
    setuid = 0x10
}
-- Config setting: Default permissions for users without an entry
local default_permissions = permissions.full

kernelLog:debug("Initializing device files", "fs")
local deviceFiles = {
	random = {
        rb = {
            close = function() end,
            read = function() return math.random(0, 255) end
        },
        r = {
            close = function() end,
            readLine = function()
                local retval = ""
                while true do
                    local n = math.random(0, 255)
                    if n == string.byte("\n") then return retval end
                    retval = retval .. string.char(n)
                end
            end,
            readAll = function()
                    local i = 0
                local retval = ""
                while i < 1024 do retval = retval .. string.char(math.random(0, 255)) end
                return retval
            end
        },
        size = 1024,
        permissions = {["*"] = permissions.read}
    },
    zero = {
        rb = {
            close = function() end,
            read = function() return 0 end
        },
        r = {
            close = function() end,
            readLine = function() return string.rep(string.char(0), 1024) end,
            readAll = function() return string.rep(string.char(0), 1024) end
        },
        size = 1024,
        permissions = {["*"] = permissions.read}
    },
    null = {
        wb = {
            close = function() end,
            flush = function() end,
            write = function() end
        },
        w = {
            close = function() end,
            write = function() end,
            writeLine = function() end,
            flush = function() end
        },
        size = 0,
        permissions = {["*"] = permissions.write}
    }
}

local i = 0
while i < 10 do
    local data = ""
    local size = 0
    deviceFiles["fifo" .. i] = {
        rb = {
            close = function() end,
            read = function()
                local c = string.byte(string.sub(data, 1, 1))
                data = string.sub(data, 2)
                size = size - 1
                return c
            end
        },
        r = {
            close = function() end,
            readLine = function()
                local len = string.find(data, "\n")
                if len == nil then
                    local retval = data
                    data = ""
                    size = 0
                    return retval
                else
                    local retval = string.sub(data, 1, len)
                    data = string.sub(data, len)
                    size = size - len
                    return retval
                end
            end,
            readAll = function()
                local retval = data
                data = ""
                size = 0
                return retval
            end
        },
        wb = {
            close = function() end,
            flush = function() end,
            write = function(c) 
                data = data .. string.char(c)
                size = size + 1 
            end
        },
        w = {
            close = function() end,
            flush = function() end,
            write = function(d) 
                data = data .. d 
                size = size + string.len(d)
            end,
            writeLine = function(d) 
                data = data .. d .. "\n" 
                size = size + string.len(d) + 1
            end
        },
        size = size,
        permissions = {["*"] = permissions.read_write}
    }
    i = i + 1
end

local singleUserMode = false
_G._UID = 0
function setuid(uid) if _G._UID ~= 0 or uid < 0 or singleUserMode then return true else _G._UID = uid end end
function getuid() return _G._UID end

local function get_permissions(perms, uid)
    if uid == 0 then return permissions.full end
    if perms[uid] ~= nil then return perms[uid]
    elseif perms["*"] ~= nil then return perms["*"]
    else return default_permissions end
end

function bit.bmask(a, m) return bit.band(a, m) == m end
local function has_permission(perms, uid, p) return bit.bmask(get_permissions(perms, uid), p) end

singleUserMode = bit.bmask(kernel_args, kernel_arguments.single)

function table.keys(t)
    local retval = {}
    for k,v in pairs(t) do table.insert(retval, k) end
    return retval
end

function textutils.unserializeFile(path)
    local file = fs.open(path, "r")
    if file == nil then return nil end
    local retval = textutils.unserialize(file.readAll())
    file.close()
    return retval
end

function textutils.serializeFile(path, tab)
    local file = fs.open(path, "w")
    if file == nil then return end
    file.write(textutils.serialize(tab))
    file.close()
end

kernelLog:debug("Initializing filesystem", "fs")
local orig_fs = fs
_G.fs = {}

local devfs = {
    list = function(path)
        if path ~= "" and path ~= "/" then return nil
        else return table.keys(deviceFiles) end
    end,
    exists = function(path)
        if path == "" or path == "/" then return true end
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        return deviceFiles[path] ~= nil
    end,
    isDir = function(path) return path == "/" or path == "" end,
    getPermissions = function(path, uid)
        --print(path)
        if path == "/" or path == "" then return permissions.read end
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        if deviceFiles[path] == nil then return permissions.none end
        return get_permissions(deviceFiles[path].permissions, uid)
    end,
    setPermissions = function(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        error("/dev/" .. path .. ": Access denied", 3)
    end,
    setOwner = function(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        error("/dev/" .. path .. ": Access denied", 3)
    end,
    getOwner = function(path) return -1 end,
    getSize = function(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        if deviceFiles[path] == nil then error("/dev/" .. path .. ": No such file", 3) end
        return deviceFiles[path].size
    end,
    getFreeSpace = function() return 1 end,
    makeDir = function(path) 
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        error("/dev/" .. path .. ": Access denied", 3)
    end,
    move = function() error("Access denied", 3) end,
    copy = function(path, toPath)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        if deviceFiles[path] == nil then error("/dev/" .. path .. ": No such file", 3) end
        if not string.find(path, "fifo") then error("/dev/" .. path .. ": Infinite copy size", 3) end
        local retval = deviceFiles[path].r.readAll()
        local out, err = fs.open(toPath, "w")
        if out == nil then error(err, 3) end
        out.write(retval)
        out.close()
    end,
    delete = function()
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        error("/dev/" .. path .. ": Access denied", 3)
    end,
    open = function(path, mode)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        if deviceFiles[path] == nil then error("/dev/" .. path .. ": No such file", 3) end
        if mode == "a" then mode = "w"
        elseif mode == "ab" then mode = "wb"
        elseif mode ~= "r" and mode ~= "rb" and mode ~= "w" and mode ~= "wb" then error("Unsupported mode", 3) end
        if deviceFiles[path][mode] == nil then return nil, "/dev/" .. path .. ": Access denied"
        else return deviceFiles[path][mode] end
    end
}

local mounts = {["dev"] = devfs}

function fs.linkDir(from, to)
    if string.sub(from, string.len(from)) == "/" then from = string.sub(from, 1, string.len(from) - 1) end
    if string.sub(to, 1, 1) == "/" then to = string.sub(to, 2) end
    if string.sub(to, string.len(to)) == "/" then to = string.sub(to, 1, string.len(to) - 1) end
    local combine = function(path) if string.sub(path, 1, 1) == "/" then return from .. path else return from .. "/" .. path end end
    return {
        list = function(path) return fs.list(combine(path)) end,
        exists = function(path) return fs.exists(combine(path)) end,
        isDir = function(path) return fs.isDir(combine(path)) end,
        getPermissions = function(path, uid) return fs.getPermissions(combine(path), uid) end,
        setPermissions = function(path, uid, perm) return fs.setPermissions(combine(path), uid, perm) end,
        getSize = function(path) return fs.getSize(combine(path)) end,
        getFreeSpace = function(path) return fs.getFreeSpace(combine(path)) end,
        makeDir = function(path) return fs.makeDir(combine(path)) end,
        move = function(path, toPath) return fs.move(combine(path), toPath) end,
        copy = function(path, toPath) return fs.copy(combine(path), toPath) end,
        delete = function(path) return fs.delete(combine(path)) end,
        open = function(path, mode) return fs.open(combine(path), mode) end
    }
end

function fs.unlinkDir(to) if to ~= "dev" then mounts[to] = nil end end

local function getMount(path)
    if type(path) ~= "string" then error("bad argument #1 (expected string, got " .. type(path) .. ")", 5) end
    if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
    for k,v in pairs(mounts) do if string.find(path, k) == 1 then return v, string.sub(path, string.len(k) + 1) end end
    --print("orig_fs")
    return orig_fs, path
end

fs.permissions = permissions
fs.getName = orig_fs.getName
fs.combine = orig_fs.combine
fs.getDir = orig_fs.getDir
fs.complete = orig_fs.complete
fs.find = orig_fs.find
fs.linkDir("rom/programs", "bin")
fs.linkDir("rom/apis", "lib")
fs.linkDir("rom/help", "man")

function orig_fs.getPermissions(path, uid)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if orig_fs.getDrive(path) == "rom" then return permissions.read_execute end
    if not orig_fs.exists(path) then
        if not orig_fs.exists(fs.getDir(path)) then return permissions.none
        elseif not fs.hasPermissions(fs.getDir(path), uid, permissions.write) then return permissions.none
        else return permissions.write end
    end
    local default = orig_fs.isReadOnly(path) and permissions.read or permissions.full
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default}})
        return default
    end
    if uid == 0 then return default end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms[orig_fs.getName(path)] == nil then 
        perms[orig_fs.getName(path)] = {["*"] = default}
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
        return default
    else return get_permissions(perms[orig_fs.getName(path)], uid) end
end

function orig_fs.setPermissions(path, uid, perm)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if type(perm) ~= "number" or perm < 0 or perm > 0x1F then error("bad argument #3 (number expected, got " .. type(path) .. ")", 3) end
    if not orig_fs.exists(path) then error(path .. ": No such file", 3) end
    if orig_fs.getDrive(path) == "rom" then error(path .. ": Access denied", 3) end
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default, [uid] = perm}})
        return
    end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms[orig_fs.getName(path)] == nil then perms[orig_fs.getName(path)] = {["*"] = default, [uid] = perm}
    else
        if perms[orig_fs.getName(path)].owner ~= nil and perms[orig_fs.getName(path)].owner ~= _G._UID then error(path .. ": Access denied", 3) end
        perms[orig_fs.getName(path)][uid] = perm 
    end
    textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
end

function orig_fs.getOwner(path)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if orig_fs.getDrive(path) == "rom" then return -1 end
    if not orig_fs.exists(path) then return nil end
    local default = orig_fs.isReadOnly(path) and permissions.read or permissions.full
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default}})
        return
    end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms[orig_fs.getName(path)] == nil then 
        perms[orig_fs.getName(path)] = {["*"] = default}
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
        return
    else return perms[orig_fs.getName(path)].owner end
end

function orig_fs.setOwner(path, uid)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if not orig_fs.exists(path) then error(path .. ": No such file", 3) end
    if orig_fs.getDrive(path) == "rom" then error(path .. ": Access denied", 3) end
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default, owner = uid}})
        return
    end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms[orig_fs.getName(path)] == nil then perms[orig_fs.getName(path)] = {["*"] = default, owner = uid}
    else
        if perms[orig_fs.getName(path)].owner ~= nil and perms[orig_fs.getName(path)].owner ~= _G._UID then error(path .. ": Access denied", 3) end
        perms[orig_fs.getName(path)].owner = uid
    end
    textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
end

function fs.list(path)
    local m, p = getMount(path)
    if not bit.bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    local retval = m.list(p)
    for k,v in pairs(mounts) do if fs.getDir(k) == path then table.insert(retval, fs.getName(k)) end end
    return retval
end

function fs.exists(path)
    local m, p = getMount(path)
    return m.exists(p)
end

function fs.isDir(path)
    local m, p = getMount(path)
    return m.isDir(p)
end

function fs.isReadOnly(path)
    local m, p = getMount(path)
    return not bit.bmask(m.getPermissions(p, getuid()), permissions.write)
end

function fs.getPermissions(path, uid)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.getPermissions(p, uid)
end

function fs.setPermissions(path, uid, perm)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.setPermissions(p, uid, perm)
end

function fs.addPermissions(path, uid, perm)
    local m, p = getMount(path)
    if uid == nil then uid =getuid() end
    return m.setPermissions(p, uid, bit.bor(m.getPermissions(p, uid), perm))
end

function fs.getOwner(path)
    local m, p = getMount(path)
    return m.getOwner(p)
end

function fs.setOwner(path, uid)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.setOwner(p, uid)
end

function fs.getDrive(path)
    if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
    if not fs.exists(path) then return nil end
    for k,v in pairs(mounts) do if string.find(path, k) == 1 then return k end end
    return orig_fs.getDrive(path)
end

function fs.getSize(path)
    local m, p = getMount(path)
    return m.getSize(p)
end

function fs.getFreeSpace(path)
    local m = getMount(path)
    return m.getFreeSpace()
end

function fs.makeDir(path)
    local m, p = getMount(path)
    if fs.getDir(p) ~= "/" and fs.getDir(p) ~= "" and not fs.isDir(fs.getDir(p)) then error(fs.getDir(p) .. ": Directory not found") end
    if fs.getDir(p) ~= "/" and fs.getDir(p) ~= "" and not bit.bmask(m.getPermissions(fs.getDir(p), getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    m.makeDir(p)
    m.setPermissions(p, "*", fs.getPermissions(fs.getDir(path), "*"))
end

function fs.move(path, toPath)
    local m, p = getMount(path)
    if not bit.bmask(m.getPermissions(p, getuid()), permissions.delete) or not bit.bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if not bit.bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
    m.move(p, toPath)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    local outperms = textutils.unserializeFile(fs.getDir(toPath) .. "/.permissions")
    outperms[fs.getName(toPath)] = inperms[fs.getName(path)]
    inperms[fs.getName(path)] = nil
    textutils.serializeFile(fs.getDir(toPath) .. "/.permissions", outperms)
    textutils.serializeFile(fs.getDir(path) .. "/.permissions", inperms)
end

function fs.copy(path, toPath)
    local m, p = getMount(path)
    if not bit.bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if not bit.bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
    m.copy(p, toPath)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    local outperms = textutils.unserializeFile(fs.getDir(toPath) .. "/.permissions")
    outperms[fs.getName(toPath)] = inperms[fs.getName(path)]
    textutils.serializeFile(fs.getDir(toPath) .. "/.permissions", outperms)
end

function fs.delete(path)
    local m, p = getMount(path)
    if not bit.bmask(m.getPermissions(p, getuid()), permissions.delete) then error(path .. ": Access denied", 2) end
    m.delete(p)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    inperms[fs.getName(path)] = nil
    textutils.serializeFile(fs.getDir(path) .. "/.permissions", inperms)
end

function fs.open(path, mode)
    local m, p = getMount(path)
    if fs.getName(path) ~= ".permissions" then
        if string.sub(mode, 1, 1) == "r" and not bit.bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
        if string.sub(mode, 1, 1) == "w" and not bit.bmask(m.getPermissions(p, getuid()), permissions.write) then error(path .. ": Access denied", 2) end
        if string.sub(mode, 1, 1) == "a" and not bit.bmask(m.getPermissions(p, getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    end
    return m.open(p, mode)
end

function fs.mount(path, mount)
    if type(path) ~= "string" then error("bad argument #1 (expected string, got " .. type(path) .. ")", 2) end
    if type(mount) ~= "table" then error("bad argument #2 (expected table, got " .. type(path) .. ")", 2) end
    for k,v in pairs(devfs) do if mount[k] == nil then error("mount missing function " .. k, 2) end end
    mounts[path] = mount
end

function fs.hasPermissions(path, uid, perm) return bit.bmask(fs.getPermissions(path, uid), perm) end
function fs.mounts() return mounts end
function fs.reset() fs = orig_fs end

-- Rewrite executor
local orig_loadfile = loadfile
local nativeRun = os.run

_G.loadfile = function( _sFile, _tEnv )
    if type( _sFile ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sFile ) .. ")", 2 ) 
    end
    if _tEnv ~= nil and type( _tEnv ) ~= "table" then
        error( "bad argument #2 (expected table, got " .. type( _tEnv ) .. ")", 2 ) 
    end
    if not fs.hasPermissions( _sFile, nil, fs.permissions.execute ) then return nil, "Permission denied" end
    local file = fs.open( _sFile, "r" )
    if file then
        local func, err = load( file.readAll(), fs.getName( _sFile ), "t", _tEnv )
        file.close()
        if fs.hasPermissions( _sFile, nil, fs.permissions.setuid ) and err == nil then 
            return function( ... )
                local args = { ... }
                _G._SETUID = _G._UID
                _G._UID = fs.getOwner( _sFile )
                local val = { pcall( function() func( table.unpack( args ) ) end ) }
                _G._UID = _G._SETUID
                if not table.remove(val, 1) then error(table.remove(val, 1), 3)
                else return table.unpack(val) end
            end
        else return func, err end
    end
    return nil, "File not found"
end

function os.run( _tEnv, _sPath, ... )
    if type( _tEnv ) ~= "table" then
        error( "bad argument #1 (expected table, got " .. type( _tEnv ) .. ")", 2 ) 
    end
    if type( _sPath ) ~= "string" then
        error( "bad argument #2 (expected string, got " .. type( _sPath ) .. ")", 2 ) 
    end
    local tEnv = _tEnv
    setmetatable( tEnv, { __index = _G } )
    local pid = kernel.exec( _sPath, tEnv, ... )
    local _, p, s = os.pullEvent("process_complete")
    if p ~= pid then while p ~= pid do _, p, s = os.pullEvent("process_complete") end end
    return s
end

-- User system
-- Passwords are stored in /etc/passwd as a LON file with the format {UID = {password = sha256(pass), name = "name"}, ...}
kernelLog:debug("Initializing user system", "users")
fs.makeDir("/usr")
fs.makeDir("/usr/bin")
fs.makeDir("/usr/share")
fs.makeDir("/usr/share/help")
fs.makeDir("/usr/lib")
fs.makeDir("/etc")
fs.makeDir("/home")
if not fs.exists("/etc/passwd") then
    local user = {}
    print("Please create a new user.")
    write("Full name: ")
    user.fullName = read()
    write("Short name: ")
    user.name = read()
    while true do
        write("Password: ")
        local pass = read("")
        write("Confirm password: ")
        if read("") == pass then
            user.password = CCOSCrypto.sha256(pass)
            break
        end
        print("Sorry, try again.")
    end
    textutils.serializeFile("/etc/passwd", {
        [-1] = {name = "superroot", fullName = "Kernel Process", password = nil},
        [0] = {name = "root", fullName = "Superuser", password = nil},
        [1] = user
    })
end
shell.setPath(shell.path() .. ":/usr/bin")
help.setPath(help.path() .. ":/usr/share/help")

_G.users = {}

users.getuid = getuid
users.setuid = setuid

function users.getFullName(uid) 
    local fl = textutils.unserializeFile("/etc/passwd")
    if fl[uid] == nil then return nil else return fl[uid].fullName end --haha
end

function users.getShortName(uid) 
    local fl = textutils.unserializeFile("/etc/passwd")
    if fl[uid] == nil then return nil else return fl[uid].name end
end

function users.getUIDFromName(name)
    local fl = textutils.unserializeFile("/etc/passwd")
    for k,v in pairs(fl) do if v.name == name then return k end end
    return nil
end

function users.getUIDFromFullName(name)
    local fl = textutils.unserializeFile("/etc/passwd")
    for k,v in pairs(fl) do if v.name == name then return k end end
    return nil
end

function users.checkPassword(uid, password)
    local hash = CCOSCrypto.sha256(password)
    local fl = textutils.unserializeFile("/etc/passwd")
    return fl[uid] ~= nil and fl[uid].password == hash
end

function users.getHomeDir() 
    local retval = "/home/" .. users.getShortName(_G._UID)
    if not fs.exists(retval) then
        fs.makeDir(retval)
        fs.setOwner(retval)
        fs.setPermissions(retval, nil, fs.permissions.full)
        fs.setPermissions(retval, "*", fs.permissions.none)
    end
    return retval .. "/"
end

function users.create(name, uid)
    if users.getuid() ~= 0 then error("Permission denied", 2) end
    local fl = textutils.unserializeFile("/etc/passwd")
    uid = uid or table.maxn(fl) + 1
    fl[uid] = {name = name}
    textutils.serializeFile("/etc/passwd", fl)
end

function users.setFullName(uid, name)
    if users.getuid() ~= 0 and users.getuid() ~= uid then error("Permission denied", 2) end
    local fl = textutils.unserializeFile("/etc/passwd")
    if fl[uid] == nil then error("User ID " .. uid .. " does not exist", 2) end
    fl[uid].fullName = name
    textutils.serializeFile("/etc/passwd", fl)
end

function users.setPassword(uid, password)
    if users.getuid() ~= 0 and users.getuid() ~= uid then error("Permission denied", 2) end
    local fl = textutils.unserializeFile("/etc/passwd")
    if fl[uid] == nil then error("User ID " .. uid .. " does not exist", 2) end
    fl[uid].password = CCOSCrypto.sha256(password)
    textutils.serializeFile("/etc/passwd", fl)
end

function users.delete(uid)
    if users.getuid() ~= 0 then error("Permission denied", 2) end
    local fl = textutils.unserializeFile("/etc/passwd")
    fl[uid] = nil
    textutils.serializeFile("/etc/passwd", fl)
end

function users.hasBlankPassword(uid) return textutils.unserializeFile("/etc/passwd")[uid].password == nil end

-- Debugger in error function
local orig_error = error
os.debug_enabled = false
_ENV.error = function(message, level)
    if os.debug_enabled then 
        printError("Error caught: ", message)
        nativeRun(_ENV, "/rom/programs/lua.lua")
    end
    if level ~= nil then level = level + 1 end
    orig_error(message, level)
end

-- Virtual terminals
local vts = {}
local currentVT = 1
i = 1
while i < 9 do
    local w, h = term.getSize()
    vts[i] = window.create(term.native(), 1, 1, w, h, false)
    vts[i].started = false
    i = i + 1
end
vts[currentVT].setVisible(true)
vts[currentVT].started = true

-- Actual kernel runtime
kernelLog:debug("Initializing kernel calls")
_G.kernel = {}
_G.signal = {}
_G.signal = {
    SIGHUP = 1,
    SIGINT = 2,
    SIGQUIT = 3,
    SIGILL = 4,
    SIGTRAP = 5,
    SIGABRT = 6,
    SIGBUS = 7,
    SIGFPE = 8,
    SIGKILL = 9,
    SIGUSR1 = 10,
    SIGSEGV = 11,
    SIGUSR2 = 12,
    SIGPIPE = 13,
    SIGALRM = 14,
    SIGTERM = 15,
    SIGSTOP = 16,
    SIGCONT = 17,
    SIGIO = 18,
    getName = function(sig) for k,v in pairs(signal) do if sig == v then return k end end end
}

local process_table = {}
local nativeQueueEvent = os.queueEvent
local pidenv = {}
function kernel.exec(path, env, ...) 
    if type(env) == "table" then 
        pidenv[_G._PID] = env
        os.queueEvent("kcall_start_process", path, ...)
    else os.queueEvent("kcall_start_process", path, env, ...) end
    local _, pid = os.pullEvent("process_started")
    return pid
end
function kernel.fork(name, func, env, ...) 
    if type(env) == "table" then 
        pidenv[_G._PID] = env
        os.queueEvent("kcall_fork_process", string.dump(func), name, ...)
    else os.queueEvent("kcall_fork_process", string.dump(func), name, env, ...) end 
    local _, pid = os.pullEvent("process_started")
    return pid
end
function kernel.kill(pid, sig) os.queueEvent(signal.getName(sig), pid) end
function kernel.signal(sig, handler) os.queueEvent("kcall_signal_handler", sig, handler) end
function kernel.send(pid, ev, ...) nativeQueueEvent(ev, "CustomEvent,PID="..tostring(pid), ...) end
function kernel.broadcast(ev, ...) kernel.send(0, ev, ...) end
function kernel.getPID() return _G._PID end
function kernel.chvt(id) os.queueEvent("kcall_change_vt", id) end
function kernel.getvt() return currentVT end
function kernel.getArgs() return kernel_args end
kernel.arguments = kernel_arguments

function kernel.getProcesses()
    os.queueEvent("kcall_get_process_table")
    local ev, t = os.pullEvent("kcall_get_process_table")
    return t
end

-- handlers is a table with the format {event_1 = function(...), event_2 = function(...), ...}
function kernel.receive(handlers)
    if type(handlers) ~= "table" then error("bad argument #1 (expected table, got " .. type(handlers) .. ")") end
    while true do
        local e = {os.pullEvent()}
        local ev = table.remove(e, 1)
        for k,v in pairs(handlers) do if k == ev then if v(table.unpack(e)) then break end end end
    end
end

kernel.log = kernelLog

function deepcopy(orig, level)
    level = level or 0
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' and level < 200 and orig ~= _ENV and orig ~= _G and orig._ENV ~= orig then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            if orig ~= orig_value and orig_key ~= "env" then copy[deepcopy(orig_key, level + 1)] = deepcopy(orig_value, level + 1)
            else copy[orig_key] = orig_value end
        end
        --if getmetatable(orig) ~= nil and getmetatable(orig).__index ~= _G then setmetatable(copy, deepcopy(getmetatable(orig))) end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function wrappedRun( _tEnv, _sPath, ... )
    if type( _tEnv ) ~= "table" then
        error( "bad argument #1 (expected table, got " .. type( _tEnv ) .. ")", 2 ) 
    end
    if type( _sPath ) ~= "string" then
        error( "bad argument #2 (expected string, got " .. type( _sPath ) .. ")", 2 ) 
    end
    --os.debug("Executing " .. _sPath)
    local tArgs = table.pack( ... )
    local tEnv = _tEnv
    setmetatable( tEnv, { __index = _G } )
    if _G.shell ~= nil and (_G.shell == {} or _G.shell.run == nil) then _G.shell = nil end
    if tEnv.shell ~= nil and (tEnv.shell == {} or tEnv.shell.run == nil) then tEnv.shell = nil end
    local fnFile, err = loadfile( _sPath, tEnv )
    if fnFile then
        local ok, err = pcall( function()
            --os.debug("Starting")
            fnFile( table.unpack( tArgs, 1, tArgs.n ) )
        end )
        if not ok then
            if err and err ~= "" then
                printError( err )
            end
            --os.debug("Run failed")
            return false
        end
        --os.debug("Run succeeded")
        return true
    end
    if err and err ~= "" then
        printError( err )
    end
    --os.debug("?")
    return false
end

function os.queueEvent(ev, ...) nativeQueueEvent(ev, "CustomEvent,PID=" .. _G._PID, ...) end

local firstProgram = shell.resolveProgram("init")
local loginProgram = shell.resolveProgram("login")
if singleUserMode then loginProgram = "/rom/programs/shell.lua" end

fs.setPermissions(firstProgram, "*", bit.bor(fs.permissions.setuid, fs.permissions.read_execute))
fs.setOwner(firstProgram, 0)

local oldPath = shell.path()
local kernel_running = true
--if shell ~= nil then shell.setPath(oldPath .. ":/" .. CCKitGlobals.CCKitDir .. "/ktools") end
table.insert(process_table, {coro=coroutine.create(nativeRun), path=firstProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=1, loggedin=true, env=_ENV})
term.clear()
term.setCursorPos(1, 1)
local orig_shell = shell
kernel.log:info("Starting CCKernel2.")
while kernel_running do
    if not vts[currentVT].started then 
        table.insert(process_table, {coro=coroutine.create(nativeRun), path=loginProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=currentVT, parent=0, loggedin=false, env=_ENV}) 
        vts[currentVT].started = true
    end
    local e = {os.pullEvent()}
    if process_table[1] == nil then
        --log:log("First process stopped, ending CCKernel")
        print("Press enter to continue.")
        read()
        kernel_running = false
    end
    if e[1] == "key" and keys.getName(e[2]) ~= nil and string.find(keys.getName(e[2]), "f%d+") == 1 then
        local num = tonumber(string.sub(keys.getName(e[2]), 2))
        if num >= 1 and num <= 8 then
            vts[currentVT].setVisible(false)
            term.clear()
            vts[num].setVisible(true)
            currentVT = num
            if not vts[num].started then 
                table.insert(process_table, {coro=coroutine.create(nativeRun), path=loginProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=num, loggedin=false, parent=0, env=_ENV}) 
                vts[num].started = true
            end
        elseif num == 12 then
            _G._PID = nil
            print("Kernel paused.")
            _ENV.kill_kernel=function() 
                kernel_running = false
                --getfenv(2).exit()
            end
            print("Entering debugger.")
            nativeRun(_ENV, "/rom/programs/lua.lua")
            print("Resuming.")
        end
    end
    local PID = 0
    if type(e[2]) == "string" and string.find(e[2], "CustomEvent,PID=") ~= nil then
        PID = tonumber(string.sub(e[2], string.len("CustomEvent,PID=")+1))
        --print("Sending " .. e[1] .. " to " .. tostring(PID))
        table.remove(e, 2)
    end
    if e[1] == "kcall_get_process_table" then
        e[2] = deepcopy(process_table)
        e[2][0] = {coro=nil, path=myself, started=true, filter=nil, stopped=false, args={}, signals={}, user=0, vt=0, loggedin=true, parent=0}
    elseif e[1] == "kcall_login_changed" and process_table[PID].user == 0 then
        process_table[PID].loggedin = e[2]
        if not e[2] then vts[process_table[PID].vt].started = false end
    end
    if signal[e[1]] ~= nil then
        local sig = signal[e[1]]
        local pid = e[2]
        if process_table[pid] ~= nil then
            if sig == signal.SIGKILL and process_table[PID].user == 0 then
                kernel.send(table.remove(process_table, pid).parent, "process_complete", pid, false)
                local c = term.getTextColor()
                term.setTextColor(colors.red)
                print("Killed")
                term.setTextColor(c)
            elseif sig == signal.SIGINT then
                local continue = true
                if process_table[pid].signals[signal.SIGINT] ~= nil then continue = process_table[pid].signals[signal.SIGINT](signal.SIGINT) end
                if continue then kernel.send(table.remove(process_table, pid).parent, "process_complete", pid, false) end
            elseif sig == signal.SIGSTOP then
                process_table[pid].stopped = true
            elseif sig == signal.SIGCONT then
                process_table[pid].stopped = false
            elseif (sig == signal.SIGBUS or sig == signal.SIGFPE or sig == signal.SIGILL or sig == signal.SIGIO or sig == signal.SIGPIPE or sig == signal.SIGSEGV or sig == signal.SIGTERM or sig == signal.SIGTRAP) and process_table[PID].user == 0 then
                if process_table[pid].signals[sig] ~= nil then process_table[pid].signals[sig](sig) end
                kernel.send(table.remove(process_table, pid).parent, "process_complete", pid, false)
            elseif process_table[pid].signals[sig] ~= nil then process_table[pid].signals[sig](sig) end
        end
    elseif e[1] == "kcall_start_process" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local env = pidenv[PID]
        table.insert(process_table, {coro=coroutine.create(nativeRun), path=path, started=false, stopped=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user, vt=process_table[PID].vt, loggedin=true, parent=PID})
        pidenv[PID] = nil
        kernel.send(PID, "process_started", #process_table)
    elseif e[1] == "kcall_fork_process" then
        table.remove(e, 1)
        local func = table.remove(e, 1)
        local name = table.remove(e, 1) or "anonymous"
        kernel.log:debug(name)
        if func == nil then kernel.log:debug("Func is nil") end
        local env = pidenv[PID]
        table.insert(process_table, {coro=coroutine.create(loadstring(func)), path="["..name.."]", started=false, stopped=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user, vt=process_table[PID].vt, loggedin=true, parent=PID})
        kernel.send(PID, "process_started", #process_table)
    elseif e[1] == "kcall_signal_handler" then
        process_table[PID].signals[e[1]] = e[2]
    elseif e[1] == "kcall_change_vt" then
        if e[2] > 0 and e[2] <= 8 then
            vts[currentVT].setVisible(false)
            term.clear()
            vts[e[2]].setVisible(true)
            currentVT = e[2]
        end
    else
        local delete = {}
        local loggedin = false
        for k,v in pairs(process_table) do
            if v.loggedin then loggedin = true end
            if not v.stopped and (v.filter == nil or v.filter == e[1]) and (v.vt == currentVT or not (
                e[1] == "key" or e[1] == "char" or e[1] == "key_up" or e[1] == "paste" or
                e[1] == "mouse_click" or e[1] == "mouse_up" or e[1] == "mouse_drag" or 
                e[1] == "mouse_scroll" or e[1] == "monitor_touch")) then
                local err = true
                local res = nil
                if v.started then
                    if PID == 0 or PID == k then
                        _G._PID = k
                        _G._FORK = false
                        _G._UID = v.user
                        --if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = n end end
                        --shell = nil
                        term.redirect(vts[v.vt])
                        err, res = coroutine.resume(v.coro, unpack(e))
                        term.redirect(term.native())
                        --shell = orig_shell
                        --if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = nil end end
                        v.user = _G._UID
                    end
                else
                    _G._PID = k
                    _G._FORK = true -- only check this before first yield
                    _G._UID = v.user
                    _G.shell = nil
                    --if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = n end end
                    --shell = nil
                    --_ENV.shell = nil
                    if vts[v.vt] == nil then
                        print(v.vt)
                        os.sleep(5)
                    end
                    term.redirect(vts[v.vt])
                    if v.env == nil then v.env = {} end
                    err, res = coroutine.resume(v.coro, v.env, v.path, unpack(v.args))
                    term.redirect(term.native())
                    --_ENV.shell = orig_shell
                    --shell = orig_shell
                    --if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = nil end end
                    v.started = true
                    v.user = _G._UID
                end
                if not err then table.insert(delete, {f=k, s=false})
                elseif coroutine.status(v.coro) == "dead" then table.insert(delete, {f=k, s=true, r=res})
                elseif res ~= nil then v.filter = res else v.filter = nil end -- assuming every yield is for pullEvent, this may be unsafe 
            end
        end
        for k,v in pairs(delete) do kernel.send(table.remove(process_table, v.f).parent, "process_complete", v.f, v.s, v.r) end
        if not loggedin then break end
    end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
os.run = nativeRun
os.queueEvent = nativeQueueEvent
error = orig_error

_G.fs = orig_fs
_G.loadfile = orig_loadfile
_G._PID = nil
_G._UID = nil
_G.kernel = nil
_G.users = nil
_G.signals = nil
currentVT = nil
if shell ~= nil then shell.setPath(oldPath) end
--os.shutdown()