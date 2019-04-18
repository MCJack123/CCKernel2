if kernel == nil then error("This requires CCKernel2.") end
args = {...}
if args[2] == nil then error("Usage: usermod <username> <fullname>") end
users.setFullName(users.getUIDFromName(args[1]), args[2])