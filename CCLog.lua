-- CCLog.lua
-- CCKit
--
-- This file creates the CCLog class, which provides a native logging system
-- for applications. A default logger is also provided. Logs are stored at
-- /CCKit/logs/(name).log.
--
-- Copyright (c) 2018 JackMacWindows.

function string.trim(s)
    return string.match(s,'^()%s*$') and '' or string.match(s,'^%s*(.*%S)')
end  

local function getLine(filename, lineno)
    local i = 1
    local retval = ""
    if type(filename) ~= "string" or (not fs.exists(filename)) then return "" end
    for line in io.lines(filename) do
        if i == lineno then retval = line end
        i=i+1
    end
    return retval
end

-- this doesn't account for leap years, but that doesn't matter in Minecraft
local junOff = 31 + 28 + 31 + 30 + 31 + 30
local function dayToString(day)
    if day <= 31 then return "Jan " .. day
    elseif day > 31 and day <= 31 + 28 then return "Feb " .. day - 31
    elseif day > 31 + 28 and day <= 31 + 28 + 31 then return "Mar " .. day - 31 - 28
    elseif day > 31 + 28 + 31 and day <= 31 + 28 + 31 + 30 then return "Apr " .. day - 31 - 28 - 31
    elseif day > 31 + 28 + 31 + 30 and day <= 31 + 28 + 31 + 30 + 31 then return "May " .. day - 31 - 28 - 31 - 30
    elseif day > 31 + 28 + 31 + 30 + 31 and day <= junOff then return "Jun " .. day - 31 - 28 - 31 - 30 - 31
    elseif day > junOff and day <= junOff + 31 then return "Jul " .. day - junOff
    elseif day > junOff + 31 and day <= junOff + 31 + 31 then return "Aug " .. day - junOff - 31
    elseif day > junOff + 31 + 31 and day <= junOff + 31 + 31 + 30 then return "Sep " .. day - junOff - 31 - 31
    elseif day > junOff + 31 + 31 + 30 and day <= junOff + 31 + 31 + 30 + 31 then return "Oct " .. day - junOff - 31 - 31 - 30
    elseif day > junOff + 31 + 31 + 30 + 31 and day <= junOff + 31 + 31 + 30 + 31 + 30 then return "Nov " .. day - junOff - 31 - 31 - 30 - 31
    else return "Dec " .. day - junOff - 31 - 31 - 30 - 31 - 30 end
end

CCLog = {}

CCLog.logLevels = {
    debug = -1,
    info = 0,
    warning = 1,
    error = 2,
    critical = 3,
    traceback = 2,
    silent = 4
}

CCLog.logColors = {
    [-1] = colors.lightGray,
    [0] = colors.white,
    colors.yellow,
    colors.red,
    colors.pink
}

CCLog.default = {}
CCLog.default.fileDescriptor = nil
CCLog.default.shell = nil
CCLog.default.consoleLogLevel = CCLog.logLevels.warning
CCLog.default.logToConsole = false
CCLog.default.term = term.native()

function CCLog.default:open()
    if self.fileDescriptor == nil then
        self.fileDescriptor = fs.open("/var/logs/default.log", fs.exists("/var/logs/default.log") and "a" or "w")
        self.fileDescriptor.write("=== Logging started at " .. dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " ===\n")
        self.fileDescriptor.flush()
    end
end
function CCLog.default:write(text, level)
    self.fileDescriptor.write(text)
    if self.logToConsole and level >= self.consoleLogLevel then
        local lastTerm = term.current()
        term.redirect(self.term)
        local lastColor = term.getTextColor()
        term.setTextColor(CCLog.logColors[level])
        write(text) 
        term.setTextColor(lastColor)
        term.redirect(lastTerm)
    end
end
function CCLog.default:debug(name, text, class, lineno)
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Debug] " .. name .. ": ", CCLog.logLevels.debug)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.debug)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.debug) end
        self:write(": ", CCLog.logLevels.debug)
    end
    self:write(text .. "\n", CCLog.logLevels.debug)
    self.fileDescriptor.flush()
