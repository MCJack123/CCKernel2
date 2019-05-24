--[[ 
CCKernel 2
Features: multiprocessing, IPC, permissions, signaling, virtual terminals, device files, debugging, multiple users, filesystem reorganization, I/O operations

* [check] For multiprocessing, we need a run loop that executes coroutines in a table one by one.
* [check] For IPC, we need to pull events sent from each coroutine into the run loop. Then we need to check the PID, name, etc. and resend the events into the parallel coroutines.
* [check] For permissions, we need to rewrite the fs API to do virtual permission checks before opening the file. Storing permissions may have to be inside a hidden file at the root directory, storing the bits for permissions for each file.
* [check] For signaling, we need IPC + checking the events sent for specific signals. If the name matches, then we either a) do what the signal means (SIGKILL, SIGTERM, SIGSTOP, etc.), or b) relay the signal into the program.
* [check] For virtual terminals, we need to have multiple copies of the term API that can be switched as needed.
  * These copies are implemented as windows that are set visible or invisible depending on the VT currently being used.
* [check] For device files, we need to catch opening these files in the fs API, and return the respective file handle for the device file. Possible devices:
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
* [check] For I/O operations, we need to rewrite term.write() and read() to use piped data first, then use the normal I/O data. Each process will need to be aware of where it's being piped to.

This will be quite complicated and will fundamentally reshape CraftOS, but it will give so many new features to CraftOS at its base. I'm hoping to keep this as compatible with base CraftOS as possible, retaining support for all (most) programs. 
]]--

local nativeReboot = os.reboot
local nativeTerminal = term.native()
local ok, err = pcall(function(...)

if shell == nil then error("CCKernel2 must be run from the shell.") end
if kernel ~= nil then error("CCKernel2 cannot be run inside itself.") end
local myself = shell.getRunningProgram()
fs.makeDir("/var")
fs.makeDir("/var/logs")
term.clear()
term.setCursorPos(1, 1)

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

    -- Check absolute path
    if fs.exists(_sTopic) then return _sTopic
    elseif fs.exists(_sTopic .. ".lua") then return _sTopic .. ".lua" end

 	-- Look on the path variable
    for sPath in string.gmatch(apipath, "[^:]+") do
        sPath = fs.combine( sPath, _sTopic )
        if sPath == nil then error("sPath is nil") end
    	if fs.exists( sPath ) and not fs.isDir( sPath ) then
			return sPath
        elseif fs.exists( sPath..".lua" ) and not fs.isDir( sPath..".lua" ) then
		    return sPath..".lua"
    	end
    end
    
    -- Check shell
    if shell ~= nil then 
        --print("shell", _sTopic, shell.dir())
        return shell.resolveProgram(_sTopic) 
    end

    -- Not found
    return nil
end

local tAPIsLoading = {}
function os.loadAPI( _sPathh )
    if type( _sPathh ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sPathh ) .. ")", 2 ) 
    end

    local _sPath = apilookup( _sPathh )
    if _sPath == nil then error("API not found", 2) end

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
    local tAPI = nil
    setmetatable( tEnv, { __index = _G } )
    local fnAPI, err = loadfile( _sPath, tEnv )
    if fnAPI then
        local ok, err = pcall( fnAPI )
        if not ok then
            --os.debug(err)
            printError( err )
            tAPIsLoading[sName] = nil
            return false
        elseif err ~= nil then
            tAPI = err
        end
    else
        printError( err )
        tAPIsLoading[sName] = nil
        return false
    end
    
    if tAPI == nil then
        tAPI = {}
        for k,v in pairs( tEnv ) do
            if k ~= "_ENV" then
                tAPI[k] =  v
            end
        end
    end

    _G[sName] = tAPI    
    tAPIsLoading[sName] = nil
    return true
end

os.loadAPI("CCOSCrypto")
_G.CCLog = dofile(apilookup("CCLog"))
CCLog.default.logToConsole = true
CCLog.default.consoleLogLevel = CCLog.logLevels.info
local kernelLog = CCLog("CCKernel2")
kernelLog:open()
kernelLog.showInDefaultLog = true

-- Virtual terminals
local vts = {}
local currentVT = 1
local thisVT = 1
i = 1
while i < 9 do
    local w, h = term.getSize()
    vts[i] = window.create(term.native(), 1, 1, w, h, false)
    vts[i].started = false
    if term.setGraphicsMode ~= nil then
        vts[i].graphicsMode = false
        vts[i].pixels = {}
        local w, h = term.getSize()
        for x = 0, w * 6 - 1 do 
            vts[i].pixels[x] = {}
            for y = 0, h * 9 - 1 do vts[i].pixels[x][y] = colors.black end
        end
    end
    i = i + 1
end
vts[currentVT].setVisible(true)
vts[currentVT].started = true

local nativeNative = term.native
local nativeSetGraphics = term.setGraphicsMode
local nativeGetGraphics = term.getGraphicsMode
local nativeSetPixel = term.setPixel
local nativeGetPixel = term.getPixel
function term.native() return vts[thisVT] end
if term.setGraphicsMode ~= nil then
    function term.setGraphicsMode(mode)
        vts[thisVT].graphicsMode = mode
        if thisVT == currentVT then nativeSetGraphics(mode) end
    end
    function term.setPixel(x, y, color)
        vts[thisVT].pixels[x][y] = color
        if thisVT == currentVT then nativeSetPixel(x, y, color) end
    end
    function term.getGraphicsMode() return vts[thisVT].graphicsMode end
    function term.getPixel(x, y) return vts[thisVT].pixels[x][y] end
