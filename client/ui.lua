local utf8 = require("utf8")

local UI = {}

local widgets = {}
local activeWidget = nil

UI.osk = {
    isVisible = false,
    mode = "ALPHA", 
    isShift = false,
    keys = {} -- To store rendered key bounds for clicking
}

local oskLayouts = {
    ALPHA = {
        {"q","w","e","r","t","y","u","i","o","p"},
        {"a","s","d","f","g","h","j","k","l"},
        {"SHIFT","z","x","c","v","b","n","m","BACKSPACE"},
        {"123", "SPACE", "ENTER"}
    },
    NUM = {
        {"1","2","3","4","5","6","7","8","9","0"},
        {"-","/",":",";","(",")","$","&","@","\""},
        {"ABC", ".", ",", "?", "!", "'", "BACKSPACE"},
        {"SPACE", "ENTER"}
    }
}

function UI.load()
    UI.font = love.graphics.newFont(20)
end

function UI.clear()
    widgets = {}
    activeWidget = nil
end

function UI.addButton(id, text, x, y, w, h, onClick)
    table.insert(widgets, {
        type = "button",
        id = id,
        text = text,
        x = x, y = y, w = w, h = h,
        onClick = onClick,
        isHovered = false
    })
end

function UI.addLabel(id, text, x, y)
    table.insert(widgets, {
        type = "label",
        id = id,
        text = text,
        x = x, y = y
    })
end

function UI.addTextInput(id, placeholder, x, y, w, h)
    table.insert(widgets, {
        type = "textinput",
        id = id,
        text = "",
        placeholder = placeholder,
        x = x, y = y, w = w, h = h,
        focused = false
    })
end

function UI.setText(id, text)
    for _, w in ipairs(widgets) do
        if w.id == id then
            w.text = text
            break
        end
    end
end

function UI.getText(id)
    for _, w in ipairs(widgets) do
        if w.id == id then return w.text end
    end
    return nil
end

function UI.showKeyboard(widget)
    UI.osk.isVisible = true
    UI.osk.targetWidget = widget
end

function UI.hideKeyboard()
    UI.osk.isVisible = false
    UI.osk.targetWidget = nil
    for _, w in ipairs(widgets) do
        if w.type == "textinput" then w.focused = false end
    end
end

function UI.update(dt)
    local mx, my = love.mouse.getPosition()
    for _, w in ipairs(widgets) do
        if w.type == "button" or w.type == "textinput" then
            w.isHovered = mx >= w.x and mx <= w.x + w.w and my >= w.y and my <= w.y + w.h
            if w.isHovered then
                love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
                activeWidget = w
            end
        end
    end
    if not activeWidget or not activeWidget.isHovered then
        love.mouse.setCursor()
        activeWidget = nil
    end
end

function UI.draw()
    love.graphics.setFont(UI.font)
    for _, w in ipairs(widgets) do
        if w.type == "button" then
            -- Drop shadow
            love.graphics.setColor(0, 0, 0, 0.3)
            love.graphics.rectangle("fill", w.x + 2, w.y + 4, w.w, w.h, 8, 8)
            
            if w.isHovered then
                love.graphics.setColor(0.35, 0.65, 0.95, 1)
            else
                love.graphics.setColor(0.2, 0.45, 0.8, 1)
            end
            love.graphics.rectangle("fill", w.x, w.y, w.w, w.h, 8, 8)
            
            -- Inner highlight
            love.graphics.setColor(1, 1, 1, 0.1)
            love.graphics.rectangle("fill", w.x, w.y, w.w, w.h / 2, 8, 8)
            
            love.graphics.setColor(1, 1, 1, 1)
            local tw = UI.font:getWidth(w.text)
            local th = UI.font:getHeight()
            love.graphics.print(w.text, w.x + w.w/2 - tw/2, w.y + w.h/2 - th/2)
        elseif w.type == "label" then
            love.graphics.setColor(0, 0, 0, 0.5)
            love.graphics.print(w.text, w.x + 2, w.y + 2)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(w.text, w.x, w.y)
        elseif w.type == "textinput" then
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.rectangle("fill", w.x + 2, w.y + 2, w.w, w.h, 6, 6)
            
            love.graphics.setColor(0.95, 0.95, 0.98, 1)
            love.graphics.rectangle("fill", w.x, w.y, w.w, w.h, 6, 6)
            
            if w.focused then
                love.graphics.setColor(0.3, 0.6, 0.9, 0.5)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", w.x, w.y, w.w, w.h, 6, 6)
            end
            
            love.graphics.setColor(0.1, 0.1, 0.1, 1)
            local txt = w.text
            if txt == "" and not w.focused then
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                txt = w.placeholder
            end
            local th = UI.font:getHeight()
            local tw = UI.font:getWidth(txt)
            local tx = w.x + 10
            
            if tw > w.w - 20 then
                tx = w.x + w.w - 10 - tw
            end
            
            love.graphics.print(txt, tx, w.y + w.h/2 - th/2)
        end
    end
    
    if UI.osk.isVisible then
        UI.drawKeyboard()
    end