end
function CCLog.default:log(name, text, class, lineno)
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Info] " .. name .. ": ", CCLog.logLevels.info)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.info)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.info) end
        self:write(": ", CCLog.logLevels.info)
    end
    self:write(text .. "\n", CCLog.logLevels.info)
    self.fileDescriptor.flush()
end
CCLog.default.info = CCLog.default.log
function CCLog.default:warn(name, text, class, lineno)
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Warning] " .. name .. ": ", CCLog.logLevels.warning)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.warning)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.warning) end
        self:write(": ", CCLog.logLevels.warning)
    end
    self:write(text .. "\n", CCLog.logLevels.warning)
    self.fileDescriptor.flush()
end
function CCLog.default:error(name, text, class, lineno)
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Error] " .. name .. ": ", CCLog.logLevels.error)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.error)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.error) end
        self:write(": ", CCLog.logLevels.error)
    end
    self:write(text .. "\n", CCLog.logLevels.error)
    self.fileDescriptor.flush()
end
function CCLog.default:critical(name, text, class, lineno)
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Critical] " .. name .. ": ", CCLog.logLevels.critical)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.critical)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.critical) end
        self:write(": ", CCLog.logLevels.critical)
    end
    self:write(text .. "\n", CCLog.logLevels.critical)
    self.fileDescriptor.flush()
end
function CCLog.default:traceback(name, errortext, class, lineno)
    local i = 4
    local statuse = nil
    local erre = "t"
    self:write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Traceback] " .. name .. ": ", CCLog.logLevels.traceback)
    if class ~= nil then 
        self:write(class, CCLog.logLevels.traceback)
        if lineno ~= nil then self:write("[" .. lineno .. "]", CCLog.logLevels.traceback) end
        self:write(": ", CCLog.logLevels.traceback)
    end
    self:write(errortext .. "\n", CCLog.logLevels.traceback)
    while erre ~= "" do
        statuse, erre = pcall(function() error("", i) end)
        if erre == "" then break end
        local filename = string.sub(erre, 1, string.find(erre, ":")-1)
        if self.shell ~= nil then filename = self.shell.resolveProgram(filename) end
        if string.find(erre, ":", string.find(erre, ":")+1) == nil then
            self:write("    at " .. erre .. "\n", CCLog.logLevels.traceback)
        else
            local lineno = tonumber(string.sub(erre, string.find(erre, ":")+1, string.find(erre, ":", string.find(erre, ":")+1)-1))
            --if i == 4 then lineno=lineno-1 end
            self:write("    at " .. erre .. string.trim(getLine(filename, lineno)) .. "\n", CCLog.logLevels.traceback)
        end
        i=i+1
    end
    self.fileDescriptor.flush()
end
function CCLog.default:close()
    self.fileDescriptor.close()
    self.fileDescriptor = nil
end

function CCLog.createTerminal(log)
    if log.open == nil or log.name == nil or log.info == nil then error("Log is not a valid CCLog!") end
    log:open()
    local retval = {}
    retval.type = CCLog.logLevels.info
    retval.cache = ""
    function retval.save()
        local text = retval.cache
        if retval.type == CCLog.logLevels.debug then log:debug(text)
        elseif retval.type == CCLog.logLevels.info then log:info(text)
        elseif retval.type == CCLog.logLevels.warning then log:warn(text)
        elseif retval.type == CCLog.logLevels.error then log:error(text)
        elseif retval.type == CCLog.logLevels.critical then log:critical(text) end
        retval.cache = ""
    end
    function retval.write(text)
        if string.find(text, "\n") then
            retval.cache = retval.cache .. string.sub(text, 1, string.find(text, "\n") - 1)
            retval.save()
            retval.write(string.sub(text, string.find(text, "\n") + 1))
        else retval.cache = retval.cache .. text end
    end
    retval.blit = retval.write
    function retval.clear() retval.cache = "" end
    function retval.clearLine() retval.cache = "" end
    function retval.getCursorPos() return 1, 1 end
    function retval.setCursorPos(x, y) if y > 1 then retval.save() end end
    function retval.setCursorBlink() end
    function retval.isColor() return true end
    function retval.getSize() return 1024, 1 end
    function retval.scroll() retval.save() end
    function retval.setTextColor(c)
        if c == colors.gray or c == colors.lightGray then retval.type = CCLog.logLevels.debug
        elseif c == colors.white or c == colors.black or c == colors.green or c == colors.lime then retval.type = CCLog.logLevels.info
        elseif c == colors.yellow or c == colors.orange then retval.type = CCLog.logLevels.warning
        elseif c == colors.red then retval.type = CCLog.logLevels.error
        elseif c == colors.pink then retval.type = CCLog.logLevels.critical end
    end
    function retval.getTextColor() return CCLog.logColors[retval.type] end
    function retval.setBackgroundColor() end
    function retval.getBackgroundColor() return colors.black end
    function retval.setPaletteColor() end
    function retval.getPaletteColor() return 0, 0, 0 end
    return retval