end

CCLog.default.term = vts[1]

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

kernelLog:info("initializing device files")
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

kernelLog:info("initializing filesystem")
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
local links = {}

function fs.linkDir(from, to)
    if string.sub(from, string.len(from)) == "/" then from = string.sub(from, 1, string.len(from) - 1) end
    if string.sub(to, 1, 1) == "/" then to = string.sub(to, 2) end
    if string.sub(to, string.len(to)) == "/" then to = string.sub(to, 1, string.len(to) - 1) end
    if not fs.isDir(from) then error(from .. ": Directory not found", 2) end
    if fs.getDir(to) ~= "/" and fs.getDir(to) ~= "" and not bit.bmask(fs.getPermissions(fs.getDir(to), getuid()), permissions.write) then error(to .. ": Access denied", 2) end
    if fs.getDir(from) ~= "/" and fs.getDir(from) ~= "" and not bit.bmask(fs.getPermissions(from, getuid()), permissions.read) then error(from .. ": Access denied", 2) end
    local combine = function(path) if string.sub(path, 1, 1) == "/" then return from .. path else return from .. "/" .. path end end
    table.insert(links, to)
    mounts[to] = {
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

local function linkHome()
    local to = "~"
    local combine = function(path) if string.sub(path, 1, 1) == "/" then return users.getHomeDir() .. path else return users.getHomeDir() .. "/" .. path end end
    table.insert(links, to)
    mounts[to] = {
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

function fs.unlinkDir(to) 
    if string.sub(to, 1, 1) == "/" then to = string.sub(to, 2) end
    if string.sub(to, string.len(to)) == "/" then to = string.sub(to, 1, string.len(to) - 1) end
    if not fs.isDir(to) then error(to .. ": Directory not found", 2) end
    if fs.getDir(to) ~= "/" and fs.getDir(to) ~= "" and not bit.bmask(fs.getPermissions(fs.getDir(to), getuid()), permissions.write) then error(to .. ": Access denied", 2) end
    if to ~= "dev" then for k,v in pairs(links) do if v == to then 
        mounts[to] = nil
        table.remove(links, k)
        return
    end end end 
end

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

function orig_fs.getPermissions(path, uid, create)
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
        if create then textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default}}) end
        return default
    end
    if uid == 0 then return default end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms[orig_fs.getName(path)] == nil then 
        if create then
            perms[orig_fs.getName(path)] = {["*"] = default}
            textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
        end
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
    for k,v in pairs(retval) do if v == ".permissions" then 
        table.remove(retval, k)
        break
    end end
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

function fs.getPermissions(path, uid, create)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.getPermissions(p, uid, create)
end

function fs.setPermissions(path, uid, perm)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.setPermissions(p, uid, perm)
end

function fs.addPermissions(path, uid, perm)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.setPermissions(p, uid, bit.bor(m.getPermissions(p, uid), perm))
end

function fs.removePermissions(path, uid, perm)
    local m, p = getMount(path)
    if uid == nil then uid = getuid() end
    return m.setPermissions(p, uid, bit.band(m.getPermissions(p, uid), bit.bnot(perm)))
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
    end
    if fs.getDir(path) ~= "/" and fs.getDir(path) ~= "" and fs.getDir(path) ~= ".." and fs.getDir(path) ~= "/.." and (string.sub(mode, 1, 1) == "w" or string.sub(mode, 1, 1) == "a") and fs.exists(fs.getDir(path) .. "/.permissions") then
        if string.sub(mode, 1, 1) == "w" and not bit.bmask(m.getPermissions(p, getuid(), false), permissions.write) then error(path .. ": Access denied", 2) end
        if string.sub(mode, 1, 1) == "a" and not bit.bmask(m.getPermissions(p, getuid(), false), permissions.write) then error(path .. ": Access denied", 2) end
    end
    return m.open(p, mode)
end

function fs.mount(path, mount)
    if _UID ~= 0 then error("Root permissions required to mount") end
    if type(path) ~= "string" then error("bad argument #1 (expected string, got " .. type(path) .. ")", 2) end
    if type(mount) ~= "table" then error("bad argument #2 (expected table, got " .. type(path) .. ")", 2) end
    for k,v in pairs(devfs) do if mount[k] == nil then error("mount missing function " .. k, 2) end end
    mounts[path] = mount
end

function fs.unmount(path)
    if _UID ~= 0 then error("Root permissions required to unmount") end
    if type(path) ~= "string" then error("bad argument #1 (expected string, got " .. type(path) .. ")", 2) end
    mounts[path] = nil
end

function fs.hasPermissions(path, uid, perm) return bit.bmask(fs.getPermissions(path, uid), perm) end
function fs.mounts() 
    local retval = {}
    for k,v in pairs(mounts) do retval[k] = v end
    return retval
end
--function fs.reset() fs = orig_fs end

fs.linkDir("rom/programs", "bin")
fs.linkDir("rom/apis", "lib")
fs.linkDir("rom/help", "man")

-- Rewrite executor
local orig_loadfile = loadfile
local nativeRun = os.run

local function tokenise( ... )
    local sLine = table.concat( { ... }, " " )
    local tWords = {}
    local bQuoted = false
    for match in string.gmatch( sLine .. "\"", "(.-)\"" ) do
        if bQuoted then
            table.insert( tWords, match )
        else
            for m in string.gmatch( match, "[^ \t]+" ) do
                table.insert( tWords, m )
            end
        end
        bQuoted = not bQuoted
    end
    return tWords
end

