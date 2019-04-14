if kernel == nil then error("This requires CCKernel2.") end
args = {...}
if args[1] == nil then error("Usage: lsperm <file>") end
local function bmask(a, m) return bit.band(a, m) == m end
local perms = fs.getPermissions(shell.resolve(args[1]), users.getuid())
local d = fs.isDir(shell.resolve(args[1])) and "d" or "-"
local s = bmask(perms, fs.permissions.setuid) and "s" or "-"
local r = bmask(perms, fs.permissions.read) and "r" or "-"
local w = bmask(perms, fs.permissions.write) and "w" or "-"
local x = bmask(perms, fs.permissions.execute) and "x" or "-"
local dl = bmask(perms, fs.permissions.delete) and "d" or "-"
print(d..s..r..w..x..dl..": " .. shell.resolve(args[1]))