local utf8 = require("utf8")

local UI = {}

local widgets = {}
local activeWidget = nil

UI.osk = {
    isVisible = false,
    mode = "ALPHA", 
    isShift = false,
    keys = {}, -- To store rendered key bounds for clicking
    pressedKey = nil, -- Currently pressed key for visual feedback
    pressTimer = 0    -- Timer for press animation
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
        isHovered = false,
        scale = 1.0
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
    UI.osk.pressedKey = nil
end

function UI.hideKeyboard()
    UI.osk.isVisible = false
    UI.osk.targetWidget = nil
    UI.osk.pressedKey = nil
    for _, w in ipairs(widgets) do
        if w.type == "textinput" then w.focused = false end
    end
end

function UI.update(dt)
    UI.time = (UI.time or 0) + dt
    
    -- Update keyboard press animation
    if UI.osk.pressedKey then
        UI.osk.pressTimer = UI.osk.pressTimer + dt
        if UI.osk.pressTimer > 0.15 then -- Animation duration
            UI.osk.pressedKey = nil
            UI.osk.pressTimer = 0
        end
    end
    
    local mx, my = love.mouse.getPosition()
    for _, w in ipairs(widgets) do
        if w.type == "button" or w.type == "textinput" then
            w.isHovered = mx >= w.x and mx <= w.x + w.w and my >= w.y and my <= w.y + w.h
            if w.isHovered then
                love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
                activeWidget = w
            end
        end
        if w.type == "button" then
            if w.isHovered then
                w.scale = w.scale + (1.05 - w.scale) * dt * 10
            else
                w.scale = w.scale + (1.0 - w.scale) * dt * 10
            end
        end
    end
    if not activeWidget or not activeWidget.isHovered then
        love.mouse.setCursor()
        activeWidget = nil
    end
end

-- Helper function to draw centered text with proper alignment
local function drawCenteredText(text, x, y, maxW, maxH, isHovered, fontSize)
    local font = UI.font
    local th = font:getHeight()
    local tw = font:getWidth(text)
    
    -- Calculate vertical center
    local textY = y + (maxH / 2) - (th / 2)
    
    -- Check if text fits within max width
    if tw <= maxW then
        -- Center horizontally
        local textX = x + (maxW / 2) - (tw / 2)
        love.graphics.print(text, textX, textY)
    else
        -- Text needs scrolling or truncation
        if isHovered and UI.time then
            -- Marquee scroll effect
            local scrollSpeed = 60
            local scrollW = tw - maxW + 20
            local offset = (UI.time * scrollSpeed) % (scrollW * 2)
            if offset > scrollW then offset = scrollW * 2 - offset end
            
            -- Use stencil for clipping
            local stencilFunc = function()
                love.graphics.rectangle("fill", x, y, maxW, maxH)
            end
            love.graphics.stencil(stencilFunc, "replace", 1)
            love.graphics.setStencilTest("greater", 0)
            love.graphics.print(text, x - offset, textY)
            love.graphics.setStencilTest()
        else
            -- Truncate with ellipsis
            local currentText = ""
            local ellipsis = "..."
            local ellW = font:getWidth(ellipsis)
            
            for i = 1, utf8.len(text) do
                local charStart = utf8.offset(text, i)
                local charEnd = utf8.offset(text, i + 1)
                local char = string.sub(text, charStart, charEnd and charEnd - 1 or #text)
                local testText = currentText .. char
                
                if font:getWidth(testText) + ellW > maxW then
                    break
                end
                currentText = testText
            end
            
            local displayText = currentText .. ellipsis
            local displayW = font:getWidth(displayText)
            local textX = x + (maxW / 2) - (displayW / 2)
            love.graphics.print(displayText, textX, textY)
        end
    end
end

-- Helper for labels (left-aligned by default, but can be centered)
local function drawLabelText(text, x, y, align)
    local font = UI.font
    local th = font:getHeight()
    
    if align == "center" then
        local tw = font:getWidth(text)
        love.graphics.print(text, x - tw/2, y)
    elseif align == "right" then
        local tw = font:getWidth(text)
        love.graphics.print(text, x - tw, y)
    else
        -- left align (default)
        love.graphics.print(text, x, y)
    end
end

function UI.draw()
    love.graphics.setFont(UI.font)
    
    for _, w in ipairs(widgets) do
        if w.type == "button" then
            local sw = w.w * w.scale
            local sh = w.h * w.scale
            local sx = w.x - (sw - w.w) / 2
            local sy = w.y - (sh - w.h) / 2
            
            -- Drop shadow
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.rectangle("fill", sx + 3, sy + 5, sw, sh, 10, 10)
            
            -- Button background
            if w.isHovered then
                love.graphics.setColor(0.35, 0.75, 1.0, 1)
            else
                love.graphics.setColor(0.2, 0.5, 0.85, 1)
            end
            love.graphics.rectangle("fill", sx, sy, sw, sh, 10, 10)
            
            -- Inner gradient highlight
            love.graphics.setColor(1, 1, 1, 0.15)
            love.graphics.rectangle("fill", sx, sy, sw, sh / 2, 10, 10)
            
            -- Button text
            love.graphics.setColor(1, 1, 1, 1)
            drawCenteredText(w.text, sx, sy, sw, sh, w.isHovered)
            
        elseif w.type == "label" then
            -- Shadow
            love.graphics.setColor(0, 0, 0, 0.5)
            drawLabelText(w.text, w.x + 2, w.y + 2, "left")
            
            -- Main text
            love.graphics.setColor(1, 1, 1, 1)
            drawLabelText(w.text, w.x, w.y, "left")
            
        elseif w.type == "textinput" then
            -- Shadow
            love.graphics.setColor(0, 0, 0, 0.2)
            love.graphics.rectangle("fill", w.x + 2, w.y + 2, w.w, w.h, 8, 8)
            
            -- Background
            love.graphics.setColor(0.95, 0.95, 0.98, 1)
            love.graphics.rectangle("fill", w.x, w.y, w.w, w.h, 8, 8)
            
            -- Focus highlight
            if w.focused then
                love.graphics.setColor(0.3, 0.7, 1.0, 0.6)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", w.x, w.y, w.w, w.h, 8, 8)
            end
            
            -- Text content
            local txt = w.text
            local isPlaceholder = false
            
            if txt == "" and not w.focused then
                love.graphics.setColor(0.5, 0.5, 0.5, 1)
                txt = w.placeholder
                isPlaceholder = true
            else
                love.graphics.setColor(0.1, 0.1, 0.1, 1)
            end
            
            -- Center text vertically in input
            local th = UI.font:getHeight()
            local textY = w.y + (w.h / 2) - (th / 2)
            
            -- Handle text overflow with scrolling when focused
            if w.focused and UI.font:getWidth(txt) > w.w - 20 then
                -- Simple scrolling effect for long text
                local scrollOffset = 0
                if UI.time then
                    local textWidth = UI.font:getWidth(txt)
                    scrollOffset = (UI.time * 30) % (textWidth + w.w)
                    if scrollOffset > textWidth then
                        scrollOffset = textWidth
                    end
                end
                love.graphics.print(txt, w.x + 10 - scrollOffset, textY)
            else
                love.graphics.print(txt, w.x + 10, textY)
            end
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
        local specialWidths = { SPACE = 200, SHIFT = 100, BACKSPACE = 140, ENTER = 120, ["123"] = 100, ["ABC"] = 100 }
        
        for _, k in ipairs(row) do
            rowW = rowW + (specialWidths[k] or 55) + padding
        end
        rowW = rowW - padding
        
        local currentX = (kw - rowW) / 2
        local currentY = ky + padding + ((r - 1) * (keyH + padding))
        
        for _, k in ipairs(row) do
            local bw = specialWidths[k] or 55
            local bh = keyH
            
            local dText = k
            if UI.osk.mode == "ALPHA" and UI.osk.isShift and #k == 1 then
                dText = string.upper(k)
            end
            
            -- Store key info for click detection
            local keyInfo = { x = currentX, y = currentY, w = bw, h = bh, key = k, dText = dText }
            table.insert(UI.osk.keys, keyInfo)
            
            -- Check if this key is currently pressed
            local isPressed = UI.osk.pressedKey and 
                             UI.osk.pressedKey.x == currentX and 
                             UI.osk.pressedKey.y == currentY
            
            -- Calculate press animation scale and offset
            local pressScale = 1.0
            local pressOffsetX = 0
            local pressOffsetY = 0
            if isPressed then
                local t = UI.osk.pressTimer / 0.15 -- 0 to 1
                -- Squash and stretch effect
                pressScale = 1 - (t * 0.1) -- Shrink slightly
                pressOffsetX = (bw * (1 - pressScale)) / 2
                pressOffsetY = (bh * (1 - pressScale)) / 2
            end
            
            local drawX = currentX + pressOffsetX
            local drawY = currentY + pressOffsetY
            local drawW = bw * pressScale
            local drawH = bh * pressScale
            
            -- Key background with press effect
            if isPressed then
                love.graphics.setColor(0.5, 0.6, 0.8, 0.9) -- Lighter when pressed
            elseif keyInfo.isHovered then
                love.graphics.setColor(0.35, 0.35, 0.5, 0.9)
            else
                love.graphics.setColor(0.25, 0.25, 0.35, 0.8)
            end
            love.graphics.rectangle("fill", drawX, drawY, drawW, drawH, 6, 6)
            
            -- Key text with press animation (slight downward movement)
            love.graphics.setColor(1, 1, 1, 1)
            local tw = UI.font:getWidth(dText)
            local th = UI.font:getHeight()
            local textX = drawX + drawW/2 - tw/2
            local textY = drawY + drawH/2 - th/2
            
            if isPressed then
                textY = textY + 2 -- Move text down slightly when pressed
            end
            
            love.graphics.print(dText, textX, textY)
            
            currentX = currentX + bw + padding
        end
    end
end

function UI.mousepressed(x, y, button)
    if button == 1 then
        if UI.osk.isVisible then
            -- Check keyboard keys first
            for _, k in ipairs(UI.osk.keys) do
                if x >= k.x and x <= k.x + k.w and y >= k.y and y <= k.y + k.h then
                    -- Set pressed key for visual feedback
                    UI.osk.pressedKey = k
                    UI.osk.pressTimer = 0
                    UI.handleKeyboardPress(k)
                    return
                end
            end
        end
    
        local clickedInput = false
        -- Iterate in reverse order so top widgets get priority
        for i = #widgets, 1, -1 do
            local w = widgets[i]
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
                    -- Add button press effect
                    local originalScale = w.scale
                    w.scale = 0.95
                    -- Reset scale after a short delay
                    local timer = 0
                    local function resetScale()
                        timer = timer + (1/60)
                        if timer >= 0.1 then
                            w.scale = originalScale
                        else
                            love.timer.sleep(0.01)
                            resetScale()
                        end
                    end
                    resetScale()
                    
                    if w.onClick then w.onClick() end
                    return
                end
            end
        end
        if not clickedInput and UI.osk.isVisible and y < _G.getH() - 250 then
            UI.hideKeyboard()
        end
    end
end

function UI.handleKeyboardPress(kDef)
    local k = kDef.key
    local tgt = UI.osk.targetWidget
    if not tgt then return end
    
    -- Play a subtle sound effect if available (optional)
    -- if love.audio and love.audio.newSource then
    --     local beep = love.audio.newSource("assets/click.wav", "static")
    --     beep:play()
    -- end
    
    if k == "SHIFT" then
        UI.osk.isShift = not UI.osk.isShift
        -- Visual feedback for shift (optional)
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
            elseif key == "return" or key == "kpenter" then
                UI.hideKeyboard()
            elseif isCtrlOrCmd and key == "v" then
                local clipboardText = love.system.getClipboardText()
                if clipboardText and #clipboardText > 0 then
                    clipboardText = clipboardText:gsub("\r", ""):gsub("\n", "")
                    w.text = w.text .. clipboardText
                end
            elseif key == "tab" then
                -- Cycle through text inputs
                local inputs = {}
                for _, w2 in ipairs(widgets) do
                    if w2.type == "textinput" then
                        table.insert(inputs, w2)
                    end
                end
                for i, w2 in ipairs(inputs) do
                    if w2.focused then
                        w2.focused = false
                        local nextIdx = i % #inputs + 1
                        inputs[nextIdx].focused = true
                        UI.showKeyboard(inputs[nextIdx])
                        break
                    end
                end
            end
        end
    end
end

-- Optional: Add a function to play keyboard sounds
function UI.setKeyboardSound(soundPath)
    UI.keyboardSound = love.audio.newSource(soundPath, "static")
end

return UI