_G.loadfile = function( _sFile, _tEnv )
    if type( _sFile ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sFile ) .. ")", 2 ) 
    end
    if _tEnv ~= nil and type( _tEnv ) ~= "table" then
        error( "bad argument #2 (expected table, got " .. type( _tEnv ) .. ")", 2 ) 
    end
    if not fs.hasPermissions( _sFile, nil, fs.permissions.execute ) then return nil, _sFile .. ": Permission denied" end
    local file = fs.open( _sFile, "r" )
    if file then
        local script = file.readAll()
        file.close()
        if string.sub(script, 1, 3) == "--!" then
            local space = string.find(script, " ")
            local enter = string.find(script, "\n")
            local sh = string.sub(script, 4, math.min(space, enter) - 1)
            if sh == _sFile then return nil, "Cannot run recursive script" end
            local args = {}
            if enter > space then args = tokenise(string.sub(script, space + 1, enter - 1)) end
            script = string.sub(script, string.find(script, "\n") + 1)
            return function(...)
                local _args = {}
                for k,v in pairs(args) do table.insert(_args, v) end
                for k,v in pairs({...}) do table.insert(_args, v) end
                local pipe = kernel.popen(sh, "w", _tEnv, table.unpack(_args))
                pipe.write(script .. "\n")
                pipe.close(true)
                local pid = pipe.pid()
                local _, p, s = os.pullEvent("process_complete")
                if p ~= pid then while p ~= pid do 
                    _, p, s = os.pullEvent("process_complete") 
                    if type(p) ~= "number" then 
                        kernel.log:traceback("Failed to run " .. _sPath .. ", PID " .. pid) 
                        error("Failed to run " .. _sPath .. ", PID " .. pid, 3)
                    end
                end end
            end
        end
        local func, err = load( script, fs.getName( _sFile ), "t", _tEnv )
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
    if p ~= pid then while p ~= pid do 
        _, p, s = os.pullEvent("process_complete") 
        if type(p) ~= "number" then 
            kernel.log:traceback("Failed to run " .. _sPath .. ", PID " .. pid) 
            error("Failed to run " .. _sPath .. ", PID " .. pid, 3)
        end
    end end
    return s
end

-- User system
-- Passwords are stored in /etc/passwd as a LTN file with the format {UID = {password = sha256(pass), name = "name"}, ...}
kernelLog:info("initializing user system")
fs.makeDir("/usr")
fs.makeDir("/usr/bin")
fs.makeDir("/usr/share")
fs.makeDir("/usr/share/help")
fs.makeDir("/usr/lib")
fs.makeDir("/usr/modules")
fs.makeDir("/etc")
fs.makeDir("/home")
fs.makeDir("/var/root")
fs.setPermissions("/var/root", 0, fs.permissions.full)
fs.setPermissions("/var/root", "*", fs.permissions.none)
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
    if _G._UID == 0 then return "var/root" end
    local retval = "home/" .. users.getShortName(_G._UID)
    if not fs.exists(retval) then
        fs.makeDir(retval)
        fs.setOwner(retval)
        fs.setPermissions(retval, nil, fs.permissions.full)
        fs.setPermissions(retval, "*", fs.permissions.none)
    end
    return retval
end

linkHome()

function users.create(name, uid)
    if users.getuid() ~= 0 then error("Permission denied", 2) end
    local fl = textutils.unserializeFile("/etc/passwd")
    uid = uid or table.maxn(fl) + 1
    fl[uid] = {name = name}
    textutils.serializeFile("/etc/passwd", fl)
    fs.makeDir("home/" .. name)
    fs.setOwner("home/" .. name, uid)
    fs.setPermissions("home/" .. name, "*", permissions.none)
    fs.setPermissions("home/" .. name, uid, permissions.full)
end

function users.setFullName(name)
    local uid = _UID
    if uid == 0 then return end
    --if users.getuid() ~= 0 and users.getuid() ~= uid then error("Permission denied", 2) end
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
    fs.delete("home/" .. fl[uid].name)
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

