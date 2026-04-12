local Bot = require("bot")
local Network = require("network")

local GameLogic = {}

local suits = {"S", "H", "D", "C"}
local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}
local rankValues = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}
local suitColors = {
    ["S"] = {0.15, 0.15, 0.15}, 
    ["C"] = {0.2, 0.35, 0.25},
    ["H"] = {0.95, 0.2, 0.3},
    ["D"] = {0.95, 0.45, 0.1}
}

local SPRITE_W = 96
local SPRITE_H = 134

local CARD_W = 70
local CARD_H = 100

local function getRelativePos(i)
    local rel = (i - GameLogic.myPlayerIdx) % 4
    if rel == 0 then return "BOTTOM"
    elseif rel == 1 then return "LEFT"
    elseif rel == 2 then return "TOP"
    elseif rel == 3 then return "RIGHT" end
end

function GameLogic.getPlayerAnchor(i)
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    local pos = getRelativePos(i)
    if pos == "BOTTOM" then return cx, _G.getH() - 50
    elseif pos == "LEFT" then return -50, cy
    elseif pos == "TOP" then return cx, -50
    elseif pos == "RIGHT" then return _G.getW() + 50, cy end
    return cx, cy
end


-- Game State Variables
GameLogic.mode = "OFFLINE" -- "OFFLINE", "HOST", "GUEST"
GameLogic.phase = "WAITING" -- "WAITING", "DEALING", "CALLING", "PLAYING", "ROUND_OVER", "MATCH_OVER"

GameLogic.players = {} -- array of 4 players
GameLogic.myPlayerIdx = 1
GameLogic.currentPlayer = 1

GameLogic.deckPacks = {
    {name="Olive Stripes",    back="card_back_2.png",   front="cards_diagonal.png"},
    {name="Ink Diagonal",     back="card_back.png",     front="cards_diagonal.png"},
    {name="ZigZag Plum",      back="card_back_4.png",   front="cards_diagonal.png"},
    {name="Olive Solo",       back="card_back_3.png",   front="cards_solo.png"}
}
GameLogic.currentDeckPackIdx = 1

GameLogic.totalRounds = 5
GameLogic.maxTurnTime = 15

GameLogic.trick = {} -- Cards played in current trick
GameLogic.flyingCards = {} -- Cards traveling off the table
GameLogic.trickLeadSuit = nil
GameLogic.roundNum = 1
GameLogic.turnTimer = 0

function GameLogic.load()
    math.randomseed(os.time())
    GameLogic.loadCardSprites(GameLogic.currentDeckPackIdx)
end

function GameLogic.startOfflineGame()
    GameLogic.mode = "OFFLINE"
    GameLogic.initPlayers()
    GameLogic.startRound()
end

function GameLogic.startOnlineHostGame()
    GameLogic.mode = "HOST"
    GameLogic.initPlayers()
    -- Sync game start to guests
    Network.sendGameMessage("all", { type = "STATE_UPDATE", state = GameLogic.getState() })
    GameLogic.startRound()
end

function GameLogic.initPlayers()
    GameLogic.players = {}
    -- Player 1 is always the local user
    table.insert(GameLogic.players, { name = _G.globalUsername or "You", isBot = false, hand = {}, call = 0, tricksWon = 0, score = 0, id = "P1" })
    
    if GameLogic.mode == "OFFLINE" then
        -- 3 Bots
        table.insert(GameLogic.players, { name = "Bot 1", isBot = true, hand = {}, call = 0, tricksWon = 0, score = 0, id = "P2" })
        table.insert(GameLogic.players, { name = "Bot 2", isBot = true, hand = {}, call = 0, tricksWon = 0, score = 0, id = "P3" })
        table.insert(GameLogic.players, { name = "Bot 3", isBot = true, hand = {}, call = 0, tricksWon = 0, score = 0, id = "P4" })
    elseif GameLogic.mode == "HOST" then
        -- Fill with network players, then bots
        local netPlayers = Network.players
        for i=1, 3 do
            if netPlayers[i] then
                table.insert(GameLogic.players, { name = netPlayers[i].name, isBot = false, hand = {}, call = 0, tricksWon = 0, score = 0, id = netPlayers[i].id })
            else
                table.insert(GameLogic.players, { name = "Bot " .. i, isBot = true, hand = {}, call = 0, tricksWon = 0, score = 0, id = "Bot" .. i })
            end
        end
    end
end

