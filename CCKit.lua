--[[ Need: 
CCAlertWindow
CCApplication
CCButton
CCCheckbox
CCControl
CCEventHandler
CCLabel
CCProgressBar
CCScrollView
CCTextField
CCTextView
CCView
CCViewController
CCWindow
CCGraphics
CCKit
CCKitGlobals
CCWindowRegistry
]]

-- CCKitAmalgamated.lua
-- CCKit
--
-- This file combines all of the files in CCKit into one file that can be loaded.
--
-- Copyright (c) 2018 JackMacWindows.

-- CCKitGlobals.lua
-- CCKit
--
-- This file defines global variables that other files read from. This must be
-- placed at /CCKit/CCKitGlobals.lua for other CCKit classes to work. This can
-- also be modified by the end user to change default values.
--
-- Copyright (c) 2018 JackMacWindows.

CCKitGlobals = {}

-- All classes
CCKitGlobals.CCKitDir = "CCKit"                             -- The directory where all of the CCKit files are located
CCKitGlobals.shouldDoubleRequire = true                     -- Whether loadAPI should load the API even when it's already loaded

-- CCWindow
CCKitGlobals.titleBarColor = colors.yellow                  -- The color of the background of the title bar
CCKitGlobals.titleBarTextColor = colors.black               -- The color of the text of the title bar
CCKitGlobals.windowBackgroundColor = colors.white           -- The color of the background of a window
CCKitGlobals.liveWindowMove = true                          -- Whether to redraw window contents while moving or to only show the border (for speed)

-- Text views
CCKitGlobals.defaultTextColor = colors.black                -- The default color of text

-- CCButtons
CCKitGlobals.buttonColor = colors.lightGray                 -- The color of a normal button
CCKitGlobals.buttonSelectedColor = colors.gray              -- The color of a selected button
CCKitGlobals.buttonHighlightedColor = colors.lightBlue      -- The color of a highlighted button
CCKitGlobals.buttonHighlightedSelectedColor = colors.blue   -- The color of a highlighted selected button
CCKitGlobals.buttonDisabledColor = colors.lightGray         -- The color of a disabled button
CCKitGlobals.buttonDisabledTextColor = colors.gray -- The color of the text in a disabled button

-- CCKitGlobalFunctions.lua
-- CCKit
--
-- Defines some functions that are used by some files. Automatically included by
-- CCKitGlobals.lua.
--
-- Copyright (c) 2018 JackMacWindows.

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function table.combine(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return nil end
    local orig_type = type(b)
    local copy = deepcopy(a)
    for orig_key, orig_value in next, b, nil do
        copy[deepcopy(orig_key)] = deepcopy(orig_value)
    end
    setmetatable(copy, deepcopy(getmetatable(b)))
    return copy
end

function multipleInheritance(...)
    local tables = { ... }
    local retval = tables[1]
    for k,v in ipairs(tables) do if k ~= 1 then retval = table.combine(retval, v) end end
    return retval
end

-- Better serialize
local g_tLuaKeywords = {
    [ "and" ] = true,
    [ "break" ] = true,
    [ "do" ] = true,
    [ "else" ] = true,
    [ "elseif" ] = true,
    [ "end" ] = true,
    [ "false" ] = true,
    [ "for" ] = true,
    [ "function" ] = true,
    [ "if" ] = true,
    [ "in" ] = true,
    [ "local" ] = true,
    [ "nil" ] = true,
    [ "not" ] = true,
    [ "or" ] = true,
    [ "repeat" ] = true,
    [ "return" ] = true,
    [ "then" ] = true,
    [ "true" ] = true,
    [ "until" ] = true,
    [ "while" ] = true,
}

local function serializeImpl( t, tTracking, sIndent )
    local sType = type(t)
    if sType == "table" then
        if tTracking[t] ~= nil then
            return "recursive"
        end
        tTracking[t] = true

        if next(t) == nil then
            -- Empty tables are simple
            return "{}"
        else
            -- Other tables take more work
            local sResult = "{\n"
            local sSubIndent = sIndent .. "  "
            local tSeen = {}
            for k,v in ipairs(t) do
                tSeen[k] = true
                sResult = sResult .. sSubIndent .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
            end
            for k,v in pairs(t) do
                if not tSeen[k] then
                    local sEntry
                    if type(k) == "string" and not g_tLuaKeywords[k] and string.match( k, "^[%a_][%a%d_]*$" ) then
                        sEntry = k .. " = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
                    else
                        sEntry = "[ " .. serializeImpl( k, tTracking, sSubIndent ) .. " ] = " .. serializeImpl( v, tTracking, sSubIndent ) .. ",\n"
                    end
                    sResult = sResult .. sSubIndent .. sEntry
                end
            end
            sResult = sResult .. sIndent .. "}"
            return sResult
        end
        
    elseif sType == "string" then
        return string.format( "%q", t )
    
    elseif sType == "number" or sType == "boolean" or sType == "nil" then
        return tostring(t)
        
    else
        return "unserializable"
        
    end
end

function textutils.serialize( t )
    local tTracking = {}
    return serializeImpl( t, tTracking, "" )
end

function setEGAColors() -- just putting this here if anyone really wants it
    if tonumber(string.sub(os.version(), 9)) < 1.8 then error("This requires CraftOS 1.8 or later.", 2) end
    term.setPaletteColor(colors.black, 0, 0, 0)
    term.setPaletteColor(colors.blue, 0, 0, 0.625)
    term.setPaletteColor(colors.green, 0, 0.625, 0)
    term.setPaletteColor(colors.cyan, 0, 0.625, 0.625)
    term.setPaletteColor(colors.red, 0.625, 0, 0)
    term.setPaletteColor(colors.purple, 0.625, 0, 0.625)
    term.setPaletteColor(colors.brown, 0.625, 0.3125, 0)
    term.setPaletteColor(colors.lightGray, 0.625, 0.625, 0.625)
    term.setPaletteColor(colors.gray, 0.3125, 0.3125, 0.3125)
    term.setPaletteColor(colors.lightBlue, 0.3125, 0.3125, 1)
    term.setPaletteColor(colors.lime, 0.3125, 1, 0.3125)
    term.setPaletteColor(colors.pink, 1, 0.3125, 0.3125)
    -- CraftOS uses orange instead of light cyan, skipping
    term.setPaletteColor(colors.magenta, 1, 0.3125, 1)
    term.setPaletteColor(colors.yellow, 1, 1, 0.3125)
    term.setPaletteColor(colors.white, 1, 1, 1)
end

-- CCGraphics.lua
-- CCKit
--
-- The ComputerCraft screen is normally 51x19, but there is an extended
-- character set that allows extra pixels to be drawn. This allows the computer
-- to use modes kind of like early CGA/EGA graphics. The screen can be
-- extended to have a full 102x57 resolution. This file is used to keep track
-- of these mini-pixels and draw to the screen in lower resolution.
-- This file is used for windows and other non-term screens.
--
-- Copyright (c) 2018 JackMacWindows.

if not term.isColor() then error("This API requires an advanced computer.", 2) end

local colorString = "0123456789abcdef"
CCGraphics = {}

local function cp(color)
    if color == 0 then return 0 end
    local recurses = 1
    local cc = color
    while cc ~= 1 do 
        cc = bit.brshift(cc, 1)
        recurses = recurses + 1
    end
    --print(recurses .. " " .. color .. " \"" .. string.sub(colorString, recurses, recurses) .. "\"")
    return string.sub(colorString, recurses, recurses)
end

function CCGraphics.drawFilledBox(x, y, endx, endy, color) 
    for px=x,endx do for py=y,endy do 
        term.setCursorPos(px, py)
        term.blit(" ", "0", cp(color)) 
    end end 
end

-- Converts a 6-bit pixel value to a character.
-- Returns: character, whether to flip the colors
local function pixelToChar(pixel)
    if pixel < 32 then
        return string.char(pixel + 128), false
    else
        return string.char(bit.band(bit.bnot(pixel), 63) + 128), true
    end
end

-- Redraws a certain pixel.
-- Parameter: win = the win to control
-- Parameter: x = x
-- Parameter: y = y
local function redrawChar(win, x, y)
    win.setCursorPos(x+1, y+1)
    if win.screenBuffer[x][y] == nil then error("pixel not found at " .. x .. ", " .. y) end
    if win.screenBuffer[x][y].transparent == true then return end
    if win.screenBuffer[x][y].useCharacter == true then win.blit(win.screenBuffer[x][y].character, cp(win.screenBuffer[x][y].fgColor), cp(win.screenBuffer[x][y].bgColor))
    else
        local char, flip = pixelToChar(win.screenBuffer[x][y].pixelCode)
        if flip then win.blit(char, cp(win.screenBuffer[x][y].bgColor), cp(win.screenBuffer[x][y].fgColor))
        else win.blit(char, cp(win.screenBuffer[x][y].fgColor), cp(win.screenBuffer[x][y].bgColor)) end
    end
end

-- Updates the screen with the graphics buffer.
-- Parameter: win = the win to control
function CCGraphics.redrawScreen(win)
    if not win.graphicsInitialized then error("graphics not initialized", 3) end
    win.clear()
    for x=0,win.screenBuffer.termWidth-1 do
        for y=0,win.screenBuffer.termHeight-1 do
            redrawChar(win, x, y)
        end
    end
end

-- Initializes the graphics buffer.
-- Parameter: win = the win to control
-- Returns: new screen width, new screen height
function CCGraphics.initGraphics(win)
    local width, height = win.getSize()
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clear()
    win.setCursorPos(1, 1)
    win.setCursorBlink(false)
    win.screenBuffer = {}
    win.screenBuffer.width = width * 2
    win.screenBuffer.height = height * 3
    win.screenBuffer.termWidth = width
    win.screenBuffer.termHeight = height
    for x=0,width-1 do
        win.screenBuffer[x] = {}
        for y=0,height-1 do
            --print("creating pixel " .. x .. ", " .. y)
            win.screenBuffer[x][y] = {}
            win.screenBuffer[x][y].fgColor = colors.white -- Text color
            win.screenBuffer[x][y].bgColor = colors.black -- Background color
            win.screenBuffer[x][y].pixelCode = 0 -- Stores the data as a 6-bit integer (tl, tr, cl, cr, bl, br)
            win.screenBuffer[x][y].useCharacter = false -- Whether to print a custom character
            win.screenBuffer[x][y].character = " " -- Custom character
        end
    end
    win.graphicsInitialized = true
    return width * 2, height * 3
end

-- Checks whether the graphics are initialized.
-- Parameter: win = the win to control
-- Returns: whether the graphics are initialized
function CCGraphics.graphicsAreInitialized(win)
    if win == nil then return false end
    return win.graphicsInitialized
end

-- Ends the graphics buffer.
-- Parameter: win = the win to control
function CCGraphics.endGraphics(win)
    win.screenBuffer = nil
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clear()
    win.setCursorPos(1, 1)
    win.setCursorBlink(false)
    win.graphicsInitialized = false
end

-- Returns the colors defined at the text location.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
-- Returns: foreground color, background color
function CCGraphics.getPixelColors(win, x, y)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x > win.screenBuffer.termWidth or y > win.screenBuffer.termHeight then error("position out of bounds", 2) end
    return win.screenBuffer[x][y].fgColor, win.screenBuffer[x][y].backgroundColor
end

-- Sets the colors at a text location.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
-- Parameter: fgColor = the foreground color to set (nil to keep)
-- Parameter: bgColor = the background color to set (nil to keep)
-- Returns: foreground color, background color
function CCGraphics.setPixelColors(win, x, y, fgColor, bgColor)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x % 1 ~= 0 or y % 1 ~= 0 then error("coordinates must be integers, got (" .. x .. ", " .. y .. ")", 2) end
    if x > win.screenBuffer.termWidth or y > win.screenBuffer.termHeight then error("position out of bounds", 2) end
    if fgColor ~= nil then win.screenBuffer[x][y].fgColor = fgColor end
    if bgColor ~= nil then win.screenBuffer[x][y].bgColor = bgColor end
    redrawChar(win, x, y)
    return win.screenBuffer[x][y].fgColor, win.screenBuffer[x][y].bgColor
end

-- Clears the text location.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
function CCGraphics.clearCharacter(win, x, y, redraw)
    redraw = redraw or true
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x > win.screenBuffer.termWidth or y > win.screenBuffer.termHeight then error("position out of bounds", 2) end
    win.screenBuffer[x][y].useCharacter = false
    win.screenBuffer[x][y].pixelCode = 0
    if redraw then redrawChar(win, x, y) end
end

-- Turns a pixel on at a location.
-- Parameter: win = the win to control
-- Parameter: x = the x location of the pixel
-- Parameter: y = the y location of the pixel
function CCGraphics.setPixel(win, x, y)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x > win.screenBuffer.width or y > win.screenBuffer.height then error("position out of bounds", 2) end
    win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].useCharacter = false
    win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].pixelCode = bit.bor(win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].pixelCode, 2^(2*(y % 3) + (x % 2)))
    redrawChar(win, math.floor(x / 2), math.floor(y / 3))
