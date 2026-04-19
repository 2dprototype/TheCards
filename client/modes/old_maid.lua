local OldMaid = {}
local GameLogic = nil

local suits = {"S", "H", "D", "C"}
local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}

function OldMaid.init(gl)
    GameLogic = gl
end

function OldMaid.generateDeck()
    local deck = {}
    for _, s in ipairs(suits) do
        for _, r in ipairs(ranks) do
            table.insert(deck, {suit=s, rank=r})
        end
    end
    table.insert(deck, {suit="JOKER", rank="JOKER"})
    return deck
end

function OldMaid.sortHand(hand)
    table.sort(hand, function(a,b)
        if a.suit == "JOKER" then return false end
        if b.suit == "JOKER" then return true end
        if a.rank == b.rank then return a.suit > b.suit end
        -- simplified ranking sort
        local rv = {["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,["9"]=9,["10"]=10,["J"]=11,["Q"]=12,["K"]=13,["A"]=14}
        return rv[a.rank] > rv[b.rank]
    end)
end

function OldMaid.startRound()
    GameLogic.phase = "DISCARD_INITIAL"
    GameLogic.trick = {}
    GameLogic.flyingCards = {}
    
    local deck = OldMaid.generateDeck()
    GameLogic.shuffle(deck)
    
    for i=1, 4 do
        if GameLogic.players[i] then
            GameLogic.players[i].hand = {}
        end
    end
    
    for i=1, #deck do
        local pIdx = ((i - 1) % 4) + 1
        table.insert(GameLogic.players[pIdx].hand, deck[i])
    end
    
    for i=1, 4 do
        OldMaid.sortHand(GameLogic.players[i].hand)
        for _, c in ipairs(GameLogic.players[i].hand) do
            local startX, startY = GameLogic.getPlayerAnchor(i)
            c.visX = startX
            c.visY = startY
        end
    end
    
    -- Pick a random player to start
    GameLogic.currentPlayer = (GameLogic.roundNum % 4) + 1
    if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
    GameLogic.turnTimer = 2.0
    
    GameLogic.syncState()
end

function OldMaid.discardPairs(playerIdx)
    local hand = GameLogic.players[playerIdx].hand
    if not hand then return false end
    
    local rankCounts = {}
    for i, c in ipairs(hand) do
        if c.suit ~= "JOKER" then
            rankCounts[c.rank] = rankCounts[c.rank] or {}
            table.insert(rankCounts[c.rank], i)
        end
    end
    
    local indicesToRemove = {}
    for r, indices in pairs(rankCounts) do
        local pairsCount = math.floor(#indices / 2)
        for p = 1, pairsCount do
            table.insert(indicesToRemove, indices[p*2 - 1])
            table.insert(indicesToRemove, indices[p*2])
        end
    end
    
    if #indicesToRemove == 0 then return false end
    
    table.sort(indicesToRemove, function(a,b) return a > b end)
    
    local px, py = GameLogic.getPlayerAnchor(playerIdx)
    for _, idx in ipairs(indicesToRemove) do
        local c = table.remove(hand, idx)
        if playerIdx ~= GameLogic.myPlayerIdx then
            c.visX, c.visY = px, py
        end
        table.insert(GameLogic.flyingCards, { card = c, targetId = "CENTER" })
    end
    
    OldMaid.sortHand(hand)
    return true
end

function OldMaid.checkForMatchOver()
    if GameLogic.phase == "MATCH_OVER" then return end
    
    local activePlayers = 0
    local loserIdx = 0
    for i=1, 4 do
        local p = GameLogic.players[i]
        local hSize = p.handSize or (p.hand and #p.hand) or 0
        if hSize > 0 then
            activePlayers = activePlayers + 1
            loserIdx = i
        end
    end
    
    if activePlayers <= 1 then
        GameLogic.phase = "MATCH_OVER"
        if loserIdx > 0 then
            GameLogic.players[loserIdx].score = (GameLogic.players[loserIdx].score or 0) - 10
            for i=1, 4 do
                if i ~= loserIdx then
                    GameLogic.players[i].score = (GameLogic.players[i].score or 0) + 10
                end
            end
        end
        GameLogic.syncState()
    end
end

function OldMaid.getTargetPlayer(curr)
    local p = curr - 1
    if p < 1 then p = 4 end
    
    while true do
        local hSize = GameLogic.players[p].handSize or (GameLogic.players[p].hand and #GameLogic.players[p].hand) or 0
        if hSize > 0 then return p end
        
        p = p - 1
        if p < 1 then p = 4 end
        if p == curr then return nil end
    end
end

function OldMaid.advanceTurn()
    GameLogic.currentPlayer = GameLogic.currentPlayer + 1
    if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
    
    local startP = GameLogic.currentPlayer
    while true do
       local p = GameLogic.players[GameLogic.currentPlayer]
       local hSize = p.handSize or (p.hand and #p.hand) or 0
       if hSize > 0 then break end
       GameLogic.currentPlayer = GameLogic.currentPlayer + 1
       if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
       if GameLogic.currentPlayer == startP then break end
    end
    
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    GameLogic.syncState()
    OldMaid.checkForMatchOver()
end

function OldMaid.update(dt)
    if GameLogic.mode == "GUEST" then return end
    
    if GameLogic.phase == "DISCARD_INITIAL" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                for i=1, 4 do
                    OldMaid.discardPairs(i)
                end
                
                -- Fast forward to someone who has cards
                local startP = GameLogic.currentPlayer
                while true do
                   local p = GameLogic.players[GameLogic.currentPlayer]
                   local hSize = p.handSize or (p.hand and #p.hand) or 0
                   if hSize > 0 then break end
                   GameLogic.currentPlayer = GameLogic.currentPlayer + 1
                   if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
                   if GameLogic.currentPlayer == startP then break end
                end

                GameLogic.phase = "PICKING"
                GameLogic.turnTimer = GameLogic.maxTurnTime or 15
                GameLogic.syncState()
            end
        end
    elseif GameLogic.phase == "CHECK_PAIR" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                OldMaid.discardPairs(GameLogic.currentPlayer)
                GameLogic.phase = "PICKING"
                OldMaid.advanceTurn()
            end
        end
    end
end

function OldMaid.isBotTurn()
    return (GameLogic.phase == "PICKING") and GameLogic.players[GameLogic.currentPlayer].isBot
end

function OldMaid.playTurnBot()
    if GameLogic.phase == "PICKING" then
        local targetIdx = OldMaid.getTargetPlayer(GameLogic.currentPlayer)
        if targetIdx then
            local tPlayer = GameLogic.players[targetIdx]
            local hSize = tPlayer.handSize or (tPlayer.hand and #tPlayer.hand) or 0
            if hSize > 0 then
                local cardIdx = math.random(1, hSize)
                OldMaid.pickCard(targetIdx, cardIdx)
            end
        end
    end
end

function OldMaid.pickCard(targetIdx, cardIdx)
    local targetP = GameLogic.players[targetIdx]
    if not targetP.hand or #targetP.hand == 0 then return end
    
    local c = table.remove(targetP.hand, cardIdx)
    
    local tx, ty = GameLogic.getPlayerAnchor(targetIdx)
    c.visX = tx
    c.visY = ty
    table.insert(GameLogic.flyingCards, { card = c, targetId = GameLogic.currentPlayer })
    
    table.insert(GameLogic.players[GameLogic.currentPlayer].hand, c)
    OldMaid.sortHand(GameLogic.players[GameLogic.currentPlayer].hand)
    
    GameLogic.phase = "CHECK_PAIR"
    GameLogic.turnTimer = 1.0
    GameLogic.syncState()
end

function OldMaid.handleNetworkMessage(evt)
    if evt.data.action == "PICK_CARD" then
        if GameLogic.phase == "PICKING" and evt.clientId == GameLogic.players[GameLogic.currentPlayer].id then
            local targetIdx = OldMaid.getTargetPlayer(GameLogic.currentPlayer)
            if targetIdx == evt.data.targetIdx then
                OldMaid.pickCard(targetIdx, evt.data.cardIdx)
            end
            return true
        end
    end
    return false
end

function OldMaid.mousepressed(x, y, button)
    if button ~= 1 then return end
    if GameLogic.phase ~= "PICKING" then return end
    if GameLogic.currentPlayer ~= GameLogic.myPlayerIdx then return end
    if GameLogic.players[GameLogic.myPlayerIdx].isBot then return end
    
    local targetIdx = OldMaid.getTargetPlayer(GameLogic.currentPlayer)
    if not targetIdx then return end
    
    local tPlayer = GameLogic.players[targetIdx]
    local hSize = tPlayer.handSize or (tPlayer.hand and #tPlayer.hand) or 0
    if hSize == 0 then return end
    
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    local pos = nil
    local rel = (targetIdx - GameLogic.myPlayerIdx) % 4
    if rel == 0 then pos = "BOTTOM"
    elseif rel == 1 then pos = "LEFT"
    elseif rel == 2 then pos = "TOP"
    elseif rel == 3 then pos = "RIGHT" end
    
    if pos == "BOTTOM" then return end
    
    local lx, ly = cx, cy
    local edgeOffset = 40
    
    if pos == "LEFT" then
        lx = edgeOffset; ly = cy; 
    elseif pos == "TOP" then
        lx = cx; ly = edgeOffset; 
    elseif pos == "RIGHT" then
        lx = _G.getW() - edgeOffset; ly = cy; 
    end
    
    local CARD_W = 70
    local CARD_H = 100
    
    local rotStep = 0.1
    local totalArc = (hSize - 1) * rotStep
    local startRot = -totalArc / 2
    
    for j = hSize, 1, -1 do
        local offset = (j - hSize/2) * 12
        local rz = startRot + ((j-1) * rotStep)
        
        local cxCard, cyCard = lx, ly
        
        if pos == "LEFT" then 
            cxCard = 140
            cyCard = cy + offset
            -- un-rotate mouse
            local ca = math.cos(-(math.pi/2 + rz))
            local sa = math.sin(-(math.pi/2 + rz))
            local dx = x - cxCard
            local dy = y - cyCard
            local rx = dx * ca - dy * sa
            local ry = dx * sa + dy * ca
            if math.abs(rx) < CARD_W/2 and math.abs(ry) < CARD_H/2 then
                -- HIT
                if GameLogic.mode == "GUEST" then
                    local Network = require("network")
                    Network.sendGameMessage("host", { action = "PICK_CARD", targetIdx = targetIdx, cardIdx = j })
                else
                    OldMaid.pickCard(targetIdx, j)
                end
                break
            end
        elseif pos == "TOP" then 
            cxCard = cx - offset
            cyCard = 140
            local ca = math.cos(-rz)
            local sa = math.sin(-rz)
            local dx = x - cxCard
            local dy = y - cyCard
            local rx = dx * ca - dy * sa
            local ry = dx * sa + dy * ca
            if math.abs(rx) < CARD_W/2 and math.abs(ry) < CARD_H/2 then
                if GameLogic.mode == "GUEST" then
                    local Network = require("network")
                    Network.sendGameMessage("host", { action = "PICK_CARD", targetIdx = targetIdx, cardIdx = j })
                else
                    OldMaid.pickCard(targetIdx, j)
                end
                break
            end
        elseif pos == "RIGHT" then 
            cxCard = _G.getW() - 140
            cyCard = cy - offset
            local ca = math.cos(-(math.pi/2 + rz))
            local sa = math.sin(-(math.pi/2 + rz))
            local dx = x - cxCard
            local dy = y - cyCard
            local rx = dx * ca - dy * sa
            local ry = dx * sa + dy * ca
            if math.abs(rx) < CARD_W/2 and math.abs(ry) < CARD_H/2 then
                if GameLogic.mode == "GUEST" then
                    local Network = require("network")
                    Network.sendGameMessage("host", { action = "PICK_CARD", targetIdx = targetIdx, cardIdx = j })
                else
                    OldMaid.pickCard(targetIdx, j)
                end
                break
            end
        end
    end
end

function OldMaid.drawScoreboard(cx, cy, W, H)
    GameLogic.drawText("SCOREBOARD (Old Maid)", W - 295, 27, 280, "center", {1, 0.85, 0.3, 1})
    if not GameLogic.isScoreboardCollapsed then
        for i=1, 4 do
            local p = GameLogic.players[i]
            local pColor = (i == GameLogic.myPlayerIdx) and {0.35, 0.95, 0.45, 1} or {0.9, 0.9, 0.9, 1}
            GameLogic.drawTruncatedText(p.name, W - 295, 57 + (i*25), 180, "left", pColor)
            GameLogic.drawText(math.floor(p.score or 0), W - 115, 57 + (i*25), 100, "right", pColor)
        end
    else
        local myP = GameLogic.players[GameLogic.myPlayerIdx]
        if myP then
            GameLogic.drawTruncatedText(myP.name, W - 295, 57 + 25, 180, "left", {0.35, 0.95, 0.45, 1})
            GameLogic.drawText(math.floor(myP.score or 0), W - 115, 57 + 25, 100, "right", {0.35, 0.95, 0.45, 1})
        end
    end
end

function OldMaid.canPlayCard(card, playerHand)
    return false
end

return OldMaid
