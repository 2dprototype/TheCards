local OldMaid = {}
local GameLogic = nil

local suits = {"S", "H", "D", "C"}
local ranks = {"2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"}

OldMaid.finishOrder = {}
OldMaid.discardPile = {}
local pendingPickedCard = nil

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
        local rv = {["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,["9"]=9,["10"]=10,["J"]=11,["Q"]=12,["K"]=13,["A"]=14}
        return rv[a.rank] > rv[b.rank]
    end)
end

function OldMaid.startRound()
    GameLogic.trick = {}
    GameLogic.flyingCards = {}
    OldMaid.finishOrder = {}
    OldMaid.discardPile = {}
    pendingPickedCard = nil
    
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
    
    GameLogic.phase = "PICKING"
    GameLogic.currentPlayer = (GameLogic.roundNum % 4) + 1
    if GameLogic.currentPlayer > 4 then GameLogic.currentPlayer = 1 end
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    
    GameLogic.syncState()
end

local function getColor(suit)
    if suit == "S" or suit == "C" then return "BLACK" end
    if suit == "H" or suit == "D" then return "RED" end
    return "JOKER"
end

function OldMaid.checkAndDiscard(playerIdx, pickedCard)
    local hand = GameLogic.players[playerIdx].hand
    if not hand or not pickedCard then return false end
    
    local matchIdx = -1
    local pickedIdx = -1
    
    local pickedSig = pickedCard.rank .. "_" .. getColor(pickedCard.suit)
    
    for i, c in ipairs(hand) do
        if c == pickedCard then
            pickedIdx = i
        elseif c.suit ~= "JOKER" and c.rank .. "_" .. getColor(c.suit) == pickedSig then
            matchIdx = i
        end
    end
    
    if matchIdx ~= -1 and pickedIdx ~= -1 then
        local maxI = math.max(pickedIdx, matchIdx)
        local minI = math.min(pickedIdx, matchIdx)
        local c1 = table.remove(hand, maxI)
        local c2 = table.remove(hand, minI)
        
        local cx, cy = _G.getW() / 2, _G.getH() / 2
        local px, py = GameLogic.getPlayerAnchor(playerIdx)
        
        for _, c in ipairs({c1, c2}) do
            if playerIdx ~= GameLogic.myPlayerIdx then
                c.visX, c.visY = px, py
            end
            c.destX = cx + math.random(-80, 80)
            c.destY = cy + math.random(-60, 60)
            c.destRot = math.random() * math.pi * 2
            table.insert(GameLogic.flyingCards, { card = c, targetId = "CENTER" })
            table.insert(OldMaid.discardPile, c)
        end
        return true
    end
    return false
end

function OldMaid.checkPlacements()
    for i=1, 4 do
        local hSize = GameLogic.players[i].handSize or (GameLogic.players[i].hand and #GameLogic.players[i].hand) or 0
        if hSize == 0 then
            local found = false
            for _, fIdx in ipairs(OldMaid.finishOrder) do
                if fIdx == i then found = true; break end
            end
            if not found then
                table.insert(OldMaid.finishOrder, i)
            end
        end
    end
end

function OldMaid.checkForMatchOver()
    if GameLogic.phase == "MATCH_OVER" then return end
    
    OldMaid.checkPlacements()
    
    if #OldMaid.finishOrder >= 3 then
        local loserIdx = 0
        for i=1, 4 do
            local found = false
            for _, fIdx in ipairs(OldMaid.finishOrder) do
                if fIdx == i then found = true; break end
            end
            if not found then loserIdx = i; break end
        end
        
        table.insert(OldMaid.finishOrder, loserIdx)
        
        for placement, pIdx in ipairs(OldMaid.finishOrder) do
            if placement == 1 then GameLogic.players[pIdx].score = 100
            elseif placement == 2 then GameLogic.players[pIdx].score = 75
            elseif placement == 3 then GameLogic.players[pIdx].score = 50
            elseif placement == 4 then GameLogic.players[pIdx].score = 0 end
        end
        
        GameLogic.phase = "MATCH_OVER"
        GameLogic.syncState()
    end
end

function OldMaid.getTargetPlayer(curr)
    local p = curr - 1
    if p < 1 then p = 4 end
    
    while true do
        local isFinished = false
        for _, fIdx in ipairs(OldMaid.finishOrder) do
            if fIdx == p then isFinished = true; break end
        end
        
        if not isFinished then return p end
        
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
        local isFinished = false
        for _, fIdx in ipairs(OldMaid.finishOrder) do
            if fIdx == GameLogic.currentPlayer then isFinished = true; break end
        end
        
        if not isFinished then break end
        
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
    
    if GameLogic.phase == "PICKING_ANIMATION" then
        if #GameLogic.flyingCards == 0 then
            if pendingPickedCard then
                table.insert(GameLogic.players[GameLogic.currentPlayer].hand, pendingPickedCard)
                OldMaid.sortHand(GameLogic.players[GameLogic.currentPlayer].hand)
            end
            GameLogic.phase = "CHECK_PAIR"
            GameLogic.turnTimer = 0.8
            GameLogic.syncState()
        end
    elseif GameLogic.phase == "CHECK_PAIR" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                local didDiscard = false
                if pendingPickedCard then
                    didDiscard = OldMaid.checkAndDiscard(GameLogic.currentPlayer, pendingPickedCard)
                    pendingPickedCard = nil
                end
                
                OldMaid.checkPlacements()
                if didDiscard then
                    GameLogic.phase = "ADVANCE_TURN_ANIM"
                else
                    GameLogic.phase = "PICKING"
                    OldMaid.advanceTurn()
                end
            end
        end
    elseif GameLogic.phase == "ADVANCE_TURN_ANIM" then
        if #GameLogic.flyingCards == 0 then
            GameLogic.phase = "PICKING"
            OldMaid.advanceTurn()
        end
    end
    
    for _, c in ipairs(OldMaid.discardPile) do
        if c.destX and c.destY then
            c.visX = c.visX + (c.destX - c.visX) * dt * 5
            c.visY = c.visY + (c.destY - c.visY) * dt * 5
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
    
    pendingPickedCard = c
    table.insert(GameLogic.flyingCards, { card = c, targetId = GameLogic.currentPlayer, sourceId = targetIdx })
    
    GameLogic.phase = "PICKING_ANIMATION"
    GameLogic.turnTimer = 2.0
    GameLogic.syncState()
end

function OldMaid.getStateExt(state)
    state.finishOrder = OldMaid.finishOrder
    state.discardPile = OldMaid.discardPile
end

function OldMaid.applyStateExt(state)
    if state.finishOrder then
        OldMaid.finishOrder = state.finishOrder
    end
    if state.discardPile then
        OldMaid.discardPile = state.discardPile
    end
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
    
    for j = hSize, 1, -1 do
        local offset = (j - hSize/2) * 12
        local cxCard, cyCard = lx, ly
        
        if pos == "LEFT" then 
            cxCard = 140
            cyCard = cy + offset
            local ca = math.cos(-(math.pi/2))
            local sa = math.sin(-(math.pi/2))
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
        elseif pos == "TOP" then 
            cxCard = cx - offset
            cyCard = 140
            local ca = math.cos(0)
            local sa = math.sin(0)
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
            local ca = math.cos(-(-math.pi/2))
            local sa = math.sin(-(-math.pi/2))
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

function OldMaid.drawCallingUI(cx, cy, W, H)
    for _, c in ipairs(OldMaid.discardPile) do
        love.graphics.push()
        love.graphics.translate(c.visX or cx, c.visY or cy)
        if c.destRot then love.graphics.rotate(c.destRot) end
        
        GameLogic.drawCard(c, -35, -50, true)
        
        love.graphics.pop()
    end
end

function OldMaid.drawScoreboard(cx, cy, W, H)
    if not GameLogic.sbFont then
        local currentSize = love.graphics.getFont():getHeight()
        GameLogic.sbFont = love.graphics.newFont(math.max(10, math.floor(currentSize * 0.85)))
    end
    local oldFont = love.graphics.getFont()
    love.graphics.setFont(GameLogic.sbFont)

    local isCollapsed = GameLogic.isScoreboardCollapsed

    local sbWidth = 260
    local sbHeight = isCollapsed and 30 or (60 + (4 * 24))
    local sbX = W - sbWidth - 15
    local sbY = 15

    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 8)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 8)

    local btnText = isCollapsed and "[+] SCOREBOARD (Tab)" or "[-] SCOREBOARD (Tab)"
    love.graphics.setColor(1, 0.85, 0.3, 1)
    love.graphics.printf(btnText, sbX, sbY + 8, sbWidth, "center")

    if not isCollapsed then
        local colName = 10
        local colStatus = 140

        local labelY = sbY + 28
        local labelColor = {0.6, 0.6, 0.6, 1}
        GameLogic.drawText("Player", sbX + colName, labelY, 110, "left", labelColor)
        GameLogic.drawText("Status/Cards",  sbX + colStatus, labelY, 110, "right", labelColor)

        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.line(sbX + 10, sbY + 45, sbX + sbWidth - 10, sbY + 45)

        local scoreY = sbY + 52
        for i = 1, 4 do
            local p = GameLogic.players[i]
            local isCurrent = (i == GameLogic.currentPlayer and GameLogic.phase ~= "ROUND_OVER" and GameLogic.phase ~= "MATCH_OVER")
            if isCurrent then
                love.graphics.setColor(1, 1, 1, 0.05)
                love.graphics.rectangle("fill", sbX + 5, scoreY - 2, sbWidth - 10, 20, 4)
            end
            
            local pColor = isCurrent and {0.3, 0.95, 0.4, 1} or {1, 1, 1, 1}
            GameLogic.drawTruncatedText(p.name, sbX + colName, scoreY, 120, "left", pColor)
            
            local txt = ""
            local hSize = p.handSize or (p.hand and #p.hand) or 0
            if hSize > 0 then
                txt = "Cards: " .. hSize
            else
                local place = 0
                for rank, fIdx in ipairs(OldMaid.finishOrder) do
                    if fIdx == i then place = rank; break end
                end
                if place == 1 then txt = "1st" pColor = {1, 0.8, 0.2, 1}
                elseif place == 2 then txt = "2nd" pColor = {0.8, 0.8, 0.8, 1}
                elseif place == 3 then txt = "3rd" pColor = {0.8, 0.5, 0.2, 1}
                elseif place == 4 then txt = "4th (Loser)" pColor = {1, 0.3, 0.3, 1}
                else txt = "Safe" end
            end
            
            GameLogic.drawText(txt, sbX + colStatus, scoreY, 110, "right", pColor)
            scoreY = scoreY + 24
        end
    end

    love.graphics.setFont(oldFont)
end

function OldMaid.canPlayCard(card, playerHand)
    return false
end

return OldMaid