end

-- Turns a pixel off at a location.
-- Parameter: win = the win to control
-- Parameter: x = the x location of the pixel
-- Parameter: y = the y location of the pixel
function CCGraphics.clearPixel(win, x, y)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x > win.screenBuffer.width or y > win.screenBuffer.height then error("position out of bounds", 2) end
    win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].useCharacter = false
    win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].pixelCode = bit.band(win.screenBuffer[math.floor(x / 2)][math.floor(y / 3)].pixelCode, bit.bnot(2^(2*(y % 3) + (x % 2))))
    redrawChar(win, math.floor(x / 2), math.floor(y / 3))
end

-- Sets a pixel at a location to a value.
-- Parameter: win = the win to control
-- Parameter: x = the x location of the pixel
-- Parameter: y = the y location of the pixel
-- Parameter: value = the value to set the pixel to
function CCGraphics.setPixelValue(win, x, y, value)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x > win.screenBuffer.width or y > win.screenBuffer.height then error("position " .. x .. ", " .. y .. " out of bounds", 2) end
    if value then CCGraphics.setPixel(win, x, y) else CCGraphics.clearPixel(win, x, y) end
end

-- Sets a custom character to be printed at a location.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
-- Parameter: char = the character to print
function CCGraphics.setCharacter(win, x, y, char)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if win.screenBuffer[x] == nil or win.screenBuffer[x][y] == nil then error("position out of bounds: " .. x .. ", " .. y, 2) end
    win.screenBuffer[x][y].useCharacter = true
    win.screenBuffer[x][y].character = char
    redrawChar(win, x, y)
end

-- Sets a custom string to be printed at a location.
-- Parameter: win = the win to control
-- Parameter: x = the x location of the start of the string
-- Parameter: y = the y location of the string
-- Parameter: str = the string to set
function CCGraphics.setString(win, x, y, str)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x + string.len(str) - 1 > win.screenBuffer.termWidth or y > win.screenBuffer.termHeight then error("region out of bounds", 2) end
    for px=x,x+string.len(str)-1 do CCGraphics.setCharacter(win, px, y, string.sub(str, px-x+1, px-x+1)) end
end

-- Draws a line on the screen.
-- Parameter: win = the win to control
-- Parameter: x = origin x
-- Parameter: y = origin y
-- Parameter: length = length of the line
-- Parameter: isVertical = whether the line is vertical or horizontal
-- Parameter: color = the color of the line
-- Parameter: fgColor = the text color of the line (ignore to keep color)
function CCGraphics.drawLine(win, x, y, length, isVertical, color, fgColor)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if isVertical then
        if y + length > win.screenBuffer.termHeight then error("region out of bounds", 2) end
        for py=y,y+length-1 do
            CCGraphics.clearCharacter(win, x, py, false)
            CCGraphics.setPixelColors(win, x, py, fgColor, color)
            --redrawChar(win, x, py)
        end
    else
        if x + length > win.screenBuffer.termWidth then error("region out of bounds", 2) end
        for px=x,x+length-1 do
            CCGraphics.clearCharacter(win, px, y, false)
            CCGraphics.setPixelColors(win, px, y, fgColor, color)
            --redrawChar(win, px, y)
        end
    end
end

-- Draws a box on the screen.
-- Parameter: win = the win to control
-- Parameter: x = origin x
-- Parameter: y = origin y
-- Parameter: width = box width
-- Parameter: height = box height
-- Parameter: color = box color
-- Parameter: fgColor = the text color of the line (ignore to keep color)
function CCGraphics.drawBox(win, x, y, width, height, color, fgColor)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x + width > win.screenBuffer.termWidth or y + height > win.screenBuffer.termHeight then error("region out of bounds", 2) end
    for px=x,x+width-1 do for py=y,y+height-1 do
        CCGraphics.clearCharacter(win, px, py, false)
        CCGraphics.setPixelColors(win, px, py, fgColor, color)
        --redrawChar(win, px, py)
    end end
end

