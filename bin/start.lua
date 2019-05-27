if kernel == nil then error("This requires CCKernel2.") end
local args = {...}
kernel.exec(shell.resolveProgram(table.remove(args, 1)), table.unpack(args))