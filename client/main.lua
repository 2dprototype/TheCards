local UI = require("ui")
local Network = require("network")
local GameLogic = require("game_logic")
local Bot = require("bot")
local Config = require("config")

_G.SCREEN_WIDTH = 700
_G.SCREEN_HEIGHT = 480

-- App States: 
-- "MENU": Main Menu
-- "LOBBY": Host Lobby / Creating
-- "JOIN": Join input code
-- "SETTINGS": Network settings
-- "GAME": In game
 local backgroundImage = nil
local appState = "MENU"
local errorMessage = nil
_G.inPauseMenu = false

_G.getW = function() return 1000 end
_G.getH = function() return 650 end

local orig_mouse_pos = love.mouse.getPosition
local function getScaleOffsets()
    local w, h = love.graphics.getDimensions()
    local scale = math.min(w / _G.getW(), h / _G.getH())
    local ox = (w - (_G.getW() * scale)) / 2
    local oy = (h - (_G.getH() * scale)) / 2
    return scale, ox, oy
end

love.mouse.getPosition = function()
    local x, y = orig_mouse_pos()
    local scale, ox, oy = getScaleOffsets()
    return (x - ox) / scale, (y - oy) / scale
end

function love.load(args)
    love.window.setMode(_G.SCREEN_WIDTH, _G.SCREEN_HEIGHT, {resizable=true, vsync=true, minwidth=700, minheight=400})
    love.window.setTitle("Devil Bridge")
    love.keyboard.setTextInput(true)
    love.keyboard.setKeyRepeat(true)
    
   

    backgroundImage = love.graphics.newImage("assets/g.jpg")
    backgroundImage:setWrap("repeat", "repeat")
    backgroundImage:setFilter("linear", "linear")
    
    love.graphics.setDefaultFilter("linear", "linear")
    love.keyboard.setKeyRepeat(true)
    
    UI.load()
    Network.load()
    GameLogic.load()
    Config.load()
    
    -- Parse CLI arguments
    if args then
        for i, v in ipairs(args) do
            if v == "--server-uri" and args[i+1] then
                Config.set("server_uri", args[i+1])
            end
        end
    end
    
    -- Setup basic UI for MENU
    setupMenuUI()
end

function love.resize(w, h)
    -- Re-layout UI based on current state
    if appState == "MENU" then setupMenuUI()
    elseif appState == "LOBBY" then setupLobbyUI()
    elseif appState == "JOIN" then setupJoinUI()
    elseif appState == "SETTINGS" then setupSettingsUI()
    elseif appState == "LOBBY_GUEST" then setupGuestLobbyUI()
    elseif appState == "GAME" then 
        if _G.inPauseMenu then setupPauseUI() 
        elseif GameLogic.phase == "MATCH_OVER" then _G.setupMatchOverUI()
        else setupGameUI() end
    end
end

function setupMenuUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addTextInput("input_name", "Enter Username", cx - 100, cy - 170, 200, 40)
    if _G.globalUsername == nil and Config.get("username") ~= "" then
        _G.globalUsername = Config.get("username")
    end
    if _G.globalUsername then UI.setText("input_name", _G.globalUsername) end
    UI.addButton("btn_host", "Host Online", cx - 100, cy - 100, 200, 50, function()
        local name = UI.getText("input_name")
        if not name or name == "" then name = "Host" end
        _G.globalUsername = name
        Config.set("username", name)
        Network.connectAsHost(name)
        appState = "LOBBY"
        setupLobbyUI()
    end)
    UI.addButton("btn_join", "Join Online", cx - 100, cy - 20, 200, 50, function()
        local name = UI.getText("input_name")
        if not name or name == "" then name = "Player" .. math.random(100, 999) end
        _G.globalUsername = name
        Config.set("username", name)
        appState = "JOIN"
        setupJoinUI()
    end)
    UI.addButton("btn_offline", "Play Offline", cx - 100, cy + 60, 200, 50, function()
        local name = UI.getText("input_name")
        if not name or name == "" then name = "You" end
        _G.globalUsername = name
        Config.set("username", name)
        GameLogic.totalRounds = _G.matchRounds or 5
        GameLogic.maxTurnTime = _G.matchTurnTime or 15
        GameLogic.startOfflineGame()
        appState = "GAME"
        setupGameUI()
    end)
    UI.addButton("btn_settings", "Settings", cx - 100, cy + 140, 200, 50, function()
        local name = UI.getText("input_name")
        if name and name ~= "" then
            _G.globalUsername = name
            Config.set("username", name)
        end
        appState = "SETTINGS"
        setupSettingsUI()
    end)
