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
if not tonumber(args[last]) then error("Invalid PID: " .. args[last]) end
kernel.kill(tonumber(args[last]), sig)