end

function UI.drawKeyboard()
    local kw = _G.getW()
    local numRows = #oskLayouts[UI.osk.mode]
    local keyH = 50
    local padding = 10
    local kh = (numRows * (keyH + padding)) + padding
    local kx = 0
    local ky = _G.getH() - kh
    
    love.graphics.setColor(0.1, 0.1, 0.15, 0.95)
    love.graphics.rectangle("fill", kx, ky, kw, kh)
    
    UI.osk.keys = {}
    
    for r, row in ipairs(oskLayouts[UI.osk.mode]) do
        local rowW = 0
        local specialWidths = { SPACE = 200, SHIFT = 100, BACKSPACE = 120, ENTER = 120, ["123"] = 100, ["ABC"] = 100 }
        
        for _, k in ipairs(row) do
            rowW = rowW + (specialWidths[k] or 50) + padding
        end
        rowW = rowW - padding
        
        local currentX = (kw - rowW) / 2
        local currentY = ky + padding + ((r - 1) * (keyH + padding))
        
        for _, k in ipairs(row) do
            local bw = specialWidths[k] or 50
            local bh = keyH
            
            local dText = k
            if UI.osk.mode == "ALPHA" and UI.osk.isShift and #k == 1 then
                dText = string.upper(k)
            end
            
            table.insert(UI.osk.keys, { x = currentX, y = currentY, w = bw, h = bh, key = k, dText = dText })
            
            love.graphics.setColor(0.25, 0.25, 0.35, 0.5)
            love.graphics.rectangle("fill", currentX, currentY, bw, bh, 6, 6)
            love.graphics.setColor(1, 1, 1, 1)
            local tw = UI.font:getWidth(dText)
            local th = UI.font:getHeight()
            love.graphics.print(dText, currentX + bw/2 - tw/2, currentY + bh/2 - th/2)
            
            currentX = currentX + bw + padding
        end
    end
end

function UI.mousepressed(x, y, button)
    if button == 1 then
        if UI.osk.isVisible then
            for _, k in ipairs(UI.osk.keys) do
                if x >= k.x and x <= k.x + k.w and y >= k.y and y <= k.y + k.h then
                    UI.handleKeyboardPress(k)
                    return -- Consume click
                end
            end
        end
    
        local clickedInput = false
        for _, w in ipairs(widgets) do
            if w.type == "textinput" then
                if x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h then
                    w.focused = true
                    clickedInput = true
                    UI.showKeyboard(w)
                else
                    w.focused = false
                end
            elseif w.type == "button" then
                if x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h then
                    if w.onClick then w.onClick() end
                end
            end
        end
        if not clickedInput and UI.osk.isVisible and y < _G.getH() - 250 then
            -- click outside keyboard hiding zone
            UI.hideKeyboard()
        end
    end
end

function UI.handleKeyboardPress(kDef)
    local k = kDef.key
    local tgt = UI.osk.targetWidget
    if not tgt then return end
    
    if k == "SHIFT" then
        UI.osk.isShift = not UI.osk.isShift
    elseif k == "123" then
        UI.osk.mode = "NUM"
        UI.osk.isShift = false
    elseif k == "ABC" then
        UI.osk.mode = "ALPHA"
        UI.osk.isShift = false
    elseif k == "BACKSPACE" then
        local byteoffset = utf8.offset(tgt.text, -1)
        if byteoffset then
            tgt.text = string.sub(tgt.text, 1, byteoffset - 1)
        end
    elseif k == "SPACE" then
        tgt.text = tgt.text .. " "
    elseif k == "ENTER" then
        UI.hideKeyboard()
    else
        tgt.text = tgt.text .. kDef.dText
        -- Reset shift after typing 1 char
        if UI.osk.isShift then UI.osk.isShift = false end
    end
end

function UI.textinput(t)
    for _, w in ipairs(widgets) do
        if w.type == "textinput" and w.focused then
            w.text = w.text .. t
        end
    end
end

function UI.keypressed(key)
    local isCtrlOrCmd = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    
    for _, w in ipairs(widgets) do
        if w.type == "textinput" and w.focused then
            if key == "backspace" then
                local byteoffset = utf8.offset(w.text, -1)
                if byteoffset then
                    w.text = string.sub(w.text, 1, byteoffset - 1)
                end
            elseif isCtrlOrCmd and key == "v" then
                local clipboardText = love.system.getClipboardText()
                if clipboardText and #clipboardText > 0 then
                    -- Sanitize simple newlines possibly
                    clipboardText = clipboardText:gsub("\r", ""):gsub("\n", "")
                    w.text = w.text .. clipboardText
                end
            end
        end
    end
end

return UI