function GameLogic.startRound()
    GameLogic.phase = "DEALING"
    GameLogic.trick = {}
    GameLogic.flyingCards = {}
    GameLogic.trickLeadSuit = nil
    
    for i=1, 4 do
        GameLogic.players[i].hand = {}
        GameLogic.players[i].call = 0
        GameLogic.players[i].tricksWon = 0
    end
    
    local deck = GameLogic.generateDeck()
    GameLogic.shuffle(deck)
    
    -- Deal 13 cards each
    for i=1, 52 do
        local pIdx = ((i - 1) % 4) + 1
        table.insert(GameLogic.players[pIdx].hand, deck[i])
    end
    
    -- Sort hands and initialize visuals
    for i=1, 4 do
        table.sort(GameLogic.players[i].hand, function(a,b)
            if a.suit == b.suit then
                return rankValues[a.rank] > rankValues[b.rank]
            end
            return a.suit > b.suit
        end)
        for _, c in ipairs(GameLogic.players[i].hand) do
            local startX, startY = GameLogic.getPlayerAnchor(1)
            c.visX = startX
            c.visY = startY
        end
    end
    
    GameLogic.phase = "CALLING"
    GameLogic.currentPlayer = (GameLogic.roundNum % 4) + 1
    if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    
    GameLogic.syncState()
end

function GameLogic.generateDeck()
    local deck = {}
    for _, s in ipairs(suits) do
        for _, r in ipairs(ranks) do
            table.insert(deck, {suit=s, rank=r})
        end
    end
    return deck
end

function GameLogic.shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

function GameLogic.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if GameLogic.phase == "CALLING" then
        p.call = Bot.makeCall(p.hand)
        GameLogic.advanceTurn()
    elseif GameLogic.phase == "PLAYING" then
        local idx, card = Bot.playCard(p.hand, GameLogic.trickLeadSuit, GameLogic.trick, p.call, p.tricksWon)
        GameLogic.playCard(GameLogic.currentPlayer, idx)
    end
end

function GameLogic.playCard(playerIdx, cardIdx)
    local p = GameLogic.players[playerIdx]
    local card = table.remove(p.hand, cardIdx)
    
    local px, py = GameLogic.getPlayerAnchor(playerIdx)
    if playerIdx == GameLogic.myPlayerIdx then
        -- Keep existing visX/visY if it's the local hand for smoother transition
    else
        card.visX = px
        card.visY = py
    end
    card.visRot = 0
    
    if #GameLogic.trick == 0 then
        GameLogic.trickLeadSuit = card.suit
    end
    
    table.insert(GameLogic.trick, { playerIdx = playerIdx, card = card })
    GameLogic.syncState()
    
    if #GameLogic.trick == 4 then
        -- Evaluate trick after a short delay
        GameLogic.phase = "EVAL_TRICK"
    else
        GameLogic.advanceTurn()
    end
end

function GameLogic.advanceTurn()
    if GameLogic.phase == "CALLING" then
        GameLogic.currentPlayer = GameLogic.currentPlayer + 1
        if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
        
        -- Check if calling is done
        local allCalled = true
        for i=1, 4 do if GameLogic.players[i].call == 0 then allCalled = false break end end
        if allCalled then
            GameLogic.phase = "PLAYING"
            -- Lead is the one who called first this round
            GameLogic.currentPlayer = (GameLogic.roundNum % 4) + 1
            if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
        end
        GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    elseif GameLogic.phase == "PLAYING" then
        GameLogic.currentPlayer = GameLogic.currentPlayer + 1
        if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
        GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    end
    GameLogic.syncState()
end