end

function setupSettingsUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addLabel("lbl_settings", "Network Settings", cx - 70, cy - 170)
    
    UI.addLabel("lbl_uri_hint", "Server URI (tcp://, udp://, ws://, wss://)", cx - 250, cy - 110)
    UI.addTextInput("input_uri", "e.g. wss://127.0.0.1:8080", cx - 250, cy - 80, 500, 40)
    UI.setText("input_uri", Config.get("server_uri") or "")
    
    UI.addButton("btn_save_settings", "Save & Back", cx - 100, cy + 80, 200, 50, function()
        local uri = UI.getText("input_uri")
        if uri and #uri > 0 then
            Config.set("server_uri", uri)
        end
        appState = "MENU"
        setupMenuUI()
    end)
end

function setupLobbyUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addLabel("lbl_lobby", "Setting up Lobby...", cx - 100, cy - 180)
    
    if not _G.matchRounds then _G.matchRounds = 5 end
    if not _G.matchTurnTime then _G.matchTurnTime = 15 end

    -- Rounds Option
    UI.addLabel("lbl_rounds", "Rounds: " .. _G.matchRounds, cx - 60, cy - 100)
    UI.addButton("btn_rounds_minus", "-", cx - 120, cy - 110, 40, 40, function()
        if _G.matchRounds > 1 then 
            _G.matchRounds = _G.matchRounds - 1 
            UI.setText("lbl_rounds", "Rounds: " .. _G.matchRounds)
        end
    end)
    UI.addButton("btn_rounds_plus", "+", cx + 80, cy - 110, 40, 40, function()
        if _G.matchRounds < 20 then 
            _G.matchRounds = _G.matchRounds + 1 
            UI.setText("lbl_rounds", "Rounds: " .. _G.matchRounds)
        end
    end)

    -- Turn Time Option
    UI.addLabel("lbl_time", "Timer: " .. _G.matchTurnTime .. "s", cx - 60, cy - 40)
    UI.addButton("btn_time_minus", "-", cx - 120, cy - 50, 40, 40, function()
        if _G.matchTurnTime > 5 then 
            _G.matchTurnTime = _G.matchTurnTime - 5 
            UI.setText("lbl_time", "Timer: " .. _G.matchTurnTime .. "s")
        end
    end)
    UI.addButton("btn_time_plus", "+", cx + 80, cy - 50, 40, 40, function()
        if _G.matchTurnTime < 60 then 
            _G.matchTurnTime = _G.matchTurnTime + 5 
            UI.setText("lbl_time", "Timer: " .. _G.matchTurnTime .. "s")
        end
    end)
    -- Deck Pack Option
    local packName = GameLogic.deckPacks[GameLogic.currentDeckPackIdx].name
    UI.addButton("btn_deck_pack", "Deck: " .. packName, cx - 100, cy + 10, 200, 40, function()
        GameLogic.currentDeckPackIdx = GameLogic.currentDeckPackIdx + 1
        if GameLogic.currentDeckPackIdx > #GameLogic.deckPacks then
            GameLogic.currentDeckPackIdx = 1
        end
        local newName = GameLogic.deckPacks[GameLogic.currentDeckPackIdx].name
        UI.setText("btn_deck_pack", "Deck: " .. newName)
        GameLogic.loadCardSprites(GameLogic.currentDeckPackIdx)
    end)

    UI.addButton("btn_start", "Start Game", cx - 100, cy + 80, 200, 50, function()
        if Network.roomCode then
            GameLogic.totalRounds = _G.matchRounds
            GameLogic.maxTurnTime = _G.matchTurnTime
            GameLogic.startOnlineHostGame()
            appState = "GAME"
            setupGameUI()
        end
    end)
    UI.addButton("btn_back", "Back", cx - 100, cy + 150, 200, 50, function()
        Network.disconnect()
        appState = "MENU"
        setupMenuUI()
    end)