-- **Cool** read function (allows linux-style password entry)
local nextReadNil = false
function _G.read( _sReplaceChar, _tHistory, _fnComplete, _sDefault )
    if nextReadNil then
        nextReadNil = false
        return nil
    end
    if _sReplaceChar ~= nil and type( _sReplaceChar ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( _sReplaceChar ) .. ")", 2 ) 
    end
    if _tHistory ~= nil and type( _tHistory ) ~= "table" then
        error( "bad argument #2 (expected table, got " .. type( _tHistory ) .. ")", 2 ) 
    end
    if _fnComplete ~= nil and type( _fnComplete ) ~= "function" then
        error( "bad argument #3 (expected function, got " .. type( _fnComplete ) .. ")", 2 ) 
    end
    if _sDefault ~= nil and type( _sDefault ) ~= "string" then
        error( "bad argument #4 (expected string, got " .. type( _sDefault ) .. ")", 2 ) 
    end
    term.setCursorBlink( true )

    local sDefault
    if type( _sDefault ) == "string" then
        sDefault = _sDefault
    else
        sDefault = ""
    end
    local sLine = sDefault
    local nHistoryPos
    local nPos = #sLine
    if _sReplaceChar then
        _sReplaceChar = string.sub( _sReplaceChar, 1, 1 )
    end

    local tCompletions
    local nCompletion
    local bModifier = false
    local function recomplete()
        if _fnComplete and nPos == string.len(sLine) then
            tCompletions = _fnComplete( sLine )
            if tCompletions and #tCompletions > 0 then
                nCompletion = 1
            else
                nCompletion = nil
            end
        else
            tCompletions = nil
            nCompletion = nil
        end
    end

    local function uncomplete()
        tCompletions = nil
        nCompletion = nil
    end

    local w, h = term.getSize()
    local sx = term.getCursorPos()

    local function redraw( _bClear )
        local nScroll = 0
        if sx + nPos >= w then
            nScroll = (sx + nPos) - w
        end

        local cx,cy = term.getCursorPos()
        term.setCursorPos( sx, cy )
        local sReplace = (_bClear and " ") or _sReplaceChar
        if sReplace ~= "" then
            if sReplace then
                term.write( string.rep( sReplace, math.max( string.len(sLine) - nScroll, 0 ) ) )
            else
                term.write( string.sub( sLine, nScroll + 1 ) )
            end
        end
        if nCompletion then
            local sCompletion = tCompletions[ nCompletion ]
            local oldText, oldBg
            if not _bClear then
                oldText = term.getTextColor()
                oldBg = term.getBackgroundColor()
                term.setTextColor( colors.white )
                term.setBackgroundColor( colors.gray )
            end
            if sReplace then
                term.write( string.rep( sReplace, string.len( sCompletion ) ) )
            else
                term.write( sCompletion )
            end
            if not _bClear then
                term.setTextColor( oldText )
                term.setBackgroundColor( oldBg )
            end
        end

        if sReplace ~= "" then term.setCursorPos( sx + nPos - nScroll, cy ) end
    end
    
    local function clear()
        redraw( true )
    end

    recomplete()
    redraw()

    local function acceptCompletion()
        if nCompletion then
            -- Clear
            clear()

            -- Find the common prefix of all the other suggestions which start with the same letter as the current one
            local sCompletion = tCompletions[ nCompletion ]
            sLine = sLine .. sCompletion
            nPos = string.len( sLine )

            -- Redraw
            recomplete()
            redraw()
        end
    end
    while true do
        local sEvent, param = os.pullEvent()
        if sEvent == "char" then
            -- Typed key
            if bModifier then
                if param == "c" and kernel ~= nil then 
                    print("^C")
                    kernel.kill(_PID, signal.SIGINT)
                elseif param == "d" then
                    nextReadNil = true
                    if nCompletion then
                        clear()
                        uncomplete()
                        redraw()
                    end
                    break
                elseif param == "u" then
                    clear()
                    sLine = sDefault
                    nPos = #sLine
                    recomplete()
                    redraw()
                elseif param == "l" then
                    clear()
                    local cx, cy = term.getCursorPos()
                    term.scroll(cy - 1)
                    term.setCursorPos(cx, 1)
                    recomplete()
                    redraw()
                elseif param == "a" then
                    clear()
                    nPos = 0
                    recomplete()
                    redraw()
                elseif param == "e" then
                    clear()
                    nPos = #sLine
                    recomplete()
                    redraw()
                elseif param == "b" then
                    -- Left
                    if nPos > 0 then
                        clear()
                        nPos = nPos - 1
                        recomplete()
                        redraw()
                    end
                elseif param == "f" then
                    -- Right                
                    if nPos < string.len(sLine) then
                        -- Move right
                        clear()
                        nPos = nPos + 1
                        recomplete()
                        redraw()
                    end
                elseif param == "h" then
                    -- Backspace
                    if nPos > 0 then
                        clear()
                        sLine = string.sub( sLine, 1, nPos - 1 ) .. string.sub( sLine, nPos + 1 )
                        nPos = nPos - 1
                        recomplete()
                        redraw()
                    end
                elseif param == "w" then
                    if string.find(sLine, " ") ~= nil then
                        clear()
                        local lastSpace = string.find(sLine, " ")
                        while string.find(sLine, " ", lastSpace + 1) ~= nil do lastSpace = string.find(sLine, " ", lastSpace + 1) end
                        sLine = string.sub( sLine, 1, lastSpace - 1 )
                        nPos = #sLine
                        recomplete()
                        redraw()
                    end
                end
            else
                clear()
                sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
                nPos = nPos + 1
                recomplete()
                redraw()
            end

        elseif sEvent == "paste" then
            -- Pasted text
            clear()
            sLine = string.sub( sLine, 1, nPos ) .. param .. string.sub( sLine, nPos + 1 )
            nPos = nPos + string.len( param )
            recomplete()
            redraw()

        elseif sEvent == "key_up" and param == keys.leftCtrl then
            bModifier = false

        elseif sEvent == "key" then
            if param == keys.enter then
                -- Enter
                if nCompletion then
                    clear()
                    uncomplete()
                    redraw()
                end
                break
                
            elseif param == keys.left then
                -- Left
                if nPos > 0 then
                    clear()
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end
                
            elseif param == keys.right then
                -- Right                
                if nPos < string.len(sLine) then
                    -- Move right
                    clear()
                    nPos = nPos + 1
                    recomplete()
                    redraw()
                else
                    -- Accept autocomplete
                    acceptCompletion()
                end

            elseif param == keys.up or param == keys.down then
                -- Up or down
                if nCompletion then
                    -- Cycle completions
                    clear()
                    if param == keys.up then
                        nCompletion = nCompletion - 1
                        if nCompletion < 1 then
                            nCompletion = #tCompletions
                        end
                    elseif param == keys.down then
                        nCompletion = nCompletion + 1
                        if nCompletion > #tCompletions then
                            nCompletion = 1
                        end
                    end
                    redraw()

                elseif _tHistory then
                    -- Cycle history
                    clear()
                    if param == keys.up then
                        -- Up
                        if nHistoryPos == nil then
                            if #_tHistory > 0 then
                                nHistoryPos = #_tHistory
                            end
                        elseif nHistoryPos > 1 then
                            nHistoryPos = nHistoryPos - 1
                        end
                    else
                        -- Down
                        if nHistoryPos == #_tHistory then
                            nHistoryPos = nil
                        elseif nHistoryPos ~= nil then
                            nHistoryPos = nHistoryPos + 1
                        end                        
                    end
                    if nHistoryPos then
                        sLine = _tHistory[nHistoryPos]
                        nPos = string.len( sLine ) 
                    else
                        sLine = ""
                        nPos = 0
                    end
                    uncomplete()
                    redraw()

                end

            elseif param == keys.backspace then
                -- Backspace
                if nPos > 0 then
                    clear()
                    sLine = string.sub( sLine, 1, nPos - 1 ) .. string.sub( sLine, nPos + 1 )
                    nPos = nPos - 1
                    recomplete()
                    redraw()
                end

            elseif param == keys.home then
                -- Home
                if nPos > 0 then
                    clear()
                    nPos = 0
                    recomplete()
                    redraw()
                end

            elseif param == keys.delete then
                -- Delete
                if nPos < string.len(sLine) then
                    clear()
                    sLine = string.sub( sLine, 1, nPos ) .. string.sub( sLine, nPos + 2 )                
                    recomplete()
                    redraw()
                end

            elseif param == keys["end"] then
                -- End
                if nPos < string.len(sLine ) then
                    clear()
                    nPos = string.len(sLine)
                    recomplete()
                    redraw()
                end

            elseif param == keys.tab then
                -- Tab (accept autocomplete)
                acceptCompletion()

            elseif param == keys.leftCtrl then
                bModifier = true

            end

        elseif sEvent == "term_resize" then
            -- Terminal resized
            w = term.getSize()
            redraw()

        end
    end

    local cx, cy = term.getCursorPos()
    term.setCursorBlink( false )
    term.setCursorPos( w + 1, cy )
    print()
    
    return sLine
