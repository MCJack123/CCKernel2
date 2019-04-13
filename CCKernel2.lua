--[[ 
CCKernel 2
Features: multiprocessing, IPC, permissions, signaling, virtual terminals, file descriptors, debugging, multiple users, filesystem reorganization, I/O operations

* For multiprocessing, we need a run loop that executes coroutines in a table one by one.
* For IPC, we need to pull events sent from each coroutine into the run loop. Then we need to check the PID, name, etc. and resend the events into the parallel coroutines.
* [check] For permissions, we need to rewrite the fs API to do virtual permission checks before opening the file. Storing permissions may have to be inside a hidden file at the root directory, storing the bits for permissions for each file.
* For signaling, we need IPC + checking the events sent for specific signals. If the name matches, then we either a) do what the signal means (SIGKILL, SIGTERM, SIGSTOP, etc.), or b) relay the signal into the program.
* For virtual terminals, we need to have multiple copies of the term API that can be switched as needed.
* [check] For file descriptors, we need to catch opening these files in the fs API, and return the respective file handle for the file descriptor. Possible descriptors:
  * /dev/random: file.read() returns math.random(0, 255)
  * /dev/zero: file.read() returns 0
  * /dev/null: file.write() does nothing
  * /dev/stdout: file.write() writes a character to the terminal
  * /dev/stdin: file.read() returns the next character in the input or 0
  * /dev/fifo[0-9]: FIFO (first in, first out) files
* For debugging, we need to have a debug entrypoint in the kernel that the processes can call on an error. Unfortunately, we cannot catch errors outside of coroutines, so enabling debugging support in a program will be the task of the programmer. (We'll probably just run rom/programs/lua.lua with the coroutine environment.)
  * Actually, if the coroutine environment is not copied on execution, it may be possible to examine the environment outside of the program. Catching errors outside and resuming will not be possible, but stepping through to each os.pullEvent() may be possible.
* [check] For multiple users, we need to implement a custom runtime for each coroutine. (We'll figure this out as we go.)
* [check] For filesystem reorganization, we just need to remap the files in /rom to /bin, /lib, /share, /etc, etc. inside the fs API. /rom will still be accessible.
* For I/O operations, we need to rewrite term.write() and read() to use piped data first, then use the normal I/O data. Each process will need to be aware of where it's being piped to.

This will be quite complicated and will fundamentally reshape CraftOS, but it will give so many new features to CraftOS at its base. I'm hoping to keep this as compatible with base CraftOS as possible, retaining support for all (most) programs. 
]]--

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

local function get_permissions(perms, uid)
    if uid == 0 then return permissions.full end
    if perms[uid] ~= nil then return perms[uid]
    elseif perms["*"] ~= nil then return perms["*"]
    else return default_permissions end
end

local function bmask(a, m) return bit.band(a, m) == m end
local function has_permission(perms, uid, p) return bmask(get_permissions(perms, uid), p) end

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

local orig_fs = fs
fs = {}

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
    if orig_fs.getDrive(path) == "rom" then return permissions.read end
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
    if type(perm) ~= "number" or perm < 0 or perm > 15 then error("bad argument #3 (number expected, got " .. type(path) .. ")", 3) end
    if not orig_fs.exists(path) then error(path .. ": No such file", 3) end
    if orig_fs.getDrive(path) == "rom" then error(path .. ": Access denied", 3) end
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions")
    if perms.owner ~= nil and perms.owner ~= uid then error(path .. ": Access denied", 3) end
    perms[orig_fs.getName(path)][uid] = perm
    textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
end

function orig_fs.getOwner(path)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if orig_fs.getDrive(path) == "rom" then return -1 end
    if not orig_fs.exists(path) then return nil end
    local default = orig_fs.isReadOnly(path) and permissions.read or permissions.full
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", {[orig_fs.getName(path)] = {["*"] = default}})
        return
    end
    local perms = textutils.unserializeFile({[orig_fs.getName(path)] = {["*"] = default}})
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
    local perms = textutils.unserializeFile(orig_fs.getDir(path) .. "/.permissions", file.readAll())
    if perms.owner ~= nil and perms.owner ~= uid then error(path .. ": Access denied", 3) end
    perms[orig_fs.getName(path)].owner = uid
    textutils.serializeFile(orig_fs.getDir(path) .. "/.permissions", perms)
end