local evalTimer = 0
function GameLogic.update(dt)
    -- We allow guests to run update for visual animations, but guard logic
    
    if GameLogic.phase == "CALLING" or GameLogic.phase == "PLAYING" then
        if GameLogic.players[GameLogic.currentPlayer].isBot then
            -- Bot thinking delay
            evalTimer = evalTimer + dt
            if evalTimer > 1.0 then
                evalTimer = 0
                if GameLogic.mode ~= "GUEST" then
                    GameLogic.playTurnBot()
                end
            end
        end
        
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer < 0 then
                GameLogic.turnTimer = 0
                if GameLogic.mode ~= "GUEST" and not GameLogic.players[GameLogic.currentPlayer].isBot then
                    GameLogic.playTurnBot()
                end
            end
        end
    elseif GameLogic.phase == "EVAL_TRICK" then
        evalTimer = evalTimer + dt
        if evalTimer > 2.0 then
            evalTimer = 0
            if GameLogic.mode ~= "GUEST" then
                GameLogic.resolveTrick()
            end
        end
    elseif GameLogic.phase == "ROUND_OVER" then
        evalTimer = evalTimer + dt
        if evalTimer > 5.0 then
            evalTimer = 0
            if GameLogic.mode ~= "GUEST" then
                if GameLogic.roundNum >= (GameLogic.totalRounds or 5) then
                    GameLogic.phase = "MATCH_OVER"
                    GameLogic.syncState()
                else
                    GameLogic.roundNum = GameLogic.roundNum + 1
                    GameLogic.startRound()
                end
            end
        end
    end
    
    -- Visual Animations
    local lerpSpeed = 12
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    
    -- Trick Cards
    for i, t in ipairs(GameLogic.trick) do
        local pos = getRelativePos(t.playerIdx)
        local tx, ty = cx - (CARD_W/2), cy - (CARD_H/2)
        if pos == "BOTTOM" then ty = ty + 40
        elseif pos == "LEFT" then tx = tx - 60
        elseif pos == "TOP" then ty = ty - 40
        elseif pos == "RIGHT" then tx = tx + 60 end
        
        t.card.visX = t.card.visX and t.card.visX + (tx - t.card.visX) * dt * lerpSpeed or tx
        t.card.visY = t.card.visY and t.card.visY + (ty - t.card.visY) * dt * lerpSpeed or ty
    end
    
    -- Flying Trick Cards collection
    for i = #GameLogic.flyingCards, 1, -1 do
        local f = GameLogic.flyingCards[i]
        local tx, ty = GameLogic.getPlayerAnchor(f.targetId)
        f.card.visX = f.card.visX + (tx - f.card.visX) * dt * lerpSpeed
        f.card.visY = f.card.visY + (ty - f.card.visY) * dt * lerpSpeed
        if math.abs(tx - f.card.visX) < 10 and math.abs(ty - f.card.visY) < 10 then
            table.remove(GameLogic.flyingCards, i)
        end
    end
    
    -- Local Hand Animation logic handles positions perfectly based on hover state 
    local myP = GameLogic.players[GameLogic.myPlayerIdx]
    if myP and myP.hand then
        local handSize = #myP.hand
        local startX = cx - (handSize * 30) / 2 - (CARD_W / 2)
        local startY = _G.getH() - CARD_H - 30
        
        local mx, my = love.mouse.getPosition()
        local hoveredIdx = -1
        if GameLogic.phase == "PLAYING" and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not myP.isBot then
            for i = handSize, 1, -1 do
                local cardX = startX + (i * 30)
                local cardY = startY
                local wCheck = (i == handSize) and CARD_W or 30
                if mx >= cardX and mx <= cardX + wCheck and my >= cardY and my <= cardY + CARD_H then
                    hoveredIdx = i
                    break
                end
            end
        end

        for i, c in ipairs(myP.hand) do
            local targetX = startX + (i * 30)
            local targetY = startY
            
            if i == hoveredIdx then
                targetY = targetY - 20
            end
            
            if not c.visX then
                c.visX, c.visY = targetX, targetY
            end
            
            c.visX = c.visX + (targetX - c.visX) * dt * lerpSpeed
            c.visY = c.visY + (targetY - c.visY) * dt * lerpSpeed
        end
    end
end

function GameLogic.handlePlayerDropped(clientId)
    if GameLogic.mode == "HOST" then
        for i=1, 4 do
            if GameLogic.players[i].id == clientId then
               GameLogic.players[i].isBot = true
               GameLogic.players[i].name = GameLogic.players[i].name .. " (Bot)"
               GameLogic.syncState()
               break
            end
        end
    end
end

function GameLogic.resolveTrick()
    local winnerIdx = GameLogic.trick[1].playerIdx
    local bestCard = GameLogic.trick[1].card
    
    for i = 2, 4 do
        local currentEntry = GameLogic.trick[i]
        local c = currentEntry.card
        local pIdx = currentEntry.playerIdx
        
        -- 1. Check if current card is a Spade (Trump)
        -- 2. Check if best card is a Spade (Trump)
        
        if c.suit == "S" and bestCard.suit ~= "S" then
            -- Current is Spade, Best is NOT Spade -> Current Wins
            bestCard = c
            winnerIdx = pIdx
        elseif c.suit == "S" and bestCard.suit == "S" then
            -- Both are Spades -> Higher Rank Wins
            if rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c
                winnerIdx = pIdx
            end
        elseif c.suit ~= "S" and bestCard.suit ~= "S" then
            -- Neither is a Spade
            -- Does Current follow lead suit?
            if c.suit == GameLogic.trickLeadSuit then
                -- If Best follows lead suit, compare ranks. If Best DOES NOT follow lead suit, Current wins automatically.
                if bestCard.suit ~= GameLogic.trickLeadSuit then
                    bestCard = c
                    winnerIdx = pIdx
                elseif rankValues[c.rank] > rankValues[bestCard.rank] then
                    bestCard = c
                    winnerIdx = pIdx
                end
            end
            -- Note: If c.suit ~= lead suit and bestCard DOES follow lead suit, current card loses (ignored).
        end
        -- Note: If bestCard is Spade and current is NOT Spade -> current loses (ignored).
    end
    
    GameLogic.players[winnerIdx].tricksWon = GameLogic.players[winnerIdx].tricksWon + 1
    
    -- Animate Trick Gathering
    for _, t in ipairs(GameLogic.trick) do
        table.insert(GameLogic.flyingCards, { card = t.card, targetId = winnerIdx }) 
    end
    
    GameLogic.trick = {}
    GameLogic.trickLeadSuit = nil
    
    GameLogic.currentPlayer = winnerIdx
    GameLogic.phase = "PLAYING"
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    
    -- Check round over
    local cardsLeft = #GameLogic.players[1].hand
    if cardsLeft == 0 then
        GameLogic.phase = "ROUND_OVER"
        GameLogic.calculateScores()
    end
    
    GameLogic.syncState()