end

-- Better serialize function
local g_tLuaKeywords = {
    [ "and" ] = true,
    [ "break" ] = true,
    [ "do" ] = true,
    [ "else" ] = true,
    [ "elseif" ] = true,
    [ "end" ] = true,
    [ "false" ] = true,
    [ "for" ] = true,
    [ "function" ] = true,
    [ "if" ] = true,
    [ "in" ] = true,
    [ "local" ] = true,
    [ "nil" ] = true,
    [ "not" ] = true,
    [ "or" ] = true,
    [ "repeat" ] = true,
    [ "return" ] = true,
    [ "then" ] = true,
    [ "true" ] = true,
    [ "until" ] = true,
    [ "while" ] = true,
}

local function serializeImpl( t, tTracking, sIndent )
    local sType = type(t)
    if sType == "table" then
        if tTracking[t] ~= nil then
            return "recursive"
        end
        tTracking[t] = true

        if next(t) == nil then
            -- Empty tables are simple
            return "{}"
        else
            -- Other tables take more work
            local sResult = "{\n"
            local sSubIndent = sIndent .. "  "
            local tSeen = {}
            for k,v in ipairs(t) do
                tSeen[k] = true
                sResult = sResult .. sSubIndent .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
            end
            for k,v in pairs(t) do
                if not tSeen[k] then
                    local sEntry
                    if type(k) == "string" and not g_tLuaKeywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
                        sEntry = k .. " = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
                    else
                        sEntry = "[ " .. serializeImpl( k, tTracking, sSubIndent ) .. " ] = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
                    end
                    sResult = sResult .. sSubIndent .. sEntry
                end
            end
            sResult = sResult .. sIndent .. "}"
            return sResult
        end
        
    elseif sType == "string" then
        return string.format( "%q", t )
    
    elseif sType == "number" or sType == "boolean" or sType == "nil" then
        return tostring(t)
        
    else
        return "unserializable"
        
    end
end

function textutils.serialize( t )
    local tTracking = {}
    return serializeImpl( t, tTracking, "" )
end

-- Actual kernel runtime
kernelLog:info("initializing kernel calls")
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

function hasFunction(val)
    if type(val) == "function" then return true
    elseif type(val) == "table" then for k,v in pairs(val) do if hasFunction(v) then return true end end end
    return false
end

local process_table = {}
local nativeQueueEvent = os.queueEvent
local nativePullEvent = os.pullEvent
local pidenv = {}
local eventFunctions = {}
function os.queueEvent(ev, ...) 
    local ef = {}
    if eventFunctions[_G._PID] == nil then eventFunctions[_G._PID] = {} end
    if eventFunctions[_G._PID][ev] == nil then eventFunctions[_G._PID][ev] = {} end
    if table.pack(...).n > 0 then for k,v in pairs({...}) do if hasFunction(v) then ef[k+2] = v end end end
    table.insert(eventFunctions[_G._PID][ev], ef)
    nativeQueueEvent(ev, "CustomEvent,PID=" .. _G._PID, ...) 
end
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
        os.queueEvent("kcall_fork_process", func, name, ...)
    else os.queueEvent("kcall_fork_process", func, name, env, ...) end 
    local _, pid = os.pullEvent("process_started")
    return pid
