if kernel == nil then error("This requires CCKernel2.") end
args = {...}
if args[1] == nil then error("Usage: useradd <username>") end
users.create(args[1])