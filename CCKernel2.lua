--[[ 
CCKernel 2
Features: multiprocessing, IPC, permissions, signaling, virtual terminals, file descriptors, debugging, multiple users, filesystem reorganization, I/O operations

* For multiprocessing, we need a run loop that executes coroutines in a table one by one.
* For IPC, we need to pull events sent from each coroutine into the run loop. Then we need to check the PID, name, etc. and resend the events into the parallel coroutines.
* For permissions, we need to rewrite the fs API to do virtual permission checks before opening the file. Storing permissions may have to be inside a hidden file at the root directory, storing the bits for permissions for each file.
* For signaling, we need IPC + checking the events sent for specific signals. If the name matches, then we either a) do what the signal means (SIGKILL, SIGTERM, SIGSTOP, etc.), or b) relay the signal into the program.
* For virtual terminals, we need to have multiple copies of the term API that can be switched as needed.
* For file descriptors, we need to catch opening these files in the fs API, and return the respective file handle for the file descriptor. Possible descriptors:
  * /dev/random: file.read() returns math.random(0, 255)
  * /dev/zero: file.read() returns 0
  * /dev/null: file.write() does nothing
  * /dev/stdout: file.write() writes a character to the terminal
  * /dev/stdin: file.read() returns the next character in the input or 0
  * /dev/fifo[0-9]: FIFO (first in, first out) files
* For debugging, we need to have a debug entrypoint in the kernel that the processes can call on an error. Unfortunately, we cannot catch errors outside of coroutines, so enabling debugging support in a program will be the task of the programmer. (We'll probably just run rom/programs/lua.lua with the coroutine environment.)
  * Actually, if the coroutine environment is not copied on execution, it may be possible to examine the environment outside of the program. Catching errors outside and resuming will not be possible, but stepping through to each os.pullEvent() may be possible.
* For multiple users, we need to implement a custom runtime for each coroutine. (We'll figure this out as we go.)
* For filesystem reorganization, we just need to remap the files in /rom to /bin, /lib, /share, /etc, etc. inside the fs API. /rom will still be accessible.
* For I/O operations, we need to rewrite term.write() and input() to use piped data first, then use the normal I/O data. Each process will need to be aware of where it's being piped to.

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
    deny_move = 0x7,
    move = 0x8,
    read_move = 0x9,
    write_move = 0xA,
    deny_delete = 0xB,
    delete_move = 0xC,
    deny_write = 0xD,
    deny_read = 0xE,
    full = 0xF
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

function orig_fs.getPermissions(path, uid)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if orig_fs.getDrive(path) == "rom" then return permissions.read end
    local default = orig_fs.isReadOnly(path) and permissions.read or permissions.full
    if not orig_fs.exists(path) then return default end
    if not orig_fs.exists(orig_fs.getDir(path) .. "/.permissions") then 
        local file = orig_fs.open(orig_fs.getDir(path) .. "/.permissions", "w")
        if file ~= nil then
            file.write(textutils.serialize({[orig_fs.getName(path)] = {["*"] = default}}))
            file.close()
        end
        return default
    end
    local file = orig_fs.open(orig_fs.getDir(path) .. "/.permissions", "r")
    local perms = textutils.unserialize(file.readAll())
    file.close()
    if perms[orig_fs.getName(path)] == nil then 
        perms[orig_fs.getName(path)] = {["*"] = default}
        local file = orig_fs.open(orig_fs.getDir(path) .. "/.permissions", "w")
        if file ~= nil then
            file.write(textutils.serialize(perms))
            file.close()
        end
        return default
    else return get_permissions(perms[orig_fs.getName(path)], uid) end
end

function orig_fs.setPermissions(path, uid, perm)
    if type(path) ~= "string" then error("bad argument #1 (string expected, got " .. type(path) .. ")", 3) end
    if type(uid) ~= "string" and type(uid) ~= "number" then error("bad argument #2 (number or string expected, got " .. type(path) .. ")", 3) end
    if type(perm) ~= "number" or perm < 0 or perm > 15 then error("bad argument #3 (number expected, got " .. type(path) .. ")", 3) end
    if not orig_fs.exists(path) then error(path .. ": No such file", 3) end
    if orig_fs.getDrive(path) == "rom" then error(path .. ": Access denied", 3) end
    local file = orig_fs.open(orig_fs.getDir(path) .. "/.permissions", "r")
    local perms = textutils.unserialize(file.readAll())
    file.close()
    if not has_permission(perms, uid, permissions.write) then error(path .. ": Access denied", 3) end
    perms[orig_fs.getName(path)] = {[uid] = perm}
    local file = orig_fs.open(orig_fs.getDir(path) .. "/.permissions", "w")
    if file ~= nil then
        file.write(textutils.serialize(perms))
        file.close()
    end
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
    if not bmask(m.getPermissions(p, getuid()), permissions.write) then error(path .. ": Access denied", 2) end
    return m.setPermissions(p, uid, perm)
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
    local file = fs.open(fs.getDir(path) .. "/.permissions", "r")
    local inperms = textutils.unserialize(file.readAll())
    file.close()
    inperms[fs.getName(path)] = {["*"] = default_permissions}
    file = fs.open(fs.getDir(path) .. "/.permissions", "w")
    file.write(textutils.serialize(inperms))
    file.close()
end

function fs.move(path, toPath)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.move) then error(path .. ": Access denied", 2) end
    if not bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
    m.move(p, toPath)
    local file = fs.open(fs.getDir(path) .. "/.permissions", "r")
    local inperms = textutils.unserialize(file.readAll())
    file.close()
    file = fs.open(fs.getDir(toPath) .. "/.permissions", "r")
    local outperms = textutils.unserialize(file.readAll())
    file.close()
    outperms[fs.getName(toPath)] = inperms[fs.getName(path)]
    inperms[fs.getName(path)] = nil
    file = fs.open(fs.getDir(toPath) .. "/.permissions", "w")
    file.write(textutils.serialize(outperms))
    file.close()
    file = fs.open(fs.getDir(path) .. "/.permissions", "w")
    file.write(textutils.serialize(inperms))
    file.close()
end

function fs.copy(path, toPath)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.read) then error(path .. ": Access denied", 2) end
    if not bmask(fs.getPermissions(toPath, getuid()), permissions.write) then error(toPath .. ": Access denied", 2) end
    m.copy(p, toPath)
    local file = fs.open(fs.getDir(path) .. "/.permissions", "r")
    local inperms = textutils.unserialize(file.readAll())
    file.close()
    file = fs.open(fs.getDir(toPath) .. "/.permissions", "r")
    local outperms = textutils.unserialize(file.readAll())
    file.close()
    outperms[fs.getName(toPath)] = inperms[fs.getName(path)]
    file = fs.open(fs.getDir(toPath) .. "/.permissions", "w")
    file.write(textutils.serialize(outperms))
    file.close()
end

function fs.delete(path)
    local m, p = getMount(path)
    if not bmask(m.getPermissions(p, getuid()), permissions.delete) then error(path .. ": Access denied", 2) end
    m.delete(p)
    local file = fs.open(fs.getDir(path) .. "/.permissions", "r")
    local inperms = textutils.unserialize(file.readAll())
    file.close()
    inperms[fs.getName(path)] = nil
    file = fs.open(fs.getDir(path) .. "/.permissions", "w")
    file.write(textutils.serialize(inperms))
    file.close()
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

function fs.mounts() return mounts end

function getuid() return 0 end