end
function kernel.kill(pid, sig) os.queueEvent(signal.getName(sig), pid) end
function kernel.signal(sig, handler) os.queueEvent("kcall_signal_handler", sig, handler) end
function kernel.send(pid, ev, ...) 
    if pid == nil then error("PID must be set", 2) end
    local ef = {}
    if eventFunctions[pid] == nil then eventFunctions[pid] = {} end
    if eventFunctions[pid][ev] == nil then eventFunctions[pid][ev] = {} end
    if table.pack(...).n > 0 then for k,v in pairs({...}) do if hasFunction(v) then ef[k+1] = v end end end
    table.insert(eventFunctions[pid][ev], ef)
    nativeQueueEvent(ev, "CustomEvent,PID=" .. pid, ...) 
end
function kernel.broadcast(ev, ...) kernel.send(0, ev, ...) end
function kernel.getPID() return _G._PID end
function kernel.chvt(id) os.queueEvent("kcall_change_vt", id) end
function kernel.getvt() return currentVT end
function kernel.getArgs() return kernel_args end
function kernel.setProcessProperty(pid, k, v)
    if process_table[pid].parent == _PID or process_table[_PID].user == 0 and k ~= "parent" and k ~= "coro" and k ~= "started" then process_table[pid][k] = v end
end
function kernel.getProcessProperty(pid, k)
    if process_table[pid].parent == _PID or process_table[_PID].user == 0 then return process_table[pid][k] end
end
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

-- I/O piping
function createPipeTerminal()
    local retval = {}
    retval.screen = {}
    retval.width, retval.height = term.getSize()
    retval.cursorX = 1
    retval.cursorY = 1
    retval.screenOffset = 0
    retval.readOffset = 0
    function retval.write(text)
        if retval.cursorX >= retval.width then return end
        retval.screen[retval.screenOffset + retval.cursorY][retval.cursorX] = string.sub(text, 1, 1)
        retval.cursorX = retval.cursorX + 1
        if string.len(text) > 1 then retval.write(string.sub(text, 2)) end
    end
    retval.blit = retval.write
    function retval.clear() 
        local y = retval.screenOffset + 1
        while y <= retval.screenOffset + retval.height do
            retval.screen[y] = {}
            local x = 1
            while x <= retval.width do
                retval.screen[y][x] = " "
                x=x+1
            end
            y=y+1
        end
    end
    function retval.clearLine() 
        retval.screen[retval.screenOffset + retval.cursorY] = {}
        local x = 1
        while x <= retval.height do
            retval.screen[retval.screenOffset + retval.cursorY][x] = " "
            x=x+1
        end
    end
    function retval.getCursorPos() return retval.cursorX, retval.cursorY end
    function retval.setCursorPos(x, y)
        retval.cursorX = x
        retval.cursorY = y
    end
    function retval.setCursorBlink() end
    function retval.isColor() return false end
    function retval.getSize() return retval.width, retval.height end
    function retval.scroll(lines) 
        local y = retval.screenOffset + retval.height
        while y <= retval.screenOffset + retval.height + lines do
            retval.cursorY = y - retval.screenOffset
            retval.clearLine()
            y=y+1
        end
        retval.screenOffset = retval.screenOffset + lines
    end
    function retval.setTextColor() end
    function retval.getTextColor() return colors.white end
    function retval.setBackgroundColor() end
    function retval.getBackgroundColor() return colors.black end
    function retval.setPaletteColor() end
    function retval.getPaletteColor() return 0, 0, 0 end
    retval.clear()
    return retval
end

local function trim11(s)
    local n = s:find"%S"
    return n and s:match(".*%S", n) or ""
end

pipes = {}
pipefd = {}
function kernel.popen(path, mode, env, ...) 
    if type(env) == "table" then 
        pidenv[_G._PID] = env
        os.queueEvent("kcall_open_pipe", path, mode, ...)
    else os.queueEvent("kcall_open_pipe", path, mode, env, ...) end
    local _, pid = os.pullEvent("process_started")
    return pipefd[pid]
end

function kernel.isPiped() return pipes[_PID] ~= nil end
function kernel.isOutputPiped() return pipes[_PID] ~= nil and pipes[_PID].read ~= nil end
function kernel.isInputPiped() return pipes[_PID] ~= nil and pipes[_PID].write ~= nil end

local orig_read = read
function _G.read(...)
    if pipes[_PID] == nil or pipes[_PID].write == nil then return orig_read(...) else
        while string.len(pipes[_PID].write) == 0 do 
            if not pipes[_PID].opened then return nil end
            os.pullEvent() 
        end
        local retval = pipes[_PID].write
        pipes[_PID].write = ""
        return retval
    end
end

function os.pullEvent( sFilter )
    local eventData = table.pack( os.pullEventRaw( sFilter ) )
    local ev = eventData[1]
    if ev == "terminate" then
        error( "Terminated", 0 )
    end
    if eventFunctions[_G._PID] ~= nil and eventFunctions[_G._PID][ev] ~= nil and #eventFunctions[_G._PID][ev] > 0 then
        local ef = table.remove(eventFunctions[_G._PID][ev], 1)
        --print(textutils.serialize(ef))
        for k,v in pairs(eventData) do if ef[k] ~= nil and k > 1 then eventData[k] = ef[k] end end
    end
    return table.unpack( eventData, 1, eventData.n )
end

local firstProgram = shell.resolveProgram("init")
local loginProgram = shell.resolveProgram("login")
if singleUserMode then loginProgram = "/rom/programs/shell.lua" end

fs.setPermissions(firstProgram, "*", bit.bor(fs.permissions.setuid, fs.permissions.read_execute))
fs.setOwner(firstProgram, 0)