end

function GameLogic.calculateScores()
    for i=1, 4 do
        local p = GameLogic.players[i]
        if p.tricksWon >= p.call then
            p.score = p.score + p.call + ((p.tricksWon - p.call) * 0.1)
        else
            p.score = p.score - p.call
        end
    end
end

-- Network Sync
function GameLogic.syncState()
    if GameLogic.mode == "HOST" then
        -- Send customized state to each client, hiding other hands
        -- For simplicity, since it's with friends, we can just send the whole state or sanitize it.
        -- We will just send full state for easy debugging, but a real game hides hands.
        -- Let's hide them.
        for netIdx, netClient in ipairs(Network.players) do
            local safeState = GameLogic.getStateFor(netClient.id)
            Network.sendGameMessage(netClient.id, { type = "STATE_UPDATE", state = safeState })
        end
    end
end

function GameLogic.getStateFor(clientId)
    local state = {
        phase = GameLogic.phase,
        currentPlayer = GameLogic.currentPlayer,
        turnTimer = GameLogic.turnTimer,
        trick = GameLogic.trick,
        trickLeadSuit = GameLogic.trickLeadSuit,
        roundNum = GameLogic.roundNum,
        totalRounds = GameLogic.totalRounds,
        maxTurnTime = GameLogic.maxTurnTime,
        players = {}
    }
    for i=1, 4 do
        local p = GameLogic.players[i]
        local pSafe = { name = p.name, call = p.call, tricksWon = p.tricksWon, score = p.score, id = p.id, isBot = p.isBot }
        if p.id == clientId then
            pSafe.hand = p.hand
            pSafe.isMe = true
        else
            pSafe.handSize = #p.hand
        end
        table.insert(state.players, pSafe)
    end
    state.deckPackIdx = GameLogic.currentDeckPackIdx
    return state
end

function GameLogic.getState()
    return GameLogic.getStateFor(GameLogic.players[1].id) -- get local host state
end

function GameLogic.handleNetworkMessage(evt)
    if evt.type == "GUEST_MSG" and GameLogic.mode == "HOST" then
        -- Input from guest
        local data = evt.data
        if data.action == "MAKE_CALL" then
            -- find player
            for i=1, 4 do 
                if GameLogic.players[i].id == evt.clientId and i == GameLogic.currentPlayer and GameLogic.phase == "CALLING" then
                    GameLogic.players[i].call = data.call
                    GameLogic.advanceTurn()
                    break
                end
            end
        elseif data.action == "PLAY_CARD" then
            for i=1, 4 do 
                if GameLogic.players[i].id == evt.clientId and i == GameLogic.currentPlayer and GameLogic.phase == "PLAYING" then
                    -- Verify hand idx
                    GameLogic.playCard(i, data.cardIdx)
                    break
                end
            end
        end
    elseif evt.type == "GAME_MSG" and GameLogic.mode == "GUEST" then
        -- Received state update from host
        if evt.data.type == "STATE_UPDATE" then
            GameLogic.applyStateUpdate(evt.data.state)
        end
    end
end

