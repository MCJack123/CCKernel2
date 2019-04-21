if kernel == nil then error("This requires CCKernel2.") end
local num = tonumber(({...})[1])
if num == nil or num < 1 or num > 8 then error("VT must be in the range [1, 8]") end
kernel.chvt(math.floor(num))