function fs.list(path)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
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
    return not bmask(m.getPermissions(p, getuid()), permissions.write)
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
    if uid == nil then uid = getuid() end
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
    if not bmask(m.getPermissions(fs.getDir(p), getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    m.makeDir(p)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    inperms[fs.getName(path)] = {["*"] = default_permissions}
    textutils.serializeFile(fs.getDir(path) .. "/.permissions", inperms)
end

function fs.move(path, toPath)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.delete) or not bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if not bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
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
    if not bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if not bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
    m.copy(p, toPath)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    local outperms = textutils.unserializeFile(fs.getDir(toPath) .. "/.permissions")
    outperms[fs.getName(toPath)] = inperms[fs.getName(path)]
    textutils.serializeFile(fs.getDir(toPath) .. "/.permissions", outperms)
end

function fs.delete(path)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.delete) then error(path .. ": Access denied", 2) end
    m.delete(p)
    local inperms = textutils.unserializeFile(fs.getDir(path) .. "/.permissions")
    inperms[fs.getName(path)] = nil
    textutils.serializeFile(fs.getDir(path) .. "/.permissions", inperms)
end

function fs.open(path, mode)
    local m, p = getMount(path)
    if string.sub(mode, 1, 1) == "r" and not bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if string.sub(mode, 1, 1) == "w" and not bmask(m.getPermissions(p, getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    if string.sub(mode, 1, 1) == "a" and not bmask(m.getPermissions(p, getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    return m.open(p, mode)
end

function fs.mount(path, mount)
    if type(path) ~= "string" then error("bad argument #1 (expected string, got " .. type(path) .. ")", 2) end
    if type(mount) ~= "table" then error("bad argument #2 (expected table, got " .. type(path) .. ")", 2) end
    for k,v in pairs(devfs) do if mount[k] == nil then error("mount missing function " .. k, 2) end end
    mounts[path] = mount
end

function fs.hasPermissions(path, uid, perm) return bmask(fs.getPermissions(path, uid), perm) end

function fs.mounts() return mounts end

-- Rewrite executor
loadfile = function( _sFile, _tEnv )
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
        if fs.hasPermissions( _sFile, nil, fs.permissions.setuid ) then 
            return function( ... )
                _G._SETUID = _G._UID
                _G._UID = fs.getOwner( _sFile )
                local ok, err = pcall(function() func( ... ) end)
                _G._UID = _G._SETUID
            end
        else return func, err end
    end
    return nil, "File not found"
end

-- User system
os.loadAPI(shell.resolve("CCOSCrypto.lua"))

-- Passwords are stored in /etc/passwd as a LON file with the format {UID = {password = sha256(pass), name = "name"}, ...}
function setuid(uid) if _G._UID ~= 0 or uid == -1 then return true else _G._UID = uid end end
function getuid() return _G._UID end

fs.makeDir("/etc")
fs.makeDir("/home")
if not fs.exists("/etc/passwd") then
    textutils.serializeFile("/etc/passwd", {
        [-1] = {name = "superroot", fullName = "API Runtime User", password = nil},
        [0] = {name = "root", fullName = "Superuser", password = nil}
    })
end

users = {}

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
    for k,v in pairs(name) do if v.name == name then return k end end
    return nil
end

function users.getUIDFromFullName(name)
    local fl = textutils.unserializeFile("/etc/passwd")
    for k,v in pairs(name) do if v.name == name then return k end end
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

-- Kernel process wrapper
local function wrapCoroFunction(func) return function(...)

end end

-- Debugger in error function
local orig_error = error
os.debug_enabled = false
error = function(message, level)
    if os.debug_enabled then 
        printError("Error caught: ", message)
        os.run(_ENV, "/rom/programs/lua.lua")
    end
    orig_error(message, level)
end

-- Actual kernel runtime
kernel = {}
signal = {}
signal = {
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
    getName = function(sig) for k,v in signal do if sig == v then return k end end end
}

local process_table = {}
local nativeQueueEvent = os.queueEvent
function kernel.exec(path, ...) os.queueEvent("kcall_start_process", path, ...) end
function kernel.fork(func, ...) os.queueEvent("kcall_fork_process", func, ...) end
function kernel.kill(pid, sig) os.queueEvent(signal.getName(sig), pid) end
function kernel.signal(sig, handler) os.queueEvent("kcall_signal_handler", sig, handler) end
function kernel.send(pid, ev, ...) nativeQueueEvent(ev, "CustomEvent,PID="..tostring(pid), ...) end
function kernel.broadcast(ev, ...) kernel.send(0, ev, ...) end
function kernel.getPID() return _G._PID end

function kernel.getProcesses()
    os.queueEvent("kcall_get_process_table")
    local ev, t = os.pullEvent("kcall_get_process_table")
    return t
end

function os.queueEvent(ev, ...)
    nativeQueueEvent(ev, "CustomEvent,PID=" .. _G._PID, ...)
end
local oldPath = shell.path()
--if shell ~= nil then shell.setPath(oldPath .. ":/" .. CCKitGlobals.CCKitDir .. "/ktools") end
table.insert(process_table, {coro=coroutine.create(os.run), path=shell.resolveProgram("login"), started=false, filter=nil, args={...}, signals={}, user=0})
term.clear()
term.setCursorPos(1, 1)
while kernel_running do
    if process_table[1] == nil or process_table[1].path ~= first_program then
        --log:log("First process stopped, ending CCKernel")
        --print("Press any key to continue.")
        kernel_running = false
    end
    local e = {os.pullEvent()}
    if e[1] == "key" and e[2] == keys.f12 then
        _G._PID = nil
        print("Kernel paused.")
        _ENV.kill_kernel=function() 
            nativeQueueEvent("kcall_kill_process", 0)
            getfenv(2).exit()
        end
        print("Entering debugger.")
        os.run(_ENV, "/rom/programs/lua.lua")
        print("Resuming.")
    end
    local PID = 0
    if type(e[2]) == "string" and string.find(e[2], "CustomEvent,PID=") ~= nil then
        PID = tonumber(string.sub(e[2], string.len("CustomEvent,PID=")+1))
        --print("Sending " .. e[1] .. " to " .. tostring(PID))
        table.remove(e, 2)
    end
    if e[1] == "kcall_get_process_table" then
        e[2] = deepcopy(process_table)
        e[2][0] = {coro=nil, path=shell.getRunningProgram(), started=true, filter=nil, args={}, signals={}, user=0}
    end
    if signal[e[1]] ~= nil then
        local sig = signal[e[1]]
        local pid = e[2]
        if sig == signal.SIGKILL and process_table[PID].user == 0 then
            if pid == 0 then break end
            table.remove(process_table, pid)
            local c = term.getTextColor()
            term.setTextColor(colors.red)
            print("Killed")
            term.setTextColor(c)
        elseif sig == signal.SIGTERM and process_table[PID].user == 0 then
            if pid == 0 then break end
            if process_table[pid].signals[signal.SIGTERM] ~= nil then process_table[pid].signals[signal.SIGTERM](signal.SIGTERM) end
            table.remove(process_table, pid)
        elseif sig == signal.SIGINT and pid ~= 0 then
            local continue = true
            if process_table[pid].signals[signal.SIGINT] ~= nil then continue = process_table[pid].signals[signal.SIGINT](signal.SIGINT) end
            if continue then table.remove(process_table, e[2]) end
        end
    elseif e[1] == "kcall_start_process" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local env = {}
        if type(e[1]) == "table" then env = table.remove(e, 1) end
        table.insert(process_table, {coro=coroutine.create(os.run), path=path, started=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user})
    elseif e[1] == "kcall_fork_process" then
        table.remove(e, 1)
        local func = table.remove(e, 1)
        local env = {}
        local path = table.remove(e, 1)
        if type(e[1]) == "table" then env = table.remove(e, 1) end
        table.insert(process_table, {coro=coroutine.create(func), path=path, started=false, filter=nil, args=e, env=env, signals={}, user=process_table[PID].user})
    elseif e[1] == "kcall_signal_handler" then
        process_table[PID].signals[e[1]] = e[2]
    else
        local delete = {}
        for k,v in pairs(process_table) do
            if v.filter == nil or v.filter == e[1] then
                local err = true
                local res = nil
                if v.started then
                    if PID == 0 or PID == k then
                        _G._PID = k
                        _G._FORK = false
                        _G._UID = v.user
                        if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = n end end
                        err, res = coroutine.resume(v.coro, unpack(e))
                        if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = nil end end
                        v.user = _G._UID
                    end
                else
                    _G._PID = k
                    _G._FORK = true -- only check this before first yield
                    _G._UID = v.user
                    if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = n end end
                    err, res = coroutine.resume(v.coro, _ENV, v.path, unpack(v.args))
                    if v.env ~= nil then for r,n in pairs(v.env) do _G[r] = nil end end
                    v.started = true
                    v.user = _G._UID
                end
                if not err then
                    log:error("Process couldn't resume or threw an error", basename(v.path), k)
                    table.insert(delete, k)
                end
                if coroutine.status(v.coro) == "dead" then table.insert(delete, k) end
                if res ~= nil then v.filter = res else v.filter = nil end -- assuming every yield is for pullEvent, this may be unsafe
            end
        end
        for k,v in pairs(delete) do table.remove(process_table, v) end
    end
end
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
os.queueEvent = nativeQueueEvent
error = orig_error
fs = orig_fs
_G._PID = nil
if shell ~= nil then shell.setPath(oldPath) end
print("CCKernel is no longer active.")