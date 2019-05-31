if not kernel then error("This requires CCKernel2.") end

local processes = {}
pcall(function() http.removeListener(8022) end)
http.listen(8022, function(req, res)
    local endpoint = req.getURL()
    if endpoint == "/open" then
        local pipe = kernel.popen_screen("/usr/bin/login.lua", "r", _ENV)
        local id = table.maxn(processes) + 1
        processes[id] = pipe
        res.setStatusCode(201)
        res.write(id)
        res.close()
        return
    elseif string.match(endpoint, "/process/%d+/") then
        local id = tonumber(({string.find(endpoint, "/process/(%d+)/")})[3])
        if processes[id] == nil then
            res.setStatusCode(404)
            res.write("404 Not Found")
            res.close()
            return
        elseif processes[id].term() == nil then
            processes[id] = nil
            res.setStatusCode(410)
            res.write("410 Gone")
            res.close()
            return
        end
        endpoint = string.sub(endpoint, string.len(string.match(endpoint, "/process/%d+/")) + 1)
        if endpoint == "read" then
            res.setStatusCode(200)
            res.write(processes[id].readAll())
            res.close()
            return
        elseif endpoint == "readColors" then
            res.setStatusCode(200)
            res.write(textutils.serialize({
                text = processes[id].readAll(),
                fg = processes[id].readTextColors(),
                bg = processes[id].readBackgroundColors()
            }))
            res.close()
            return
        elseif endpoint == "write" and req.getMethod() == "POST" then
            local str = req.readAll()
            for s in string.gmatch(str, ".") do kernel.send(processes[id].pid(), "char", s) end
            res.setStatusCode(200)
            res.write("")
            res.close()
            return
        elseif endpoint == "event" and req.getMethod() == "POST" then
            local param = textutils.unserialize(req.readAll())
            if param == nil then
                res.setStatusCode(400)
                res.write("400 Bad Request")
                res.close()
                return
            end
            --print(table.unpack(param))
            kernel.send(processes[id].pid(), table.unpack(param))
            res.setStatusCode(200)
            res.write("")
            res.close()
            return
        elseif endpoint == "events" and req.getMethod() == "POST" then
            local param = textutils.unserialize(req.readAll())
            if param == nil then
                res.setStatusCode(400)
                res.write("400 Bad Request")
                res.close()
                return
            end
            for k,v in pairs(param) do 
                --print(table.unpack(v))
                kernel.send(processes[id].pid(), table.unpack(v)) 
            end
            res.setStatusCode(200)
            res.write("")
            res.close()
            return
        elseif endpoint == "cursorPos" then
            res.setStatusCode(200)
            local x, y = processes[id].term().getCursorPos()
            res.write(x .. "," .. y)
            res.close()
            return
        elseif endpoint == "close" then
            processes[id].close()
            res.setStatusCode(200)
            res.write("")
            res.close()
            return
        end
    elseif string.match(endpoint, "/stopserver") then
        res.setStatusCode(200)
        res.write("")
        res.close()
        os.queueEvent("server_stop")
        return true
    end
    res.setStatusCode(404)
    res.write("404 Not Found")
    res.close()
end)
