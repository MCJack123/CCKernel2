if kernel == nil then error("This requires CCKernel2.") end
args = {...}
if args[1] == nil then error("Usage: userdel <username>") end
users.delete(users.getUIDFromName(args[1]))