-- Captures an image of an area on screen to an image.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
-- Parameter: width = the width of the image
-- Parameter: height = the height of the image
-- Returns: a table with the image data
function CCGraphics.captureRegion(win, x, y, width, height)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if x + width > win.screenBuffer.termWidth or y + height > win.screenBuffer.termHeight then error("region out of bounds", 2) end
    local captureTable = {}
    captureTable.width = width * 2
    captureTable.height = height * 3
    captureTable.termWidth = width
    captureTable.termHeight = height
    for px=x,x+width-1 do
        captureTable[px-x] = {}
        for py=y,height-1 do captureTable[px-x][py-y] = win.screenBuffer[px][py] end
    end
    return captureTable
end

-- Draws a previously captured image onto screen at a position.
-- Parameter: win = the win to control
-- Parameter: x = the x location on screen
-- Parameter: y = the y location on screen
-- Parameter: image = a table with the image data
function CCGraphics.drawCapture(win, x, y, image)
    if not win.graphicsInitialized then error("graphics not initialized", 2) end
    if image.width == nil or image.height == nil or image.termWidth == nil or image.termHeight == nil then error("invalid image", 2) end
    if x + image.termWidth > win.screenBuffer.termWidth or y + image.termHeight > win.screenBuffer.termHeight then error("region out of bounds", 2) end
    for px=x,x+image.termWidth-1 do for py=y,y+image.termHeight-1 do 
        --print(px .. " " .. py)
        if image[px-x] == nil then error("no row at " .. px-x) end
        if image[px-x][py-y] == nil then error("no data at " .. px-x .. ", " .. py-y, 2) end
        win.screenBuffer[px][py] = image[px-x][py-y]
    end end
    CCGraphics.redrawScreen(win)
end

-- Resizes the window.
-- Parameter: win = the win to control
-- Parameter: width = the new width (in term chars)
-- Parameter: height = the new height (in term chars)
function CCGraphics.resizeWindow(win, width, height)
    win.screenBuffer.width = width * 2
    win.screenBuffer.height = height * 3
    win.screenBuffer.termWidth = width
    win.screenBuffer.termHeight = height
    for x=0,width-1 do
        if win.screenBuffer[x] == nil then win.screenBuffer[x] = {} end
        for y=0,height-1 do
            --print("creating pixel " .. x .. ", " .. y)
            if win.screenBuffer[x][y] == nil then
                win.screenBuffer[x][y] = {}
                win.screenBuffer[x][y].fgColor = colors.white -- Text color
                win.screenBuffer[x][y].bgColor = colors.black -- Background color
                win.screenBuffer[x][y].pixelCode = 0 -- Stores the data as a 6-bit integer (tl, tr, cl, cr, bl, br)
                win.screenBuffer[x][y].useCharacter = false -- Whether to print a custom character
                win.screenBuffer[x][y].character = " " -- Custom character
            end
        end
    end
end

-- CCWindowRegistry.lua
-- CCKit
--
-- This file creates functions that provide ray-casting for mouse clicks so that
-- only the top-most window recieves actions.
--
-- Copyright (c) 2018 JackMacWindows.

CCWindowRegistry = {}

if _G.windowRegistry == nil then 
    _G.windowRegistry = {}
    _G.windowRegistry.zPos = {}
end

function CCWindowRegistry.registerApplication(appname)
    _G.windowRegistry[appname] = {}
    _G.windowRegistry.zPos[table.maxn(_G.windowRegistry.zPos)+1] = appname
end

function CCWindowRegistry.registerWindow(win)
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    table.insert(_G.windowRegistry[win.application.name], {name=win.name, x=win.frame.x, y=win.frame.y, width=win.frame.width, height=win.frame.height})
end

function CCWindowRegistry.deregisterApplication(appname)
    _G.windowRegistry[appname] = nil
    for k,v in pairs(_G.windowRegistry.zPos) do if v == appname then
        table.remove(_G.windowRegistry.zPos, k)
        break
    end end
end

function CCWindowRegistry.deregisterWindow(win)
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then return end
    for k,v in pairs(_G.windowRegistry[win.application.name]) do if v.name == win.name then
        table.remove(_G.windowRegistry[win.application.name], k)
        break
    end end
end

function CCWindowRegistry.setAppZ(appname, z)
    local n = 0
    for k,v in pairs(_G.windowRegistry.zPos) do if v == appname then n = k end end
    if n == 0 then error("Couldn't find application " .. appname, 2) end
    table.insert(_G.windowRegistry.zPos, z, table.remove(_G.windowRegistry.zPos, n))
end

function CCWindowRegistry.setAppTop(appname) CCWindowRegistry.setAppZ(appname, table.maxn(_G.windowRegistry.zPos)) end

function CCWindowRegistry.setWinZ(win, z)
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    local n = 0
    for k,v in pairs(_G.windowRegistry[win.application.name]) do if v.name == win.name then n = k end end
    if n == 0 then error("Couldn't find window " .. win.name, 2) end
    table.insert(_G.windowRegistry[win.application.name], z, table.remove(_G.windowRegistry[win.application.name], n))
end

function CCWindowRegistry.setWinTop(win) 
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    CCWindowRegistry.setWinZ(win, table.maxn(_G.windowRegistry[win.application.name]))
end

function CCWindowRegistry.moveWin(win, x, y)
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    for k,v in pairs(_G.windowRegistry[win.application.name]) do if v.name == win.name then
        v.x = x
        v.y = y
        break
    end end
end

function CCWindowRegistry.resizeWin(win, x, y)
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    for k,v in pairs(_G.windowRegistry[win.application.name]) do if v.name == win.name then
        v.width = x
        v.height = y
        break
    end end
end

function CCWindowRegistry.isAppOnTop(appname) return _G.windowRegistry.zPos[table.maxn(_G.windowRegistry.zPos)] == appname end 

function CCWindowRegistry.isWinOnTop(win) 
    if win.application == nil then error("Window does not have application", 2) end
    if _G.windowRegistry[win.application.name] == nil then error("Application " .. win.application.name .. " is not registered", 2) end
    return _G.windowRegistry[win.application.name][table.maxn(_G.windowRegistry[win.application.name])].name == win.name
end

function CCWindowRegistry.hitTest(win, px, py)
    return win and win.frame and not (px < win.frame.x or py < win.frame.y or px >= win.frame.x + win.frame.width or py >= win.frame.y + win.frame.height)
end

function CCWindowRegistry.getAppZ(appname)
    for k,v in pairs(_G.windowRegistry.zPos) do if v == appname then return k end end
    return -1
end

function CCWindowRegistry.rayTest(win, px, py)
    return CCWindowRegistry.hitTest(win, px, py) --[[
    if win.application == nil or _G.windowRegistry[win.application.name] == nil or win.frame == nil or px == nil or py == nil then return false end
    -- If the click isn't on the window then of course it didn't hit
    if px < win.frame.x or py < win.frame.y or px >= win.frame.x + win.frame.width or py >= win.frame.y + win.frame.height then return false end
    -- If the app and window are both on top, then it hit
    if isAppOnTop(win.application.name) and isWinOnTop(win) then return true
    -- If the app is not on top, check if this window is the uppermost window in the position
    else
        -- Get the highest window at the point for each app
        local wins = {}
        for k,v in pairs(_G.windowRegistry) do if k ~= "zPos" then
            wins[k] = {}
            wins[k].z = -1
            for l,w in pairs(v) do if hitTest(w, px, py) and l > wins[k].z then wins[k] = {win=w,app=k,z=l} end end
        end end
        -- Get the highest window of the highest app at the point
        local finalwin = nil
        for k,v in pairs(wins) do if finalwin == nil or getAppZ(v.app) > getAppZ(finalwin.app) then finalwin = v end end
        -- Check if win is the highest window
        return finalwin.win.name == win.name
    end]]
end

-- CCEventHandler.lua
-- CCKit
--
-- This file defines an interface named CCEventHandler that CCApplication uses
-- to handle events.
--
-- Copyright (c) 2018 JackMacWindows.

local charset = {}

-- qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890
for i = 48,  57 do table.insert(charset, string.char(i)) end
for i = 65,  90 do table.insert(charset, string.char(i)) end
for i = 97, 122 do table.insert(charset, string.char(i)) end