function GameLogic.applyStateUpdate(state)
    -- Guest applying state
    GameLogic.phase = state.phase
    GameLogic.currentPlayer = state.currentPlayer
    GameLogic.turnTimer = state.turnTimer
    -- Keep trick visual persistence if trick shrinks
    if #state.trick == 0 and #GameLogic.trick > 0 then
        -- Find winner dynamically to simulate flying cards on guest side... Too complex for state sync.
        GameLogic.trick = {} 
    elseif #state.trick > #GameLogic.trick then
        for i = #GameLogic.trick + 1, #state.trick do
            local nT = state.trick[i]
            local px, py = GameLogic.getPlayerAnchor(nT.playerIdx)
            nT.card.visX = px
            nT.card.visY = py
            table.insert(GameLogic.trick, nT)
        end
    end
    
    GameLogic.trickLeadSuit = state.trickLeadSuit
    GameLogic.roundNum = state.roundNum
    GameLogic.totalRounds = state.totalRounds or 5
    GameLogic.maxTurnTime = state.maxTurnTime or 15
    
    if state.deckPackIdx and state.deckPackIdx ~= GameLogic.currentDeckPackIdx then
        GameLogic.currentDeckPackIdx = state.deckPackIdx
        GameLogic.loadCardSprites(GameLogic.currentDeckPackIdx)
    end
    
    GameLogic.players = state.players
    for i=1, 4 do
        if state.players[i].isMe then
            GameLogic.myPlayerIdx = i
            -- Init visuals if fresh
            if state.players[i].hand then
                for _, c in ipairs(state.players[i].hand) do
                    if not c.visX then
                        c.visX, c.visY = GameLogic.getPlayerAnchor(i)
                    end
                end
            end
        end
    end
end

-- UI and Interaction

function GameLogic.setupUI()
    -- Create calling buttons if it's my turn to call
    -- UI logic mixed with drawing per frame using immediate mode is easier
end

