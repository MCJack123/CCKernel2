local args = {...}
if not args[1] then error("Usage: rsh <ip>") end

local openfd = http.get("http://" .. args[1] .. ":8022/open")
local id = tonumber(openfd.readAll())
openfd.close()

local function _event(...) http.post("http://" .. args[1] .. ":8022/process/" .. id .. "/event", textutils.serialize({...})) end
local function _events(ev) http.request("http://" .. args[1] .. ":8022/process/" .. id .. "/events", textutils.serialize(ev)) end

local function wrapRequest(url)
    http.request(url)
    local events = {}
    while true do
        local ev = {os.pullEvent()}
        if ev[1] == "http_success" then 
            if ev[2] == url then
                --print("got url")
                _events(events)
                return ev[3]
            else 
                --print("success: " .. ev[2]) 
                --ev[3].close()
            end
        elseif ev[1] == "http_failure" then 
            if ev[2] == url then return nil else print("fail: " .. ev[2]) end 
        else
            table.insert(events, ev)
        end
    end
    error("This should not break")
end

local function _read()
    local fd = wrapRequest("http://" .. args[1] .. ":8022/process/" .. id .. "/readColors")
    if not fd or fd.getResponseCode() ~= 200 then return nil end
    local retval = textutils.unserialize(fd.readAll())
    fd.close()
    return retval.text, retval.fg, retval.bg
end

local function _cursorPos()
    local fd = wrapRequest("http://" .. args[1] .. ":8022/process/" .. id .. "/cursorPos")
    if not fd or fd.getResponseCode() ~= 200 then return nil end
    local t = fd.readAll()
    fd.close()
    local retval = {string.find(t, "(%d+),(%d+)")}
    table.remove(retval, 1)
    table.remove(retval, 1)
    return table.unpack(retval)
end

local function pc(str) return string.find("0123456789abcdef", string.sub(str,1,1)) and bit.blshift(1, string.find("0123456789abcdef", string.sub(str,1,1)) - 1) or nil end

local ok, err = pcall(function()
    term.setCursorBlink(true)
    while true do
        local text, fg, bg = _read()
        if text == nil then break end
        local x, y = _cursorPos()
        if x == nil then break end
        term.clear()
        term.setCursorPos(1, 1)
        for i = 0, string.len(text) do
            term.setBackgroundColor(pc(string.sub(bg, i, i)) or colors.black)
            term.setTextColor(pc(string.sub(fg, i, i)) or colors.white)
            write(string.sub(text, i, i))
        end
        term.setCursorPos(tonumber(x), tonumber(y))
        --_event(os.pullEvent())
        --term.setCursorBlink(false)
        --os.sleep(0.05)
    end
end)
term.clear()
term.setCursorPos(1, 1)
http.get("http://" .. args[1] .. ":8022/process/" .. id .. "/close")
if not ok then error(err) end
