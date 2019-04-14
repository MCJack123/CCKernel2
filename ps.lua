if kernel == nil then error("This requires CCKernel2.") end
local ptable = kernel.getProcesses()
local ttable = {{"PID", "TTY", "CMD"}}
for k,v in pairs(ptable) do 
    if k == 0 then table.insert(ttable, 2, {tostring(k), "tty" .. tostring(v.vt), ({string.gsub(fs.getName(v.path), ".lua", "")})[1]}) 
    else table.insert(ttable, {tostring(k), "tty" .. tostring(v.vt), ({string.gsub(fs.getName(v.path), ".lua", "")})[1]}) end
end
textutils.tabulate(unpack(ttable))