function GameLogic.draw()
    if #GameLogic.players == 0 then return end

    local W, H = _G.getW(), _G.getH()
    local cx, cy = W / 2, H / 2
    local font = love.graphics.getFont()
    local fontH = font:getHeight()

    -- Helper to draw professional text with drop shadow
    local function drawText(text, x, y, w, align, color)
        love.graphics.setColor(color or {1, 1, 1, 1})
        love.graphics.printf(text, x, y, w, align)
    end

    if GameLogic.phase == "MATCH_OVER" then
        -- Professional Match Over Overlay
        love.graphics.setColor(0.05, 0.05, 0.1, 0.8)
        love.graphics.rectangle("fill", cx - 250, cy - 200, 500, 400, 16)

        drawText("MATCH OVER - FINAL SCORES", 0, cy - 150, W, "center", {1, 0.85, 0.3, 1})

        local sorted = {}
        for i = 1, 4 do table.insert(sorted, GameLogic.players[i]) end
        table.sort(sorted, function(a, b) return a.score > b.score end)

        for i, p in ipairs(sorted) do
            local pColor = (p.id == GameLogic.players[GameLogic.myPlayerIdx].id) and {0.3, 0.95, 0.4, 1} or {1, 1, 1, 1}
            drawText(i .. ". " .. p.name .. " - Score: " .. string.format("%.1f", p.score),
                           0, cy - 70 + (i * 45), W, "center", pColor)
        end
        return
    end

    if GameLogic.phase == "EVAL_TRICK" and #GameLogic.trick > 0 then
        local bestCard = GameLogic.trick[1].card
        local winnerIdx = GameLogic.trick[1].playerIdx
        for i = 2, #GameLogic.trick do
            local c = GameLogic.trick[i].card
            local pIdx = GameLogic.trick[i].playerIdx
            local isSpade = (c.suit == "S")
            local bestIsSpade = (bestCard.suit == "S")
            
            if isSpade and not bestIsSpade then
                bestCard = c; winnerIdx = pIdx
            elseif isSpade and bestIsSpade and rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c; winnerIdx = pIdx
            elseif c.suit == GameLogic.trickLeadSuit and bestCard.suit == GameLogic.trickLeadSuit and rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c; winnerIdx = pIdx
            end
        end
        drawText(GameLogic.players[winnerIdx].name .. " wins trick!", 0, cy + 90, W, "center", {1, 0.85, 0.3, 1})
    end

    -- 4. Player Names (Centered and Rotated precisely on sides)
    for i = 1, 4 do
        local p = GameLogic.players[i]
        local isCurrent = (i == GameLogic.currentPlayer)
        local pos = getRelativePos(i)

        local lx, ly = cx, cy
        local angle = 0
        local edgeOffset = 40

        if pos == "BOTTOM" then
            lx = cx
            ly = H - edgeOffset - 130
            angle = 0
        elseif pos == "LEFT" then
            lx = edgeOffset
            ly = cy
            angle = math.pi / 2
        elseif pos == "TOP" then
            lx = cx
            ly = edgeOffset
            angle = math.pi
        elseif pos == "RIGHT" then
            lx = W - edgeOffset
            ly = cy
            angle = -math.pi / 2
        end

        love.graphics.push()
        love.graphics.translate(lx, ly)
        love.graphics.rotate(angle)

        local pColor = isCurrent and {0.3, 0.95, 0.4, 1} or {1, 1, 1, 0.9}

        if isCurrent then
            love.graphics.setColor(0.3, 0.95, 0.4, 0.2)
            love.graphics.rectangle("fill", -80, -12, 160, 24, 12)
        end

        drawText(p.name, -100, -fontH / 2, 200, "center", pColor)

        if isCurrent and p.isBot and (GameLogic.phase == "CALLING" or GameLogic.phase == "PLAYING") then
            drawText("Thinking...", -100, (fontH / 2) + 4, 200, "center", {0.6, 0.6, 0.6, 1})
        end

        love.graphics.pop()
        
        -- Draw Hand Backs for Opponents Beautifully fanned out
        local hSize = p.handSize or (p.hand and #p.hand) or 0
        if pos ~= "BOTTOM" and hSize > 0 then
            local rotStep = 0.1
            local totalArc = (hSize - 1) * rotStep
            local startRot = -totalArc / 2
            
            for j = 1, hSize do 
                local offset = (j - hSize/2) * 12
                local rx, ry, rz = lx, ly, startRot + ((j-1) * rotStep)
                if pos == "LEFT" then 
                    GameLogic.drawCardBack(140, cy + offset, math.pi/2 + rz)
                elseif pos == "TOP" then 
                    GameLogic.drawCardBack(cx - offset, 140, rz)
                elseif pos == "RIGHT" then 
                    GameLogic.drawCardBack(_G.getW() - 140, cy - offset, math.pi/2 + rz) 
                end
            end
        end
    end
    
    -- 5. Draw Local Hand
    local myP = GameLogic.players[GameLogic.myPlayerIdx]
    if myP and myP.hand then
        for i, c in ipairs(myP.hand) do
            local valid = true
            if GameLogic.phase == "PLAYING" and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not myP.isBot and GameLogic.trickLeadSuit then
                if c.suit ~= GameLogic.trickLeadSuit then
                    for _, hc in ipairs(myP.hand) do
                        if hc.suit == GameLogic.trickLeadSuit then
                            valid = false
                            break
                        end
                    end
                end
            end
            GameLogic.drawCard(c, c.visX or 0, c.visY or 0, valid)
        end
    end

    -- 6. Draw Trick Cards (Flying and Placed)
    for _, f in ipairs(GameLogic.flyingCards) do
        GameLogic.drawCard(f.card, f.card.visX, f.card.visY, true)
    end

    for _, t in ipairs(GameLogic.trick) do
        if t.card.visX then
            GameLogic.drawCard(t.card, t.card.visX, t.card.visY, true)
        end
    end
    

    -- 1. Match Info (Top-Left)
    love.graphics.setColor(0.05, 0.05, 0.1, 0.8)
    love.graphics.rectangle("fill", 15, 15, 200, 80, 10)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", 15, 15, 200, 80, 10)

    drawText("Round: " .. GameLogic.roundNum .. "/" .. (GameLogic.totalRounds or 5), 25, 25, 180, "left", {0.9, 0.9, 0.9, 1})
    drawText("Phase: " .. GameLogic.phase, 25, 45, 180, "left", {0.8, 0.8, 0.8, 1})

    if (GameLogic.phase == "CALLING" or GameLogic.phase == "PLAYING") and GameLogic.turnTimer then
        local tColor = GameLogic.turnTimer <= 5 and {1, 0.4, 0.4, 1} or {0.4, 0.9, 1, 1}
        drawText("Time: " .. math.ceil(GameLogic.turnTimer) .. "s", 25, 65, 180, "left", tColor)
    end

    -- 2. Scoreboard (Top-Right)
    local sbWidth = 280 -- Increased slightly for more breathing room
    local sbHeight = 80 + (4 * 30)
    local sbX = W - sbWidth - 15
    local sbY = 15

    -- Background & Border
    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 10)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 10)

    -- Header
    drawText("SCOREBOARD", sbX, sbY + 12, sbWidth, "center", {1, 0.85, 0.3, 1})

    -- Column Definitions (X-Offsets relative to sbX)
    local colName  = 15
    local colCall  = 130
    local colTrick = 180
    local colScore = 230

    -- Sub-header Labels
    local labelY = sbY + 35
    local labelColor = {0.6, 0.6, 0.6, 1}
    drawText("Player", sbX + colName, labelY, 100, "left", labelColor)
    drawText("C",      sbX + colCall, labelY, 40,  "center", labelColor)
    drawText("T",      sbX + colTrick, labelY, 40, "center", labelColor)
    drawText("Pts",    sbX + colScore, labelY, 40, "right", labelColor)

    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.line(sbX + 10, sbY + 55, sbX + sbWidth - 10, sbY + 55)

    -- Table Rows
    local scoreY = sbY + 65
    for i = 1, 4 do
        local p = GameLogic.players[i]
        local isCurrent = (i == GameLogic.currentPlayer)
        if isCurrent then
            love.graphics.setColor(1, 1, 1, 0.05)
            love.graphics.rectangle("fill", sbX + 5, scoreY - 5, sbWidth - 10, 25, 4)
        end
        local pColor = isCurrent and {0.3, 0.95, 0.4, 1} or {0.95, 0.95, 0.95, 1}
        drawText(p.name, sbX + colName, scoreY, colCall - colName - 5, "left", pColor)
        drawText(tostring(p.call or 0), sbX + colCall, scoreY, 40, "center", pColor)
        drawText(tostring(p.tricksWon or 0), sbX + colTrick, scoreY, 40, "center", pColor)
        drawText(string.format("%.1f", p.score or 0), sbX + colScore, scoreY, 40, "right", pColor)
        scoreY = scoreY + 30
    end

    -- -- 3. Center Trick Info
    -- if GameLogic.trickLeadSuit then
        -- local suitNames = {S = "Spades", H = "Hearts", D = "Diamonds", C = "Clubs"}
        -- drawText("Lead Suit: " .. suitNames[GameLogic.trickLeadSuit], 0, cy - 90, W, "center", {1, 0.8, 0.8, 1})
    -- end
    
    -- 7. Draw Calling UI
    if GameLogic.phase == "CALLING" and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.currentPlayer].isBot then
        local boxW = 8 * 55
        local startX = cx - (boxW / 2)
        local startY = cy + 50
        
        -- Dark Background Panel
        love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
        love.graphics.rectangle("fill", startX - 20, startY - 40, boxW + 40, 110, 12)
        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.rectangle("line", startX - 20, startY - 40, boxW + 40, 110, 12)

        drawText("Make Your Call:", 0, startY - 25, W, "center", {1, 1, 1, 1})

        local mx, my = love.mouse.getPosition()
        for j = 1, 8 do
            local bx = startX + ((j - 1) * 55)
            local by = startY + 10

            local isHovered = (mx >= bx and mx <= bx + 45 and my >= by and my <= by + 45)

            if isHovered then
                love.graphics.setColor(0.3, 0.7, 1.0, 1)
                love.graphics.rectangle("fill", bx, by - 5, 45, 50, 8)
                drawText(tostring(j), bx, by + 12, 45, "center", {0, 0, 0, 1})
            else
                love.graphics.setColor(0.15, 0.25, 0.45, 1)
                love.graphics.rectangle("fill", bx, by, 45, 45, 8)
                drawText(tostring(j), bx, by + 12, 45, "center", {1, 1, 1, 1})
            end
        end
    end
