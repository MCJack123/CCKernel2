if kernel == nil then error("This requires CCKernel2.") end
local sig = signal.SIGINT
local args = {...}
local last = 1
if string.sub(args[1], 1, 1) == "-" then
    last = 2
    local s = string.sub(args[1], 2)
    if tonumber(s) then sig = tonumber(s)
    elseif signal[s] then sig = signal[2] end
end
local ptab = kernel.getProcesses()
for k,v in pairs(ptab) do if ({string.gsub(fs.getName(v.path), ".lua", "")})[1] == args[last] then kernel.kill(v.pid, sig) end end