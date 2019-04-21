if http.listen == nil then error("This requires CraftOS-PC v1.2 or later.") end
www_root = "/var/www"
port = tonumber(({...})[1]) or 80
if not fs.isDir(www_root) then 
    fs.makeDir(www_root) 
    local file = fs.open(www_root .. "/index.html", "w")
    file.write("<html><body><h1>It works!</h1></body></html>")
    file.close()
end

function http_server(req, res)
    local url = req.getURL()
    local query = {}
    local postdata = {}
    local querystr = ""
    if string.find(url, "?") then
        querystr = string.sub(url, string.find(url, "?") + 1)
        url = string.sub(url, 1, string.find(url, "?") - 1)
        for s in string.gmatch(querystr, ".+=?.+&?") do
            if not string.find(s, "=") then query[s] = true
            else query[string.sub(s, 1, string.find(s, "=") - 1)] = string.sub(s, string.find(s, "=") + 1) end
        end
    end
    if req.getMethod() == "POST" and req.getRequestHeaders()["Content-Type"] == "application/x-www-form-urlencoded" then
        local querystr = req.readAll()
        for s in string.gmatch(querystr, ".+=?.+&?") do
            if not string.find(s, "=") then query[s] = true
            else query[string.sub(s, 1, string.find(s, "=") - 1)] = string.sub(s, string.find(s, "=") + 1) end
        end
    end
    if string.sub(url, string.len(url)) == "/" then
        url = url .. "index.html"
    end
    print("Got request for " .. url)
    if not fs.exists(www_root .. url) then
        print("Sending 404")
        res.setStatusCode(404)
        res.setResponseHeader("Content-Type", "text/html")
        if fs.exists(www_root .. "/404.html") then
            local file = fs.open(www_root .. "/404.html", "r")
            res.write(file.readAll())
            file.close()
        else
            res.write("<html><body><h1>404 Not Found</h1><p>The requested URL " .. url .. " was not found on this server.<hr><i>CCServer/1.0 (CraftOS) Server at 127.0.0.1 Port " .. port .. "</i></p></body></html>")
        end
        pcall(res.close)
        return
    end
    if string.sub(url, string.len(url) - 3) == ".lua" then
        local env = {}
        local output = ""
        env.print = function(s, ...)
            if s == nil then return end
            output = output .. tostring(s) .. "\n"
        end
        env.write = function(s, ...)
            if s == nil then return end
            output = output .. tostring(s)
        end
        env.header = res.setResponseHeader
        env.response_code = res.setStatusCode
        env._GET = query
        env._POST = postdata
        env._SERVER = {
            GATEWAY_INTERFACE = _VERSION,
            REQUEST_URI = url,
            SERVER_PORT = port,
            REQUEST_METHOD = req.getMethod(),
            REQUEST_TIME = os.time(),
            SERVER_ADDR = "127.0.0.1",
            LUA_SELF = www_root .. url,
            QUERY_STRING = querystr,
            DOCUMENT_ROOT = www_root
        }
        env.error = error
        env.textutils = textutils
        env.fs = fs
        env.string = string
        env.table = table
        env.os = os
        env.http = http
        env.bit = bit
        env.colors = colors
        env.disk = disk
        env.keys = keys
        env.math = math
        env.vector = vector
        env.assert = assert
        env.dofile = dofile
        env.getmetatable = getmetatable
        env.ipairs = ipairs
        env.load = load
        env.loadfile = loadfile
        env.loadstring = loadstring
        env.next = next
        env.pairs = pairs
        env.pcall = pcall
        env.rawequal = rawequal
        env.rawget = rawget
        env.rawset = rawset
        env.select = select
        env.setmetatable = setmetatable
        env.sleep = sleep
        env.tonumber = tonumber
        env.tostring = tostring
        env.type = type
        env.unpack = unpack
        env.xpcall = xpcall
        env._HOST = _HOST
        env._VERSION = _VERSION
        print("Executing " .. www_root .. url)
        local success = false
        local err = "File not found"
        local script = loadfile(www_root .. url, env)
        if script then success, err = pcall(script) end
        if not success then
            print("Sending 500")
            res.setStatusCode(500)
            res.setResponseHeader("Content-Type", "text/html")
            if fs.exists(www_root .. "/500.html") then
                local file = fs.open(www_root .. "/500.html", "r")
                res.write(file.readAll())
                file.close()
            else
                res.write("<html><body><h1>500 Internal Server Error</h1><p>An error occurred while processing a CGI script on the server.<br>Error: " .. err .. "<hr><i>CCServer/1.0 (CraftOS) Server at 127.0.0.1 Port " .. port .. "</i></p></body></html>")
            end
            pcall(res.close)
            return
        end
        res.write(output)
    else
        local file = fs.open(www_root .. url, "r")
        res.write(file.readAll())
        file.close()
    end
    pcall(res.close)
end

pcall(function() http.removeListener(port) end)
http.listen(port, http_server)