end


local RANKS = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
local SUITS = {"C", "D", "H", "S"}

local cardSheet
local cardQuads = {}
local cardBackSheet

function GameLogic.loadCardSprites(packIdx)
    packIdx = packIdx or 1
    local pack = GameLogic.deckPacks[packIdx] or GameLogic.deckPacks[1]
    
    local frontFile = "assets/" .. pack.front
    local backFile = "assets/" .. pack.back

    local s1, fImg = pcall(love.graphics.newImage, frontFile)
    if s1 then cardSheet = fImg else print("Failed to load front:", frontFile) end
    
    local s2, bImg = pcall(love.graphics.newImage, backFile)
    if s2 then cardBackSheet = bImg else print("Failed to load back:", backFile) end
    
    if not cardSheet then return end
    cardQuads = {}
    
    -- Auto-calculate sprite dimensions based on 13x4 format if SPRITE_W is not set correctly
    local sw, sh = cardSheet:getDimensions()
    -- always recalculate for custom textures like solo
    SPRITE_W = sw / 13
    SPRITE_H = sh / 4
    
    for suitIdx, suit in ipairs(SUITS) do
        cardQuads[suit] = {}
        for rankIdx, rank in ipairs(RANKS) do
            local qx = (rankIdx - 1) * SPRITE_W
            local qy = (suitIdx - 1) * SPRITE_H
            cardQuads[suit][rank] = love.graphics.newQuad(qx, qy, SPRITE_W, SPRITE_H, sw, sh)
        end
    end
end