local oldPath = shell.path()
local kernel_running = true
--if shell ~= nil then shell.setPath(oldPath .. ":/" .. CCKitGlobals.CCKitDir .. "/ktools") end
table.insert(process_table, {coro=coroutine.create(nativeRun), path=firstProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=1, loggedin=false, env=_ENV, term=vts[1], main=true})
local orig_shell = shell
kernel.log:info("starting init program")
local function killProcess(pid)
    local oldparent = process_table[pid].parent
    process_table[pid] = nil
    pipes[pid] = nil
    pipefd[pid] = nil
    if oldparent ~= nil then kernel.send(oldparent, "process_complete", pid, false) end
    local restart = true
    while restart do
        restart = false
        for k,v in pairs(process_table) do if v.parent == pid then 
            killProcess(k) 
            restart = true
            break
        end end
    end
end
local modifiers = 0
while kernel_running do
    if not vts[currentVT].started and process_table[1] ~= nil then 
        local pid = table.maxn(process_table) + 1
        table.insert(process_table, pid, {coro=coroutine.create(nativeRun), path=loginProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=currentVT, parent=0, loggedin=false, env=_ENV, term=vts[currentVT], main=true}) 
        vts[currentVT].started = true
    end
    local e = {os.pullEvent()}
    if process_table[1] == nil then
        --log:log("First process stopped, ending CCKernel")
        print("Press enter to continue.")
        read()
        kernel_running = false
        e = {"kernel_stop"}
    end
    if e[1] == "key" and keys.getName(e[2]) ~= nil then
        if string.find(keys.getName(e[2]), "f%d+") == 1 and bit.band(modifiers, 3) == 3 then
            local num = tonumber(string.sub(keys.getName(e[2]), 2))
            if num >= 1 and num <= 8 then
                vts[currentVT].setVisible(false)
                term.clear()
                vts[num].setVisible(true)
                currentVT = num
                if not vts[num].started then 
                    local pid = table.maxn(process_table) + 1
                    table.insert(process_table, pid, {coro=coroutine.create(nativeRun), path=loginProgram, started=false, filter=nil, args={...}, signals={}, user=0, vt=num, loggedin=false, parent=0, env=_ENV, term=vts[num], main=true}) 
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
        elseif e[2] == keys.c then
            -- kill
        elseif e[2] == keys.leftCtrl then
            modifiers = bit.bor(modifiers, 1)
        elseif e[2] == keys.leftAlt then
            modifiers = bit.bor(modifiers, 2)
        elseif e[2] == keys.leftShift then
            modifiers = bit.bor(modifiers, 4)
        end
    elseif e[1] == "key_up" and keys.getName(e[2]) ~= nil then
        if e[2] == keys.leftCtrl then
            modifiers = bit.band(modifiers, bit.bnot(1))
        elseif e[2] == keys.leftAlt then
            modifiers = bit.band(modifiers, bit.bnot(2))
        elseif e[2] == keys.leftShift then
            modifiers = bit.band(modifiers, bit.bnot(4))
        end
    end
    local PID = 0
    if type(e[2]) == "string" and string.find(e[2], "CustomEvent,PID=") ~= nil then
        PID = tonumber(string.sub(e[2], string.len("CustomEvent,PID=")+1))
        --print("Sending " .. e[1] .. " to " .. tostring(PID))
        table.remove(e, 2)
    end
    if eventFunctions[PID] ~= nil and eventFunctions[PID][e[1]] ~= nil and #eventFunctions[PID][e[1]] > 0 then
        local ef = table.remove(eventFunctions[PID][e[1]], 1)
        --print(textutils.serialize(ef))
        for k,v in pairs(e) do if k > 1 and ef[k] ~= nil then e[k] = ef[k] end end
    end
    if e[1] == "kcall_get_process_table" then
        e[2] = deepcopy(process_table)
        e[2][0] = {coro=nil, path=myself, started=true, filter=nil, stopped=false, args={}, signals={}, user=0, vt=0, loggedin=false, parent=0, term=nativeNative(), main=true}
    elseif e[1] == "kcall_login_changed" and process_table[PID].user == 0 then
        process_table[PID].loggedin = e[2]
        if not e[2] then vts[process_table[PID].vt].started = false end
    end
    if signal[e[1]] ~= nil then
        local sig = signal[e[1]]
        local pid = e[2]
        if process_table[pid] ~= nil then
            if sig == signal.SIGKILL and process_table[PID].user == 0 then
                killProcess(pid)
                local c = term.getTextColor()
                term.setTextColor(colors.red)
                print("Killed")
                term.setTextColor(c)
            elseif sig == signal.SIGINT then
                local continue = true
                if process_table[pid].signals[signal.SIGINT] ~= nil then continue = process_table[pid].signals[signal.SIGINT](signal.SIGINT) end
                if continue then killProcess(pid) end
            elseif sig == signal.SIGSTOP then
                process_table[pid].stopped = true
                vts[currentVT].write("Stopped")
            elseif sig == signal.SIGCONT then
                process_table[pid].stopped = false
                vts[currentVT].write("Continuing")
            elseif (sig == signal.SIGBUS or sig == signal.SIGFPE or sig == signal.SIGILL or sig == signal.SIGIO or sig == signal.SIGPIPE or sig == signal.SIGSEGV or sig == signal.SIGTERM or sig == signal.SIGTRAP) then
                if process_table[pid].signals[sig] ~= nil then process_table[pid].signals[sig](sig) end
                killProcess(pid)
            elseif process_table[pid].signals[sig] ~= nil then process_table[pid].signals[sig](sig) end
        end
    elseif e[1] == "kcall_start_process" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local env = pidenv[PID]
        local pid = table.maxn(process_table) + 1
        table.insert(process_table, pid, {coro=coroutine.create(nativeRun), path=path, started=false, stopped=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user, vt=process_table[PID].vt, loggedin=process_table[PID].loggedin, parent=PID, term=vts[process_table[PID].vt], main=false})
        pidenv[PID] = nil
        kernel.send(PID, "process_started", pid)
    elseif e[1] == "kcall_fork_process" then
        table.remove(e, 1)
        local func = table.remove(e, 1)
        local name = table.remove(e, 1) or "anonymous"
        local pid = table.maxn(process_table) + 1
        kernel.log:debug(name)
        if func == nil then kernel.log:debug("Func is nil") end
        local env = pidenv[PID]
        if process_table[PID] == nil then error("Parent doesn't exist! " .. PID) end
        table.insert(process_table, pid, {coro=coroutine.create(func), path="["..name.."]", started=false, stopped=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user, vt=process_table[PID].vt, loggedin=process_table[PID].loggedin, parent=PID, term=vts[process_table[PID].vt], main=false})
        kernel.send(PID, "process_started", pid)
    elseif e[1] == "kcall_open_pipe" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local mode = table.remove(e, 1)
        local env = pidenv[PID]
        local pid = table.maxn(process_table) + 1
        table.insert(process_table, pid, {coro=coroutine.create(nativeRun), path=path, started=false, stopped=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user, vt=process_table[PID].vt, loggedin=process_table[PID].loggedin, parent=PID, term=vts[process_table[PID].vt], main=false})
        local retval = {}
        pipes[pid] = {opened=true}
        function retval.close(continue)
            pipes[pid].opened = false
            if not continue then
                kernel.kill(pid, signal.SIGINT)
                pipes[pid] = nil
            end
        end
        function retval.is_open() return pipes[pid] and pipes[pid].opened end
        function retval.pid() return pid end
        if string.find(mode, "r") ~= nil then
            pipes[pid].read = createPipeTerminal()
            process_table[pid].term = pipes[pid].read
            retval.readLine = function()
                if not pipes[pid].opened then return nil end
                if pipes[pid].read.readOffset >= pipes[pid].read.screenOffset + pipes[pid].read.height then return nil end
                local retval = trim11(table.concat(pipes[pid].read.screen[pipes[pid].read.readOffset + 1]))
                if retval == "" then return nil end
                pipes[pid].read.readOffset = pipes[pid].read.readOffset + 1
                return retval
            end
            retval.readAll = function()
                if not pipes[pid].opened then return nil end
                local retvalt = ""
                local line = retval.readLine()
                while line ~= nil and line ~= "" do
                    retvalt = retvalt .. line .. "\n"
                    line = retval.readLine()
                end
                if retvalt == "" then return nil
                else return retvalt end
            end
        end
        if string.find(mode, "w") ~= nil then
            pipes[pid].write = ""
            retval.write = function(d) 
                if pipes[pid].opened then pipes[pid].write = pipes[pid].write .. d end
            end
            retval.writeLine = function(d) 
                if pipes[pid].opened then pipes[pid].write = pipes[pid].write .. d .. "\n" end
            end
        end
        pipefd[pid] = retval
        kernel.send(PID, "process_started", pid)
    elseif e[1] == "kcall_signal_handler" then
        process_table[PID].signals[e[1]] = e[2]
    elseif e[1] == "kcall_change_vt" then
        if e[2] > 0 and e[2] <= 8 then
            vts[currentVT].setVisible(false)
            term.clear()
            vts[e[2]].setVisible(true)
            if term.setGraphicsMode ~= nil then
                nativeSetGraphics(vts[e[2]].graphicsMode)
                local w, h = term.getSize()
                for x = 0, w * 6 - 1 do for y = 0, h * 9 - 1 do nativeSetPixel(x, y, vts[e[2]].pixels[x][y]) end end
            end
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
                        thisVT = v.vt
                        term.redirect(v.term)
                        err, res = coroutine.resume(v.coro, unpack(e))
                        v.term = term.current()
                        term.redirect(nativeNative())
                        thisVT = 1
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
                    thisVT = v.vt
                    term.redirect(v.term)
                    if v.env == nil then v.env = {} end
                    err, res = coroutine.resume(v.coro, v.env, v.path, unpack(v.args))
                    v.term = term.current()
                    term.redirect(nativeNative())
                    thisVT = 1
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
        for k,v in pairs(delete) do 
            if process_table[v.f] and process_table[v.f].main then vts[process_table[v.f].vt].started = false end
            killProcess(v.f)
        end
        --if not loggedin then break end
    end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
kernelLog:close()
os.run = nativeRun
os.queueEvent = nativeQueueEvent
os.pullEvent = nativePullEvent
term.native = nativeNative
term.setGraphicsMode = nativeSetGraphics
term.getGraphicsMode = nativeGetGraphics
term.setPixel = nativeSetPixel
term.getPixel = nativeGetPixel
error = orig_error

_G.fs = orig_fs
_G.loadfile = orig_loadfile
_G.read = orig_read
_G._PID = nil
_G._UID = nil
_G.kernel = nil
_G.users = nil
_G.signals = nil
currentVT = nil
if shell ~= nil then shell.setPath(oldPath) end

end, ...)

if not ok then
    term.redirect(nativeTerminal)
    printError("\nkernel panic at " .. err .. "\n\nA critical error has occurred in CCKernel2, and the computer was left in an unstable state. CraftOS must restart to recover functionality. Press any key to reboot.")
    coroutine.yield()
    coroutine.yield("key")
    nativeReboot()
end