end

function setupJoinUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addTextInput("input_code", "Enter Room Code", cx - 100, cy - 100, 200, 50)
    UI.addButton("btn_connect", "Connect", cx - 100, cy - 20, 200, 50, function()
        local code = UI.getText("input_code")
        if code and #code > 0 then
            Network.connectAsGuest(code, _G.globalUsername or ("Player" .. math.random(100, 999)))
            GameLogic.mode = "GUEST"
            appState = "LOBBY_GUEST"
            setupGuestLobbyUI()
        end
    end)
    UI.addButton("btn_back", "Back", cx - 100, cy + 60, 200, 50, function()
        appState = "MENU"
        setupMenuUI()
    end)
end

function setupGuestLobbyUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addLabel("lbl_guest_lobby", "Waiting for Host...", cx - 100, cy - 100)
    UI.addButton("btn_back", "Disconnect", cx - 100, cy + 100, 200, 50, function()
        Network.disconnect()
        appState = "MENU"
        setupMenuUI()
    end)
end

function setupGameUI()
    UI.clear()
    -- Game logic UI managed by GameLogic primarily, UI module used for simple widgets
    GameLogic.setupUI()
end

function setupPauseUI()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addLabel("lbl_pause", "PAUSED", cx - 30, cy - 150)
    UI.addButton("btn_resume", "Resume", cx - 100, cy - 80, 200, 50, function()
        _G.inPauseMenu = false
        setupGameUI()
    end)
    UI.addButton("btn_full", "Toggle Fullscreen", cx - 100, cy - 20, 200, 50, function()
        love.window.setFullscreen(not love.window.getFullscreen())
    end)
    UI.addButton("btn_leave", "Leave Match", cx - 100, cy + 40, 200, 50, function()
        _G.inPauseMenu = false
        Network.disconnect()
        appState = "MENU"
        setupMenuUI()
    end)
end

_G.setupMatchOverUI = function()
    UI.clear()
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    UI.addButton("btn_leave_match", "Return to Menu", cx - 100, cy + 120, 200, 50, function()
        Network.disconnect()
        appState = "MENU"
        setupMenuUI()
    end)
end

function love.update(dt)
    Network.update(dt)
    UI.update(dt)
    
    if appState == "LOBBY" then
        if Network.roomCode then
            UI.setText("lbl_lobby", "Room Code: " .. Network.roomCode .. "\nPlayers: " .. Network.getPlayerCount() .. "/4")
        end
    elseif appState == "GAME" then
        if not _G.inPauseMenu and GameLogic.phase ~= "MATCH_OVER" then
            GameLogic.update(dt)
        end
        if GameLogic.phase == "MATCH_OVER" and not UI.getText("btn_leave_match") then
            -- Trigger UI creation once
            _G.setupMatchOverUI()
        end
    end
end

function love.draw()
    local scale, ox, oy = getScaleOffsets()
    love.graphics.push()
    love.graphics.translate(ox, oy)
    love.graphics.scale(scale, scale)
    
    -- Scissor out the overflowing bounds dynamically
    love.graphics.setScissor(ox, oy, _G.getW() * scale, _G.getH() * scale)
    
    -- -- Background
    -- if appState == "GAME" then
        -- -- Felt green background
        -- love.graphics.clear(0.08, 0.35, 0.20, 1.0)
        -- -- love.graphics.clear(0.109804, 0.109804, 0.109804, 1)
        -- GameLogic.draw()
        
        -- if _G.inPauseMenu or GameLogic.phase == "MATCH_OVER" then
            -- love.graphics.setColor(0, 0, 0, 0.7)
            -- love.graphics.rectangle("fill", 0, 0, _G.getW(), _G.getH())
        -- end
    -- else
        -- love.graphics.clear(0.05, 0.08, 0.12, 1.0)
    -- end
    
    -- In love.load() or initialization section

    -- In your draw section
    if appState == "GAME" then
        -- love.graphics.clear(0.08, 0.35, 0.20, 1.0)
        love.graphics.clear(0.05, 0.30, 0.15, 1.0)
        -- Draw background image with blend mode
        if backgroundImage then
            -- Store current color
            local r, g, b, a = love.graphics.getColor()
            -- Method 1: Draw with alpha blending
            love.graphics.setColor(1, 1, 1, 0.18) -- 50% opacity
            love.graphics.draw(backgroundImage, 0, 0, 0, _G.getW()/backgroundImage:getWidth(), _G.getH()/backgroundImage:getHeight())
            
            -- Method 2 (alternative): Use blend modes for different effects
            -- love.graphics.setBlendMode("multiply", "premultiplied")
            -- love.graphics.setColor(1, 1, 1, 1)
            -- love.graphics.draw(backgroundImage, 0, 0, 0, _G.getW()/backgroundImage:getWidth(), _G.getH()/backgroundImage:getHeight())
            -- love.graphics.setBlendMode("alpha")
            
            -- Restore color
            love.graphics.setColor(r, g, b, a)
        end
        
        GameLogic.draw()
        
        if _G.inPauseMenu or GameLogic.phase == "MATCH_OVER" then
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", 0, 0, _G.getW(), _G.getH())
        end
    else

    love.graphics.clear(0.05, 0.08, 0.12, 1.0)