end

CCLog.default:open()

setmetatable(CCLog, {__call = function(_, name)
    local retval = {}
    retval.name = name
    retval.fileDescriptor = nil
    retval.showInDefaultLog = true
    retval.shell = nil
    function retval:open()
        if self.fileDescriptor == nil then
            if type(self.name) == "table" then textutils.pagedPrint(textutils.serialize(self)) end
            self.fileDescriptor = fs.open("/var/logs/" .. self.name .. ".log", fs.exists("/var/logs/" .. self.name .. ".log") and "a" or "w")
            if self.fileDescriptor == nil then error("Could not open log file") end
            self.fileDescriptor.write("=== Logging for " .. name .. " started at " .. dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " ===\n")
            self.fileDescriptor.flush()
        end
    end
    function retval:debug(text, class, lineno)
        if self == nil then error("No self") end
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Debug] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(text .. "\n")
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:debug(self.name, text, class, lineno) 
        end
    end
    function retval:log(text, class, lineno)
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Info] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(text .. "\n")
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:log(self.name, text, class, lineno) 
        end
    end
    retval.info = retval.log
    function retval:warn(text, class, lineno)
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Warning] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(text .. "\n")
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:warn(self.name, text, class, lineno) 
        end
    end
    function retval:error(text, class, lineno)
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Error] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(text .. "\n")
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:error(self.name, text, class, lineno) 
        end
    end
    function retval:critical(text, class, lineno)
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Critical] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(text .. "\n")
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:critical(self.name, text, class, lineno) 
        end
    end
    function retval:traceback(errortext, class, lineno)
        local i = 4
        local statuse, erre = nil
        self.fileDescriptor.write(dayToString(os.day()) .. " " .. textutils.formatTime(os.time(), false) .. " [Traceback] ")
        if class ~= nil then 
            self.fileDescriptor.write(class)
            if lineno ~= nil then self.fileDescriptor.write("[" .. lineno .. "]") end
            self.fileDescriptor.write(": ")
        end
        self.fileDescriptor.write(errortext .. "\n")
        while erre ~= "" do
            statuse, erre = pcall(function() error("", i) end)
            if erre == "" then break end
            local filename = string.sub(erre, 1, string.find(erre, ":")-1)
            if self.shell ~= nil then filename = self.shell.resolveProgram(filename) end
            if string.find(erre, ":") == nil or string.find(erre, ":", string.find(erre, ":")+1) == nil then
                self.fileDescriptor.write("    at " .. erre .. "\n")
            else
                local lineno = tonumber(string.sub(erre, string.find(erre, ":")+1, string.find(erre, ":", string.find(erre, ":")+1)-1))
                --if i == 4 then lineno=lineno-1 end
                self.fileDescriptor.write("    at " .. erre .. string.trim(getLine(filename, lineno)) .. "\n")
            end
            i=i+1
        end
        self.fileDescriptor.flush()
        if (self.showInDefaultLog) then 
            CCLog.default:traceback(self.name, errortext, class, lineno) 
        end
    end
    function retval:close()
        self.fileDescriptor.close()
        self.fileDescriptor = nil
    end
    function retval:terminal() return CCLog.createTerminal(self) end
    return retval
end})

return CCLog