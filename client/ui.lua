local utf8 = require("utf8")

local UI = {}

local widgets = {}
local activeWidget = nil

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
end

function UI.mousepressed(x, y, button)
    if button == 1 then
        for _, w in ipairs(widgets) do
            if w.type == "textinput" then
                w.focused = (x >= w.x and x <= w.x + w.w and y >= w.y and y <= w.y + w.h)
            end
        end
        if activeWidget and activeWidget.isHovered and activeWidget.onClick then
            activeWidget.onClick()
        end
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