end
    
    UI.draw()
    
    if errorMessage then
        local cx, cy = _G.getW() / 2, _G.getH() / 2
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.rectangle("fill", cx - 200, cy - 100, 400, 200, 10, 10)
        love.graphics.setColor(1, 0.3, 0.3, 1)
        love.graphics.printf("Error / Disconnect", 0, cy - 60, _G.getW(), "center")
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(errorMessage, 0, cy - 10, _G.getW(), "center")
    end
    
    love.graphics.setScissor()
    love.graphics.pop()
    
    -- Fill letterboxes with black logically outside matrix
    love.graphics.setColor(0, 0, 0, 1)
    if ox > 0 then
        love.graphics.rectangle("fill", 0, 0, ox, love.graphics.getHeight())
        love.graphics.rectangle("fill", love.graphics.getWidth() - ox, 0, ox, love.graphics.getHeight())
    elseif oy > 0 then
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), oy)
        love.graphics.rectangle("fill", 0, love.graphics.getHeight() - oy, love.graphics.getWidth(), oy)
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    local scale, ox, oy = getScaleOffsets()
    x = (x - ox) / scale
    y = (y - oy) / scale

    if errorMessage then
        errorMessage = nil
        appState = "MENU"
        setupMenuUI()
        return
    end
    UI.mousepressed(x, y, button)
    if appState == "GAME" and not _G.inPauseMenu and GameLogic.phase ~= "MATCH_OVER" then
        GameLogic.mousepressed(x, y, button)
    end
end

function love.textinput(t)
    UI.textinput(t)
end

function love.keypressed(key)
    UI.keypressed(key)
    if key == "escape" then
        if appState == "GAME" and GameLogic.phase ~= "MATCH_OVER" then
            if _G.inPauseMenu then
                _G.inPauseMenu = false
                setupGameUI()
            else
                _G.inPauseMenu = true
                setupPauseUI()
            end
        end
    end
end

-- Network handlers mapped to GameLogic or UI
_G.handleNetworkEvent = function(evt)
    if evt.type == "ROOM_CREATED" then
        Network.roomCode = evt.code
    elseif evt.type == "JOIN_SUCCESS" then
        UI.setText("lbl_guest_lobby", "Joined Room! Waiting for host to start...")
    elseif evt.type == "CLIENT_JOINED" then
        -- Handled by network mapping internally if needed
    elseif evt.type == "GAME_MSG" or evt.type == "GUEST_MSG" then
        GameLogic.handleNetworkMessage(evt)
        if appState == "LOBBY_GUEST" and evt.type == "GAME_MSG" and evt.data and evt.data.type == "STATE_UPDATE" then
            appState = "GAME"
            setupGameUI()
        end
    elseif evt.type == "CLIENT_LEFT" then
        -- Hook to bot drop-in
        GameLogic.handlePlayerDropped(evt.clientId)
    elseif evt.type == "ERROR" then
        errorMessage = evt.message
    elseif evt.type == "ROOM_CLOSED" then
        errorMessage = "The Host has ended the match or disconnected."
        Network.disconnect()
        UI.clear()
    elseif evt.type == "DISCONNECT" then
        errorMessage = evt.reason
        Network.disconnect()
        UI.clear()
    end
end
