local ptab = kernel.getProcesses()
local log = {}
for k,v in pairs(ptab) do if v.loggedin then table.insert(log, {k, v.path}) end end
textutils.tabulate(unpack(log))