function GameLogic.drawCard(card, x, y, valid)
    -- Drop shadow
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", x + 3, y + 4, CARD_W, CARD_H, 6, 6)
    
    if not valid then
        love.graphics.setColor(0.5, 0.5, 0.5, 1) -- Set tint to gray if invalid
    else
        love.graphics.setColor(1, 1, 1, 1) -- White (no tint)
    end
    
    if cardSheet and cardQuads[card.suit] and cardQuads[card.suit][card.rank] then
        local scaleX = CARD_W / SPRITE_W
        local scaleY = CARD_H / SPRITE_H
        love.graphics.draw(cardSheet, cardQuads[card.suit][card.rank], x, y, 0, scaleX, scaleY)
    else
        -- Fallback if texture is missing or nil
        love.graphics.rectangle("fill", x, y, CARD_W, CARD_H)
    end
    
    love.graphics.setColor(1, 1, 1, 1)
end


function GameLogic.drawCardBack(x, y, rotation)
    love.graphics.push()
    love.graphics.translate(x, y)
    if rotation then love.graphics.rotate(rotation) end
    
    -- Offset drawing to center
    local hw, hh = CARD_W/2, CARD_H/2
    
    -- Shadow
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", -hw + 2, -hh + 2, CARD_W, CARD_H, 6, 6)
    
    -- if cardBackSheet then
        local bw, bh = cardBackSheet:getDimensions()
        local scaleX = CARD_W / bw
        local scaleY = CARD_H / bh
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(cardBackSheet, -hw, -hh, 0, scaleX, scaleY)
    -- else
        -- -- Border
        -- love.graphics.setColor(0.9, 0.9, 0.9, 1)
        -- love.graphics.rectangle("fill", -hw, -hh, CARD_W, CARD_H, 6, 6)
        
        -- -- Inner Pattern
        -- love.graphics.setColor(0.15, 0.3, 0.5, 1)
        -- love.graphics.rectangle("fill", -hw + 5, -hh + 5, CARD_W - 10, CARD_H - 10, 4, 4)
        -- love.graphics.setColor(0.2, 0.4, 0.6, 1)
        -- -- Simple diagonal line pattern
        -- love.graphics.setLineWidth(2)
        -- for i = 10, CARD_H-10, 15 do
            -- love.graphics.line(-hw + 5, -hh + i, -hw + CARD_W - 5, -hh + i)
        -- end
    -- end
    
    love.graphics.pop()
end


function GameLogic.mousepressed(x, y, button)
    if button ~= 1 then return end
    
    if GameLogic.currentPlayer ~= GameLogic.myPlayerIdx then return end
    if GameLogic.players[GameLogic.myPlayerIdx].isBot then return end -- Bot handles itself
    
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    
    if GameLogic.phase == "CALLING" then
        local boxW = 8 * 50
        local startX = cx - (boxW / 2)
        local startY = cy + 50
        
        for j = 1, 8 do
            local bx = startX + ((j-1) * 50)
            local by = startY
            if x >= bx and x <= bx+40 and y >= by and y <= by+40 then
                if GameLogic.mode == "GUEST" then
                    Network.sendGameMessage("host", { action = "MAKE_CALL", call = j })
                else
                    GameLogic.players[GameLogic.myPlayerIdx].call = j
                    GameLogic.advanceTurn()
                end
            end
        end
    elseif GameLogic.phase == "PLAYING" then
        local myP = GameLogic.players[GameLogic.myPlayerIdx]
        if not myP.hand then return end
        
        local handSize = #myP.hand
        local startX = cx - (handSize * 30) / 2 - (CARD_W / 2)
        local startY = _G.getH() - CARD_H - 30
        
        -- Check clicks right to left since cards overlap extending rightwards
        for i = handSize, 1, -1 do
            local c = myP.hand[i]
            local cardX = startX + (i * 30)
            local cardY = startY
            
            local wCheck = (i == handSize) and CARD_W or 30
            
            if x >= cardX and x <= cardX + wCheck and y >= cardY and y <= cardY + CARD_H then
                -- Check valid follow suit
                local isValid = true
                if GameLogic.trickLeadSuit then
                    if c.suit ~= GameLogic.trickLeadSuit then
                         -- Do we have a card of lead suit?
                         for _, hc in ipairs(myP.hand) do
                             if hc.suit == GameLogic.trickLeadSuit then
                                 isValid = false
                                 break
                             end
                         end
                    end
                end
                
                if isValid then
                    if GameLogic.mode == "GUEST" then
                        Network.sendGameMessage("host", { action = "PLAY_CARD", cardIdx = i })
                    else
                        GameLogic.playCard(GameLogic.myPlayerIdx, i)
                    end
                end
                break
            end
        end
    end
end

return GameLogic