function string.random(length)
  --math.randomseed(os.clock())

  if length > 0 then
    return string.random(length - 1) .. charset[math.random(1, #charset)]
  else
    return ""
  end
end

function CCEventHandler(class)
    local retval = {}
    retval.name = string.random(8)
    retval.class = class
    retval.events = {}
    retval.hasEvents = true -- for CCView compatibility
    function retval:addEvent(name, func)
        self.events[name] = {}
        self.events[name].func = func
        self.events[name].self = self.name
    end
    return retval
end

-- CCApplication.lua
-- CCKit
--
-- This file creates the CCApplication, which manages the program's run loop.
--
-- Copyright (c) 2018 JackMacWindows.

local colorString = "0123456789abcdef"

local function cp(color)
    local recurses = 1
    local cc = color
    while cc ~= 1 do 
        cc = bit.brshift(cc, 1)
        recurses = recurses + 1
    end
    --print(recurses .. " " .. color .. " \"" .. string.sub(colorString, recurses, recurses) .. "\"")
    return string.sub(colorString, recurses, recurses)
end

local function drawFilledBox(x, y, endx, endy, color) for px=x,x+endx-1 do for py=y,y+endy-1 do 
    term.setCursorPos(px, py)
    term.blit(" ", "0", cp(color)) 
end end end

local charset = {}

-- qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890
for i = 48,  57 do table.insert(charset, string.char(i)) end
for i = 65,  90 do table.insert(charset, string.char(i)) end
for i = 97, 122 do table.insert(charset, string.char(i)) end

function string.random(length)
  --math.randomseed(os.clock())

  if length > 0 then
    return string.random(length - 1) .. charset[math.random(1, #charset)]
  else
    return ""
  end
end

function CCApplication(name)
    local retval = {}
    term.setBackgroundColor(colors.black)
    retval.name = string.random(8)
    retval.class = "CCApplication"
    retval.objects = {count = 0}
    retval.events = {}
    retval.isApplicationRunning = false
    retval.backgroundColor = colors.black
    retval.objectOrder = {}
    retval.applicationName = name
    retval.showName = false
    if name ~= nil then retval.log = CCLog(name)
    else retval.log = CCLog.default end
    CCLog.default.logToConsole = false
    retval.log:open()
    function retval:setBackgroundColor(color)
        self.backgroundColor = color
        term.setBackgroundColor(color)
        term.clear()
        for k,v in pairs(self.objects) do if k ~= "count" and v.class == "CCWindow" then v:redraw() end end
    end
    function retval:registerObject(win, name, up) -- adds the events in the object to the run loop
        --if win.class ~= "CCWindow" then error("tried to register non-CCWindow type " .. win.class, 2) end
        if win == nil then 
            self.log:error("win is nil") 
            return
        end
        if up == nil then up = true end
        if win.repaintColor ~= nil then win.repaintColor = self.backgroundColor end
        self.objects[name] = win
        table.insert(self.objectOrder, name)
        if up then self.objects.count = self.objects.count + 1 end
        --print("added to " .. name)
        --local i = 0
        --print(textutils.serialize(win.events))
        for k,v in pairs(win.events) do
            if self.events[k] == nil then self.events[k] = {} end
            table.insert(self.events[k], v)
            --print("added event " .. k)
            --i=i+1
        end
        --print(textutils.serialize(self.events))
        --print(i)
    end
    function retval:deregisterObject(name)
        self.objects[name] = nil
        local remove = {}
        for k,v in pairs(self.events) do for l,w in pairs(v) do if w.self == name then table.insert(remove, {f = k, s = l}) end end end
        for a,b in pairs(remove) do self.events[b.f][b.s] = nil end
    end
    function retval:runLoop()
        --print("starting loop")
        self.log:open()
        if _G.windowRegistry[self.name] == nil then CCWindowRegistry.registerApplication(self.name) end
        if CCKernel ~= nil then CCKernel.broadcast("redraw_all", self.name, true) end
        while self.isApplicationRunning do
            --print("looking for event")
            if self.objects.count == 0 then break end
            if self.showName then
                term.setBackgroundColor(self.backgroundColor)
                term.setTextColor(colors.white)
                term.setCursorPos(1, 1)
                term.write(self.applicationName)
            end
            local ev, p1, p2, p3, p4, p5 = os.pullEvent()
            --print("recieved event " .. ev)
            if ev == "closed_window" then
                if self.objects[p1] == nil or self.objects[p1].class ~= "CCWindow" then 
                    self.log:error("Missing window for " .. p1, "CCApplication")
                else
                    drawFilledBox(self.objects[p1].frame.x, self.objects[p1].frame.y, self.objects[p1].frame.width, self.objects[p1].frame.height, self.backgroundColor)
                    CCWindowRegistry.setAppTop(self.name)
                    CCWindowRegistry.deregisterWindow(self.objects[p1])
                    if CCKernel ~= nil then CCKernel.broadcast("redraw_all", self.name) end
                    self.objects[p1] = nil
                    self.objects.count = self.objects.count - 1
                    if self.objects.count == 0 then break end
                    local remove = {}
                    for k,v in pairs(self.events) do for l,w in pairs(v) do if w.self == p1 then table.insert(remove, {f = k, s = l}) end end end
                    for a,b in pairs(remove) do self.events[b.f][b.s] = nil end
                    for k,v in pairs(self.objectOrder) do if self.objects[v] ~= nil and self.objects[v].class == "CCWindow" and self.objects[v].window ~= nil then self.objects[v].window.redraw() end end 
                end
            elseif ev == "redraw_window" then
                if self.objects[p1] ~= nil and self.objects[p1].redraw ~= nil then self.objects[p1]:redraw() end
            elseif ev == "redraw_all" then
                if p1 ~= self.name then for k,v in pairs(self.objectOrder) do if self.objects[v] ~= nil and self.objects[v].class == "CCWindow" and self.objects[v].window ~= nil then self.objects[v]:redraw(false) end end
                elseif p2 == true then CCWindowRegistry.setAppTop(self.name) end
            end
            local didEvent = false
            local redraws = {}
            for k,v in pairs(self.events) do if ev == k then 
                --print("got event " .. ev)
                --print(textutils.serialize(v))
                for l,w in pairs(v) do 
                    if self.objects[w.self] == nil then 
                        self.log:debug(textutils.serialize(w))
                        self.log:error("Could not find object for " .. tostring(w.self), "CCApplication")
                    else
                        if w.func(self.objects[w.self], p1, p2, p3, p4, p5) then 
                            redraws[w.self] = true
                            didEvent = true
                            break 
                        end
                    end
                end 
            end end
            if didEvent then for k,v in pairs(self.objectOrder) do if self.objects[v] ~= nil and self.objects[v].class == "CCWindow" and self.objects[v].window ~= nil then self.objects[v].window.redraw() end end end
        end
        --print("ending loop")
        self.log:close()
        CCWindowRegistry.deregisterApplication(self.name)
        coroutine.yield()
    end
    function retval:startRunLoop()
        self.coro = coroutine.create(self.runLoop)
        self.isApplicationRunning = true
        coroutine.resume(self.coro, self)
    end
    function retval:stopRunLoop()
        self.isApplicationRunning = false
    end
    CCWindowRegistry.registerApplication(retval.name)
    return retval
end

-- CCWindow.lua
-- CCKit
--
-- This file creates the CCWindow class, which handles the actions required
-- for a window to be displayed on screen.
--
-- Copyright (c) 2018 JackMacWindows.

-- Constants for the colors of the window

local charset = {}

-- qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890
for i = 48,  57 do table.insert(charset, string.char(i)) end
for i = 65,  90 do table.insert(charset, string.char(i)) end
for i = 97, 122 do table.insert(charset, string.char(i)) end

function string.random(length)
  --math.randomseed(os.clock())

  if length > 0 then
    return string.random(length - 1) .. charset[math.random(1, #charset)]
  else
    return ""
  end
end

function CCWindow(x, y, width, height)
    local retval = CCEventHandler("CCWindow")
    retval.window = window.create(term.native(), x, y, width, height)
    retval.title = ""
    retval.frame = {}
    retval.frame.x = x
    retval.frame.y = y
    retval.frame.width = width
    retval.frame.height = height
    retval.defaultFrame = {}
    retval.defaultFrame.x = retval.frame.x
    retval.defaultFrame.y = retval.frame.y
    retval.defaultFrame.width = retval.frame.width
    retval.defaultFrame.height = retval.frame.height
    retval.viewController = nil
    retval.isDragging = false
    retval.mouseOffset = 0
    retval.repaintColor = colors.black
    retval.application = nil
    retval.closing = false
    retval.maximized = false
    retval.maximizable = true
    retval.showTitleBar = true
    function retval:redraw(setapp)
        if setapp == nil then setapp = true end
        if not self.closing then
            self.window.setCursorBlink(false)
            if self.showTitleBar then
                CCGraphics.drawLine(retval.window, 0, 0, self.frame.width-1, false, CCKitGlobals.titleBarColor, CCKitGlobals.titleBarTextColor)
                CCGraphics.setPixelColors(retval.window, self.frame.width-1, 0, colors.white, colors.red)
                CCGraphics.setCharacter(retval.window, self.frame.width-1, 0, "X")
                if self.maximizable then
                    CCGraphics.setPixelColors(retval.window, self.frame.width-2, 0, colors.white, colors.lime)
                    if self.maximized then CCGraphics.setCharacter(retval.window, self.frame.width-2, 0, "o")
                    else CCGraphics.setCharacter(retval.window, self.frame.width-2, 0, "O") end
                end
            else
                CCGraphics.drawLine(retval.window, 0, 0, self.frame.width, false, CCKitGlobals.windowBackgroundColor)
            end
            CCGraphics.drawBox(retval.window, 0, 1, self.frame.width, self.frame.height - 1, CCKitGlobals.windowBackgroundColor)
            self:setTitle(self.title)
            if self.viewController ~= nil then self.viewController.view:draw() end
            if self.application ~= nil and setapp then 
                CCWindowRegistry.setAppTop(self.application.name)
                if not CCWindowRegistry.isAppOnTop(self.application.name) then error("Not on top!") end
            end
        end
    end
    function retval:moveToPos(button, px, py)
        --print("moving")
        if button == 1 and self.isDragging then
            if not CCWindowRegistry.isWinOnTop(self) or not CCWindowRegistry.isAppOnTop(self.application.name) then 
                self:redraw() 
                CCWindowRegistry.setAppTop(self.application.name)
                CCWindowRegistry.setWinTop(self)
            end
            CCGraphics.drawFilledBox(self.frame.x, self.frame.y, self.frame.x + self.frame.width, self.frame.y + self.frame.height, self.repaintColor)
            if CCKernel ~= nil then 
                CCKernel.broadcast("redraw_all", self.application.name)
                os.queueEvent("done_redraw")
                os.pullEvent("done_redraw")
            end
            CCWindowRegistry.moveWin(self, px - self.mouseOffset, py)
            self.window.reposition(px - self.mouseOffset, py)
            if self.viewController ~= nil then self.viewController.view:updateAbsolutes(px - self.frame.x - self.mouseOffset, py - self.frame.y) end
            --CCGraphics.redrawScreen(self.window)
            --self:redraw()
            self.frame.x = px - self.mouseOffset
            self.frame.y = py
            --if not CCKitGlobals.liveWindowMove then paintutils.drawBox(self.frame.x, self.frame.y, self.frame.x + self.frame.width - 1, self.frame.y + self.frame.height - 1, CCKitGlobals.windowBackgroundColor) end
            return true
        end
        return false
    end
    function retval:startDrag(button, px, py)
        if not CCWindowRegistry.rayTest(self, px, py) then return false end
        if button == 1 then
            if not CCWindowRegistry.isWinOnTop(self) or not CCWindowRegistry.isAppOnTop(self.application.name) then 
                self:redraw() 
                CCWindowRegistry.setAppTop(self.application.name)
                CCWindowRegistry.setWinTop(self)
            end
            if py == self.frame.y and px >= self.frame.x and px < self.frame.x + self.frame.width - 2 then 
                self.isDragging = true 
                self.mouseOffset = px - self.frame.x
                self.window.setVisible(CCKitGlobals.liveWindowMove)
                return true
            elseif py == self.frame.y and px == self.frame.x + self.frame.width - 2 and self.maximizable then
                if self.maximized then
                    self.frame.x = self.defaultFrame.x
                    self.frame.y = self.defaultFrame.y
                    self.frame.width = self.defaultFrame.width
                    self.frame.height = self.defaultFrame.height
                    self.maximized = false
                    self:resize(self.frame.width, self.frame.height)
                    self.application:setBackgroundColor(self.application.backgroundColor)
                else
                    self.defaultFrame.x = self.frame.x
                    self.defaultFrame.y = self.frame.y
                    self.defaultFrame.width = self.frame.width
                    self.defaultFrame.height = self.frame.height
                    self.frame.x = 1
                    self.frame.y = 1
                    self.maximized = true
                    self:resize(term.native().getSize())
                end
                self.application.log:debug(tostring(self.defaultFrame.width))
                return true
            elseif py == self.frame.y and px == self.frame.x + self.frame.width - 1 then
                CCGraphics.endGraphics(self.window)
                self.window = nil
                self.closing = true
                if self.viewController ~= nil then for k,v in pairs(self.viewController.view.subviews) do
                    self.viewController.view:deregisterSubview(v)
                end end
                os.queueEvent("closed_window", self.name)
                return true
            end
        end
        return false
    end
    function retval:stopDrag(button, px, py)
        --if not CCWindowRegistry.rayTest(self, px, py) then return false end
        if button == 1 and self.isDragging then 
            if not CCWindowRegistry.isWinOnTop(self) or not CCWindowRegistry.isAppOnTop(self.application.name) then 
                self:redraw() 
                CCWindowRegistry.setAppTop(self.application.name)
                CCWindowRegistry.setWinTop(self)
            end
            self:moveToPos(button, px, py) 
            self.isDragging = false
            self.window.setVisible(true)
            return true
        end
        return false
    end
    function retval:scroll(direction, px, py)
        if CCWindowRegistry.rayTest(self, px, py) and (not CCWindowRegistry.isWinOnTop(self) or not CCWindowRegistry.isAppOnTop(self.application.name)) then 
            self:redraw() 
            CCWindowRegistry.setAppTop(self.application.name)
            CCWindowRegistry.setWinTop(self)
        end
        return false
    end
    function retval:resize(newWidth, newHeight)
        self.frame.width = newWidth
        self.frame.height = newHeight
        self.window.reposition(self.frame.x, self.frame.y, self.frame.width, self.frame.height)
        CCGraphics.resizeWindow(self.window, newWidth, newHeight)
        CCWindowRegistry.resizeWin(self, newWidth, newHeight)
        self:redraw()
    end
    function retval:setTitle(str)
        self.title = str
        CCGraphics.setString(self.window, math.floor((self.frame.width - string.len(str)) / 2), 0, str)
    end
    function retval:setViewController(vc, app)
        self.application = app
        if self.viewController == nil then CCWindowRegistry.registerWindow(self) end
        self.viewController = vc
        self.viewController:loadView(self, self.application)
        self.viewController:viewDidLoad()
        self.viewController.view:draw()
        self:redraw()
    end
    function retval:registerObject(obj)
        if self.application ~= nil then
            self.application:registerObject(obj, obj.name, false)
        end
    end
    function retval:close()
        if self.viewController ~= nil then self.viewController:dismiss() end
        os.queueEvent("closed_window", self.name)
    end
    function retval:present(newwin)
        newwin:redraw()
        self.application:registerObject(newwin, newwin.name)
    end
    retval:addEvent("mouse_drag", retval.moveToPos)
    retval:addEvent("mouse_click", retval.startDrag)
    retval:addEvent("mouse_up", retval.stopDrag)
    retval:addEvent("mouse_scroll", retval.scroll)
    CCGraphics.initGraphics(retval.window)
    retval:redraw()
    return retval
end

-- CCView.lua
-- CCKit
--
-- This file creates the CCView class, which handles initializing, drawing,
-- and displaying information inside a CCWindow.
--
-- Copyright (c) 2018 JackMacWindows.

function CCView(x, y, width, height)
    local retval = {}
    retval.class = "CCView"
    retval.parentWindowName = nil
    retval.parentWindow = nil
    retval.application = nil
    retval.window = nil
    retval.hasEvents = false
    retval.events = {}
    retval.subviews = {}
    retval.backgroundColor = colors.white
    retval.frame = {x = x, y = y, width = width, height = height, absoluteX = x, absoluteY = y}
    function retval:setBackgroundColor(color)
        self.backgroundColor = color
        self:draw()
    end
    function retval:draw()
        if self.parentWindow ~= nil then
            CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, self.backgroundColor)
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:addSubview(view)
        if self.application == nil then error("Parent view must be added before subviews", 2) end
        if view == nil then self.application.log:error("Cannot add nil subview", 2) end
        if view.hasEvents then self.application:registerObject(view, view.name, false) end
        view:setParent(self.window, self.application, self.parentWindowName, self.frame.absoluteX, self.frame.absoluteY)
        table.insert(self.subviews, view)
    end
    function retval:setParent(parent, application, name, absoluteX, absoluteY)
        self.parentWindow = parent
        self.parentWindowName = name
        self.application = application
        self.frame.absoluteX = absoluteX + self.frame.x
        self.frame.absoluteY = absoluteY + self.frame.y
        self.window = window.create(self.parentWindow, self.frame.x+1, self.frame.y+1, self.frame.width, self.frame.height)
        CCGraphics.initGraphics(self.window)
    end
    function retval:updateAbsolutes(addX, addY)
        --print(addX .. ", " .. addY)
        self.frame.absoluteX = self.frame.absoluteX + addX
        self.frame.absoluteY = self.frame.absoluteY + addY
        for k,view in pairs(self.subviews) do view:updateAbsolutes(addX, addY) end
    end
    function retval:deregisterSubview(view)
        if view.hasEvents and self.application ~= nil then
            self.application:deregisterObject(view.name)
            for k,v in pairs(view.subviews) do view:deregisterSubview(v) end
        end
    end
    return retval
end

-- CCViewController.lua
-- CCKit
--
-- This file creates the CCViewController class, which is used in a CCWindow
-- to control the window contents. This can be subclassed to create custom
-- controllers for your application.
--
-- Copyright (c) 2018 JackMacWindows.

function CCViewController()
    local retval = {}
    retval.view = {}
    retval.window = nil
    retval.application = nil
    function retval:loadView(win, app)
        --print("loaded view " .. win.name)
        self.window = win
        self.application = app
        local width, height = win.window.getSize()
        if self.window.showTitleBar then self.view = CCView(0, 1, width, height - 1)
        else self.view = CCView(0, 0, width, height) end
        self.view:setParent(self.window.window, self.application, self.window.name, self.window.frame.x, self.window.frame.y)
    end
    retval.superLoadView = retval.loadView
    function retval:viewDidLoad()
        -- override this to create custom subviews
    end
    function retval:dismiss()
        if self.view.subviews ~= nil then
            for k,v in pairs(self.view.subviews) do self.view:deregisterSubview(v) end
        end
    end
    return retval
end

-- CCControl.lua
-- CCKit
--
-- This file defines the CCControl class, which is a base class for all controls.
-- Controls can be interacted with and show content relating to the program
-- state and any interactions done with the view.
--
-- Copyright (c) 2018 JackMacWindows.

function CCControl(x, y, width, height)
    local retval = multipleInheritance(CCView(x, y, width, height), CCEventHandler("CCControl"))
    retval.hasEvents = true
    retval.isEnabled = true
    retval.isSelected = false
    retval.isHighlighted = false
    retval.action = nil
    retval.actionObject = nil
    function retval:setAction(func, obj)
        self.action = func
        self.actionObject = obj
    end
    function retval:setHighlighted(h)
        self.isHighlighted = h
        self:draw()
    end
    function retval:setEnabled(e)
        self.isEnabled = e
        self:draw()
    end
    function retval:onMouseDown(button, px, py)
        if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        local bx = self.frame.absoluteX
        local by = self.frame.absoluteY
        if px >= bx and py >= by and px < bx + self.frame.width and py < by + self.frame.height and button == 1 and self.action ~= nil and self.isEnabled then 
            self.isSelected = true
            self:draw()
            return true
        end
        return false
    end
    function retval:onMouseUp(button, px, py)
        --if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        if self.isSelected and button == 1 then 
            self.isSelected = false
            self:draw()
            self.action(self.actionObject)
            return true
        end
        return false
    end
    function retval:onKeyDown(key, held)
        if self.isHighlighted and key == keys.enter and self.isEnabled then 
            self.isSelected = true
            self:draw()
            return true
        end
        return false
    end
    function retval:onKeyUp(key)
        if self.isHighlighted and self.isSelected and key == keys.enter and self.isEnabled then
            self.isSelected = false
            self:draw()
            self.action(self.actionObject)
            return true
        end
        return false
    end
    retval:addEvent("key", retval.onKeyDown)
    retval:addEvent("key_up", retval.onKeyUp)
    retval:addEvent("mouse_click", retval.onMouseDown)
    retval:addEvent("mouse_up", retval.onMouseUp)
    return retval
end

-- CCLabel.lua
-- CCKit
--
-- This is a subclass of CCView that displays text on screen.
--
-- Copyright (c) 2018 JackMacWindows.

function CCLabel(x, y, text)
    local retval = CCView(x, y, string.len(text), 1)
    retval.text = text
    retval.textColor = colors.black
    function retval:draw()
        if self.parentWindow ~= nil then
            for px=0,self.frame.width-1 do CCGraphics.setPixelColors(self.window, px, 0, self.textColor, self.backgroundColor) end
            CCGraphics.setString(self.window, 0, 0, self.text)
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    return retval
end

-- CCButton.lua
-- CCKit
--
-- This file creates a subclass of CCView called CCButton, which allows a user
-- to click and start an action.
--
-- Copyright (c) 2018 JackMacWindows.

function CCButton(x, y, width, height)
    local retval = CCControl(x, y, width, height)
    retval.textColor = CCKitGlobals.defaultTextColor
    retval.text = nil
    retval.backgroundColor = CCKitGlobals.buttonColor
    function retval:draw()
        if self.parentWindow ~= nil then
            local textColor
            local backgroundColor
            if self.isHighlighted and self.isSelected then backgroundColor = CCKitGlobals.buttonHighlightedSelectedColor
            elseif self.isHighlighted then backgroundColor = CCKitGlobals.buttonHighlightedColor
            elseif self.isSelected then backgroundColor = CCKitGlobals.buttonSelectedColor
            elseif not self.isEnabled then backgroundColor = CCKitGlobals.buttonDisabledColor
            else backgroundColor = self.backgroundColor end
            if self.isEnabled then textColor = self.textColor else textColor = CCKitGlobals.buttonDisabledTextColor end
            CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, backgroundColor, textColor)
            if retval.text ~= nil then CCGraphics.setString(self.window, math.floor((self.frame.width - string.len(self.text)) / 2), math.floor((self.frame.height - 1) / 2), self.text) end
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:setText(text)
        self.text = text
        self:draw()
    end
    function retval:setTextColor(color)
        self.textColor = color
        self:draw()
    end
    return retval
end

-- CCImageView.lua
-- CCKit
--
-- This file creates the CCImageView class, which inherits from CCView and
-- draws a CCGraphics image into the view.
--
-- Copyright (c) 2018 JackMacWindows.

function CCImageView(x, y, image)
    local retval = CCView(x, y, image.termWidth, image.termHeight)
    retval.image = image
    function retval:draw()
        if self.parentWindow ~= nil then
            CCGraphics.drawCapture(self.window, 0, 0, self.image)
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    return retval
end

-- CCProgressBar.lua
-- CCKit
--
-- This creates a subclass of CCView called CCProgressBar, which displays a
-- bar showing progress.
--
-- Copyright (c) 2018 JackMacWindows.

function CCProgressBar(x, y, width)
    local retval = CCView(x, y, width, 1)
    retval.backgroundColor = colors.lightGray
    retval.foregroundColor = colors.yellow
    retval.progress = 0.0
    retval.indeterminate = false
    function retval:draw()
        if self.parentWindow ~= nil then
            if self.indeterminate then
                local i = 0
                while i < self.frame.width do
                    local c = self.backgroundColor
                    if i / 2 == 0.0 then c = self.foregroundColor end
                    CCGraphics.setPixelColors(self.window, i, 0, nil, c)
                    i=i+1
                end
            else
                CCGraphics.drawLine(self.window, 0, 0, self.frame.width, false, self.backgroundColor)
                CCGraphics.drawLine(self.window, 0, 0, math.floor(self.frame.width * self.progress), false, self.foregroundColor)
            end
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:setProgress(progress)
        if progress > 1 then progress = 1 end
        self.progress = progress
        self:draw()
    end
    function retval:setIndeterminate(id)
        self.indeterminate = id
        self:draw()
    end
    return retval
end

-- CCCheckbox.lua
-- CCKit
--
-- This file creates the CCCheckbox class, which provides a binary toggleable
-- button for selecting states.
--
-- Copyright (c) 2018 JackMacWindows.

function CCCheckbox(x, y, text)
    local size = 1
    if type(text) == "string" then size = string.len(text) + 2 end
    local retval = CCControl(x, y, size, 1)
    retval.isOn = false
    retval.text = text
    retval.textColor = CCKitGlobals.defaultTextColor
    retval.backgroundColor = CCKitGlobals.buttonColor
    function retval:setOn(value)
        self.isOn = value
        self:draw()
    end
    function retval:setTextColor(color)
        self.textColor = color
        self:draw()
    end
    function retval:draw()
        if self.parentWindow ~= nil then
            local textColor
            local backgroundColor
            if self.isOn and self.isSelected then backgroundColor = CCKitGlobals.buttonHighlightedSelectedColor
            elseif self.isOn then backgroundColor = CCKitGlobals.buttonHighlightedColor
            elseif self.isSelected then backgroundColor = CCKitGlobals.buttonSelectedColor
            elseif not self.isEnabled then backgroundColor = CCKitGlobals.buttonDisabledColor
            else backgroundColor = self.backgroundColor end
            if self.isEnabled then textColor = self.textColor else textColor = CCKitGlobals.buttonDisabledTextColor end
            CCGraphics.drawBox(self.window, 0, 0, 1, 1, backgroundColor, textColor)
            if retval.isOn then CCGraphics.setCharacter(self.window, 0, 0, "x")
            else CCGraphics.clearCharacter(self.window, 0, 0) end
            if retval.text ~= nil then 
                CCGraphics.drawBox(self.window, 1, 0, string.len(self.text) + 1, 1, CCKitGlobals.windowBackgroundColor, textColor)
                CCGraphics.setString(self.window, 2, 0, self.text)
            end
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:action()
        self:setOn(not self.isOn)
        os.queueEvent("checkbox_toggled", self.name, self.isOn)
    end
    retval:setAction(retval.action, retval)
    return retval
end

-- CCTextField.lua
-- CCKit
--
-- This file creates the CCTextField class, which allows the user to type text.
--
-- Copyright (c) 2018 JackMacWindows.

function CCTextField(x, y, width)
    local retval = multipleInheritance(CCView(x, y, width, 1), CCEventHandler("CCTextField"))
    retval.text = ""
    retval.isSelected = false
    retval.isEnabled = true
    retval.cursorOffset = 0 -- later
    retval.backgroundColor = colors.lightGray
    retval.textColor = CCKitGlobals.defaultTextColor
    retval.placeholderText = nil
    retval.textReplacement = nil
    function retval:setTextColor(color)
        self.textColor = color
        self:draw()
    end
    function retval:setEnabled(e)
        self.isEnabled = e
        self:draw()
    end
    function retval:setPlaceholder(text)
        self.placeholderText = text
        self:draw()
    end
    function retval:draw()
        if self.parentWindow ~= nil then
            CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, self.backgroundColor, self.textColor)
            local text = self.text
            if string.len(text) >= self.frame.width then text = string.sub(text, string.len(text)-self.frame.width+2)
            elseif string.len(text) == 0 and self.placeholderText ~= nil and not self.isSelected then
                text = self.placeholderText
                CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, self.backgroundColor, colors.gray)
            end
            if self.isSelected then text = text .. "_" end
            CCGraphics.setString(self.window, 0, 0, (self.textReplacement and text ~= self.placeholderText) and string.rep(string.sub(self.textReplacement, 1, 1), string.len(text) - 1) .. (self.isSelected and "_" or "") or text)
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:onClick(button, px, py)
        if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        if button == 1 then
            self.isSelected = px >= self.frame.absoluteX and py == self.frame.absoluteY and px < self.frame.absoluteX + self.frame.width and self.isEnabled
            self:draw()
            return self.isSelected
        end
        return false
    end
    function retval:onKey(key, held)
        if key == keys.backspace and self.isSelected and self.isEnabled then
            self.text = string.sub(self.text, 1, string.len(self.text)-1)
            self:draw()
            return true
        end
        return false
    end
    function retval:onChar(ch)
        if self.isSelected and self.isEnabled then
            self.text = self.text .. ch
            self:draw()
            return true
        end
        return false
    end
    retval:addEvent("mouse_click", retval.onClick)
    retval:addEvent("key", retval.onKey)
    retval:addEvent("char", retval.onChar)
    return retval
end

-- CCScrollView.lua
-- CCKit
--
-- This creates the CCScrollView class, which is used to display subviews
-- that would otherwise be too tall for the area.
--
-- Copyright (c) 2018 JackMacWindows.

local function CCScrollBar(x, y, height) -- may make this public later
    local retval = CCControl(x, y, 1, height)
    retval.class = "CCScrollBar"
    retval.buttonColor = CCKitGlobals.buttonColor
    retval.sliderValue = 0
    function retval:setValue(value)
        self.sliderValue = value
        self:draw()
    end
    function retval:onMouseDown(button, px, py)
        if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        local bx = self.frame.absoluteX
        local by = self.frame.absoluteY
        if px >= bx and py >= by and px < bx + self.frame.width and py < by + self.frame.height and button == 1 and self.isEnabled then 
            self.isSelected = true
            self:onDrag(button, px, py)
            return true
        end
        return false
    end
    function retval:onDrag(button, px, py)
        --if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        if self.isSelected and button == 1 then
            if py < self.frame.absoluteY then self.sliderValue = 0
            elseif py > self.frame.absoluteY + self.frame.height - 1 then self.sliderValue = self.frame.height - 1
            else self.sliderValue = py - self.frame.absoluteY end
            self:draw()
            os.queueEvent("slider_dragged", self.name, self.sliderValue)
            return true
        end
        return false
    end
    function retval:draw()
        if self.parentWindow ~= nil then
            CCGraphics.drawLine(self.window, 0, 0, self.frame.height, true, self.backgroundColor)
            if self.isSelected then CCGraphics.setPixelColors(self.window, 0, self.sliderValue, CCKitGlobals.buttonSelectedColor, CCKitGlobals.buttonSelectedColor)
            else CCGraphics.setPixelColors(self.window, 0, self.sliderValue, self.buttonColor, self.buttonColor) end
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    retval:setAction(function() return end, self)
    retval:addEvent("mouse_click", retval.onMouseDown)
    retval:addEvent("mouse_drag", retval.onDrag)
    return retval
end

local function getWindowCapture(view)
    local image = CCGraphics.captureRegion(view.window, 0, 0, view.frame.width, view.frame.height)
    for k,v in pairs(view.subviews) do
        local subimage = getWindowCapture(v)
        for x,r in pairs(subimage) do if type(x) ~= "string" then 
            if image[x+v.frame.x] == nil then image[x+v.frame.x] = {} end
            for y,p in pairs(r) do image[x+v.frame.x][y+v.frame.y] = p end 
        end end
    end
    return image
end

local function resizeImage(image, x, y, width, height, default)
    local retval = {width = width * 2, height = height * 3, termWidth = width, termHeight = height}
    for px=0,width-1 do
        if retval[px] == nil then retval[px] = {} end
        for py=0,height-1 do
            --print("creating pixel " .. x .. ", " .. y)
            if retval[px][py] == nil then
                retval[px][py] = {}
                retval[px][py].fgColor = default -- Text color
                retval[px][py].bgColor = default -- Background color
                retval[px][py].pixelCode = 0 -- Stores the data as a 6-bit integer (tl, tr, cl, cr, bl, br)
                retval[px][py].useCharacter = false -- Whether to print a custom character
                retval[px][py].character = " " -- Custom character
            end
        end
    end
    for dx,r in pairs(image) do if type(dx) ~= "string" then 
        if retval[dx-x] == nil then retval[dx-x] = {} end
        for dy,p in pairs(r) do retval[dx-x][dy-y] = p end
    end end
    return retval
end

function math.round(num) if num % 1 < 0.5 then return math.floor(num) else return math.ceil(num) end end

function CCScrollView(x, y, width, height, innerHeight)
    local retval = multipleInheritance(CCView(x, y, width, height), CCEventHandler("CCScrollView"))
    retval.contentHeight = innerHeight
    retval.currentOffset = 0
    retval.renderWindow = window.create(term.native(), 1, 1, width-1, innerHeight, false)
    retval.scrollBar = CCScrollBar(width-1, 0, height)
    retval.lastAbsolute = 0
    CCGraphics.initGraphics(retval.renderWindow)
    function retval:draw() -- won't work with any views that don't use CCGraphics (please use CCGraphics)
        if self.parentWindow ~= nil then
            self.scrollBar.sliderValue = math.round(self.currentOffset * (self.frame.height / (self.contentHeight - self.frame.height + 1)))
            CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, self.backgroundColor)
            --self.renderWindow.setVisible(true)
            CCGraphics.drawBox(self.renderWindow, 0, 0, self.frame.width-1, self.contentHeight, self.backgroundColor)
            local image = CCGraphics.captureRegion(self.renderWindow, 0, 0, self.frame.width-1, self.contentHeight)
            for k,v in pairs(self.subviews) do 
                v:updateAbsolutes(0, (self.frame.absoluteY - self.currentOffset) - self.lastAbsolute)
                v:draw()
                if v.class ~= "CCScrollBar" then
                    local subimage = getWindowCapture(v)
                    for x,r in pairs(subimage) do if type(x) ~= "string" then 
                        if image[x+v.frame.x] == nil then image[x+v.frame.x] = {} end
                        for y,p in pairs(r) do image[x+v.frame.x][y+v.frame.y] = p end 
                    end end
                end
            end
            image = resizeImage(image, 0, self.currentOffset, self.frame.width-1, self.frame.height, self.backgroundColor)
            --self.application.log:debug(textutils.serialize(image))
            CCGraphics.drawCapture(self.window, 0, 0, image)
            self.scrollBar:draw()
            self.lastAbsolute = self.frame.absoluteY - self.currentOffset
            --self.renderWindow.setVisible(false)
        end
    end
    function retval:scroll(direction, px, py)
        if not CCWindowRegistry.rayTest(self.application.objects[self.parentWindowName], px, py) then return false end
        if px >= self.frame.absoluteX and py >= self.frame.absoluteY and px < self.frame.absoluteX + self.frame.width and py < self.frame.absoluteY + self.frame.height and self.currentOffset + direction <= self.contentHeight - self.frame.height and self.currentOffset + direction >= 0 then
            self.currentOffset = self.currentOffset + direction
            self:draw()
            return true
        end
        return false
    end
    function retval:addSubview(view)
        if self.application == nil then error("Parent view must be added before subviews", 2) end
        if view == nil then self.application.log:error("Cannot add nil subview", 2) end
        if view.hasEvents then self.application:registerObject(view, view.name, false) end
        if view.class == "CCScrollBar" then view:setParent(self.window, self.application, self.parentWindowName, self.frame.absoluteX, self.frame.absoluteY)
        else view:setParent(self.renderWindow, self.application, self.parentWindowName, self.frame.absoluteX, self.frame.absoluteY - self.currentOffset) end
        table.insert(self.subviews, view)
    end
    function retval:setParent(parent, application, name, absoluteX, absoluteY)
        self.parentWindow = parent
        self.parentWindowName = name
        self.application = application
        self.frame.absoluteX = absoluteX + self.frame.x
        self.frame.absoluteY = absoluteY + self.frame.y
        self.lastAbsolute = self.frame.absoluteY - self.currentOffset
        self.window = window.create(self.parentWindow, self.frame.x+1, self.frame.y+1, self.frame.width, self.frame.height)
        CCGraphics.initGraphics(self.window)
        self:addSubview(self.scrollBar)
    end
    function retval:didScroll(name, value)
        self.application.log:debug("Slider dragged")
        if name == self.scrollBar.name then
            self.currentOffset = math.round(((self.contentHeight - self.frame.height + 1) / self.frame.height) * value)
            self:draw()
            return true
        end
        return false
    end
    retval:addEvent("mouse_scroll", retval.scroll)
    retval:addEvent("slider_dragged", retval.didScroll)
    return retval
end

-- CCLineBreakMode.lua
-- CCKit
--
-- This sets constants that define how text should be wrapped in a CCTextView.
--
-- Copyright (c) 2018 JackMacWindows.

CCLineBreakMode = {}
CCLineBreakMode.byWordWrapping = 1
CCLineBreakMode.byCharWrapping = 2
CCLineBreakMode.byClipping = 4
CCLineBreakMode.byTruncatingHead = 8

function string.split(str, tok)
    words = {}
    for word in str:gmatch(tok) do table.insert(words, word) end
    return words
end

function table.count(tab)
    local i = 0
    for k,v in pairs(tab) do i = i + 1 end
    return i
end

function CCLineBreakMode.divideText(text, width, mode)
    local retval = {}
    if bit.band(mode, CCLineBreakMode.byCharWrapping) == CCLineBreakMode.byCharWrapping then
        for i=1,string.len(text),width do table.insert(retval, string.sub(text, i, i + width)) end
    elseif bit.band(mode, CCLineBreakMode.byClipping) == CCLineBreakMode.byClipping then
        local lines = string.split(text, "\n")
        for k,line in pairs(lines) do table.insert(retval, string.sub(line, 1, width)) end
    else
        local words = string.split(text, "[%w%p\n]+")
        local line = ""
        for k,word in pairs(words) do
            if string.len(line) + string.len(word) >= width then
                table.insert(retval, line)
                line = ""
            end
            line = line .. word .. " "
            if string.find(line, "\n") then
                local nextLine = string.sub(line, 1, string.find(line, "\n") - 1, nil)
                if string.len(nextLine) > width then error("wtf2: " .. nextLine) end
                table.insert(retval, nextLine)
                line = string.sub(line, string.find(line, "\n") + 1, nil)
                if string.len(line) >= width then error("wtf: " .. line) end
            end
        end
        table.insert(retval, line)
    end
    return retval
end

-- CCTextView.lua
-- CCKit
--
-- This creates a subclass of CCView that displays multi-line text.
--
-- Copyright (c) 2018 JackMacWindows.

function CCTextView(x, y, width, height)
    local retval = CCView(x, y, width, height)
    retval.textColor = CCKitGlobals.defaultTextColor
    retval.text = ""
    retval.lineBreakMode = CCLineBreakMode.byWordWrapping
    function retval:draw()
        if self.parentWindow ~= nil then
            CCGraphics.drawBox(self.window, 0, 0, self.frame.width, self.frame.height, self.backgroundColor, self.textColor)
            local lines = CCLineBreakMode.divideText(self.text, self.frame.width, self.lineBreakMode)
            --print(textutils.serialize(lines))
            if table.count(lines) > self.frame.height then
                local newlines = {}
                if bit.band(self.lineBreakMode, CCLineBreakMode.byTruncatingHead) then
                    for i=table.count(lines)-self.frame.height,table.count(lines) do table.insert(newlines, lines[i]) end
                else
                    for i=1,table.count(lines) do table.insert(newlines, lines[i]) end
                end
                lines = newlines
            end
            for k,v in pairs(lines) do CCGraphics.setString(self.window, 0, k-1, v) end
            for k,v in pairs(self.subviews) do v:draw() end
        end
    end
    function retval:setText(text)
        self.text = text
        self:draw()
    end
    function retval:setTextColor(color)
        self.textColor = color
        self:draw()
    end
    function retval:setLineBreakMode(mode)
        self.lineBreakMode = mode
        self:draw()
    end
    return retval
end

-- CCAlertWindow.lua
-- CCKit
--
-- This file creates the CCAlertWindow class, which provides a way to show alert
-- dialogs to the user.
--
-- Copyright (c) 2018 JackMacWindows.

local function AlertViewController(w, h, text)
    local retval = CCViewController()
    retval.button2 = CCButton((w-4)/2, h-3, 4, 1)
    retval.text = text
    retval.w = w
    retval.h = h
    function retval:viewDidLoad()
        local label = CCTextView(1, 1, self.w-2, self.h-2)
        label:setText(self.text)
        self.view:addSubview(label)
        self.button2:setText("OK")
        self.button2:setAction(self.window.close, self.window)
        self.button2:setHighlighted(true)
        self.view:addSubview(self.button2)
    end
    return retval
end

function CCAlertWindow(x, y, width, height, title, message, application)
    local retval = CCWindow(x, y, width, height)
    retval.maximizable = false
    retval:setTitle(title)
    local newvc = AlertViewController(width, height, message)
    retval:setViewController(newvc, application)
    return retval
end

-- CCKit.lua
-- CCKit
--
-- The main CCKit include. Renames all classes to be part of itself.
--
-- Copyright (c) 2018 JackMacWindows.

function CCMain(initX, initY, initWidth, initHeight, title, vcClass, backgroundColor, appName, showName)
    backgroundColor = backgroundColor or colors.black
    local name = title
    if appName ~= nil then name = appName end
    local app = CCApplication(name)
    app:setBackgroundColor(backgroundColor)
    app.showName = showName or false
    local win = CCWindow(initX, initY, initWidth, initHeight)
    win:setTitle(title)
    local vc = vcClass()
    win:setViewController(vc, app)
    app:registerObject(win, win.name)
    app.isApplicationRunning = true
    term.setCursorBlink(false)
    local ok, err = pcall(function() app:runLoop() end)
    CCWindowRegistry.deregisterApplication(app.name)
    if not ok then
        printError(err)
        return
    end
    while table.maxn(_G.windowRegistry.zPos) > 0 do coroutine.yield() end
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setCursorBlink(true)
end
