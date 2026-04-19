local CallBridge = {}
local GameLogic = nil

local rankValues = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}

function CallBridge.init(gl)
    GameLogic = gl
end

function CallBridge.botMakeCall(hand)
    local call = 0
    local counts = {S=0, H=0, D=0, C=0}
    for _, card in ipairs(hand) do
        counts[card.suit] = counts[card.suit] + 1
        if card.rank == "A" then call = call + 1
        elseif card.rank == "K" then call = call + 0.5
        elseif card.rank == "Q" and card.suit == "S" then call = call + 0.5
        end
    end
    if counts["S"] > 4 then call = call + (counts["S"] - 4) end
    call = math.floor(call + 0.5)
    if call < 1 then call = 1 end
    if call > 8 then call = 8 end
    return call
end

function CallBridge.botPlayCard(hand, trickLeadSuit, trick, myCall, myTricksWon)
    local validCards = {}
    if trickLeadSuit then
        for _, card in ipairs(hand) do
            if card.suit == trickLeadSuit then table.insert(validCards, card) end
        end
    end
    if #validCards == 0 then
        for _, card in ipairs(hand) do table.insert(validCards, card) end
    end
    
    local needTricks = (myTricksWon or 0) < (myCall or 1)
    local bestCard = nil
    if trick and #trick > 0 then
        bestCard = trick[1].card
        for i = 2, #trick do
            local c = trick[i].card
            local isSpade = (c.suit == "S")
            local bestIsSpade = (bestCard.suit == "S")
            if isSpade and not bestIsSpade then bestCard = c
            elseif isSpade and bestIsSpade and rankValues[c.rank] > rankValues[bestCard.rank] then bestCard = c
            elseif c.suit == trickLeadSuit and bestCard.suit == trickLeadSuit and rankValues[c.rank] > rankValues[bestCard.rank] then bestCard = c
            end
        end
    end
    
    table.sort(validCards, function(a, b) 
        local aVal = rankValues[a.rank] + (a.suit == "S" and 20 or 0)
        local bVal = rankValues[b.rank] + (b.suit == "S" and 20 or 0)
        return aVal < bVal
    end)
    
    local chosenCard = validCards[1]
    if needTricks then
        if not bestCard then
            local tempValid = {}
            for _, v in ipairs(validCards) do table.insert(tempValid, v) end
            table.sort(tempValid, function(a,b) return rankValues[a.rank] < rankValues[b.rank] end)
            chosenCard = tempValid[#tempValid]
        else
            local winningCards = {}
            for _, c in ipairs(validCards) do
                local canWin = false
                if c.suit == "S" and bestCard.suit ~= "S" then canWin = true
                elseif c.suit == "S" and bestCard.suit == "S" and rankValues[c.rank] > rankValues[bestCard.rank] then canWin = true
                elseif c.suit == trickLeadSuit and bestCard.suit == trickLeadSuit and rankValues[c.rank] > rankValues[bestCard.rank] then canWin = true
                end
                if canWin then table.insert(winningCards, c) end
            end
            if #winningCards > 0 then chosenCard = winningCards[1] end
        end
    else
        chosenCard = validCards[1]
    end
    
    for i, c in ipairs(hand) do
        if c.suit == chosenCard.suit and c.rank == chosenCard.rank then
            return i, c
        end
    end
end

function CallBridge.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if GameLogic.phase == "CALLING" then
        p.call = CallBridge.botMakeCall(p.hand)
        GameLogic.advanceTurn()
    elseif GameLogic.phase == "PLAYING" then
        local idx, card = CallBridge.botPlayCard(p.hand, GameLogic.trickLeadSuit, GameLogic.trick, p.call, p.tricksWon)
        GameLogic.playCard(GameLogic.currentPlayer, idx)
    end
end

function CallBridge.resolveTrick()
    local winnerIdx = GameLogic.trick[1].playerIdx
    local bestCard = GameLogic.trick[1].card
    
    for i = 2, 4 do
        local currentEntry = GameLogic.trick[i]
        local c = currentEntry.card
        local pIdx = currentEntry.playerIdx
        
        if c.suit == "S" and bestCard.suit ~= "S" then
            bestCard = c
            winnerIdx = pIdx
        elseif c.suit == "S" and bestCard.suit == "S" then
            if rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c
                winnerIdx = pIdx
            end
        elseif c.suit ~= "S" and bestCard.suit ~= "S" then
            if c.suit == GameLogic.trickLeadSuit then
                if bestCard.suit ~= GameLogic.trickLeadSuit then
                    bestCard = c
                    winnerIdx = pIdx
                elseif rankValues[c.rank] > rankValues[bestCard.rank] then
                    bestCard = c
                    winnerIdx = pIdx
                end
            end
        end
    end
    
    GameLogic.players[winnerIdx].tricksWon = GameLogic.players[winnerIdx].tricksWon + 1
    
    for _, t in ipairs(GameLogic.trick) do
        table.insert(GameLogic.flyingCards, { card = t.card, targetId = winnerIdx }) 
    end
    
    GameLogic.trick = {}
    GameLogic.trickLeadSuit = nil
    
    GameLogic.currentPlayer = winnerIdx
    GameLogic.phase = "PLAYING"
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    
    local cardsLeft = #GameLogic.players[1].hand
    if cardsLeft == 0 then
        GameLogic.phase = "ROUND_OVER"
        CallBridge.calculateScores()
    end
    
    GameLogic.syncState()
end

function CallBridge.calculateScores()
    for i=1, 4 do
        local p = GameLogic.players[i]
        if p.tricksWon >= p.call then
            p.score = p.score + p.call + ((p.tricksWon - p.call) * 0.1)
        else
            p.score = p.score - p.call
        end
    end
end

function CallBridge.update(dt)
    -- Handles mode-specific evaluation phases
    if GameLogic.phase == "EVAL_TRICK" then
        if not GameLogic.evalTimer then GameLogic.evalTimer = 0 end
        GameLogic.evalTimer = GameLogic.evalTimer + dt
        if GameLogic.evalTimer > 2.0 then
            GameLogic.evalTimer = 0
            if GameLogic.mode ~= "GUEST" then
                CallBridge.resolveTrick()
            end
        end
    end
end

function CallBridge.drawScoreboard(cx, cy, W, H)
    if not GameLogic.sbFont then
        local currentSize = love.graphics.getFont():getHeight()
        GameLogic.sbFont = love.graphics.newFont(math.max(10, math.floor(currentSize * 0.85)))
    end
    local oldFont = love.graphics.getFont()
    love.graphics.setFont(GameLogic.sbFont)

    local isCollapsed = GameLogic.isScoreboardCollapsed
    local sbWidth = 240
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
        local colName  = 10
        local colCall  = 110
        local colTrick = 150
        local colScore = 190

        local labelY = sbY + 28
        local labelColor = {0.6, 0.6, 0.6, 1}
        GameLogic.drawText("Player", sbX + colName, labelY, 90, "left", labelColor)
        GameLogic.drawText("C",      sbX + colCall, labelY, 35,  "center", labelColor)
        GameLogic.drawText("T",      sbX + colTrick, labelY, 35, "center", labelColor)
        GameLogic.drawText("Pts",    sbX + colScore, labelY, 40, "right", labelColor)

        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.line(sbX + 10, sbY + 45, sbX + sbWidth - 10, sbY + 45)

        local scoreY = sbY + 52
        for i = 1, 4 do
            local p = GameLogic.players[i]
            local isCurrent = (i == GameLogic.currentPlayer)
            if isCurrent then
                love.graphics.setColor(1, 1, 1, 0.05)
                love.graphics.rectangle("fill", sbX + 5, scoreY - 2, sbWidth - 10, 20, 4)
            end
            local pColor = isCurrent and {0.3, 0.95, 0.4, 1} or {0.95, 0.95, 0.95, 1}
            GameLogic.drawTruncatedText(p.name, sbX + colName, scoreY, colCall - colName - 5, "left", pColor)
            GameLogic.drawText(tostring(p.call or 0), sbX + colCall, scoreY, 35, "center", pColor)
            GameLogic.drawText(tostring(p.tricksWon or 0), sbX + colTrick, scoreY, 35, "center", pColor)
            GameLogic.drawText(string.format("%.1f", p.score or 0), sbX + colScore, scoreY, 40, "right", pColor)
            scoreY = scoreY + 24
        end
    end

    love.graphics.setFont(oldFont)
end

function CallBridge.drawCallingUI(cx, cy, W, H)
    if GameLogic.phase == "CALLING" and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.currentPlayer].isBot then
        local boxW = 8 * 55
        local startX = cx - (boxW / 2)
        local startY = cy + 50
        
        love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
        love.graphics.rectangle("fill", startX - 20, startY - 40, boxW + 40, 110, 12)
        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.rectangle("line", startX - 20, startY - 40, boxW + 40, 110, 12)

        GameLogic.drawText("Make Your Call:", 0, startY - 25, W, "center", {1, 1, 1, 1})

        local mx, my = love.mouse.getPosition()
        for i = 1, 8 do
            local bx = startX + (i-1)*55
            local by = startY
            local hover = mx >= bx and mx <= bx + 45 and my >= by and my <= by + 45
            if hover then
                love.graphics.setColor(0.3, 0.95, 0.4, 1)
            else
                love.graphics.setColor(0.2, 0.2, 0.3, 1)
            end
            love.graphics.rectangle("fill", bx, by, 45, 45, 8)
            love.graphics.setColor(1, 1, 1, 1)
            GameLogic.drawText(tostring(i), bx, by + 12, 45, "center")
        end
    end
end

function CallBridge.mousepressed(x, y, button)
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    local W = _G.getW()
    local sbWidth = 240
    local sbX = W - sbWidth - 15
    local sbY = 15
    if x >= sbX and x <= sbX + sbWidth and y >= sbY and y <= sbY + 30 then
        GameLogic.isScoreboardCollapsed = not GameLogic.isScoreboardCollapsed
        return
    end

    if GameLogic.phase == "CALLING" and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.currentPlayer].isBot then
        local boxW = 8 * 55
        local startX = cx - (boxW / 2)
        local startY = cy + 50
        for i = 1, 8 do
            local bx = startX + (i-1)*55
            local by = startY
            if x >= bx and x <= bx + 45 and y >= by and y <= by + 45 then
                local Network = require("network")
                if GameLogic.mode == "GUEST" then
                    Network.sendGameMessage("host", { action = "MAKE_CALL", call = i })
                else
                    GameLogic.players[GameLogic.myPlayerIdx].call = i
                    GameLogic.advanceTurn()
                end
                break
            end
        end
    end
end

-- Validate if card can be played (returns true/false)
function CallBridge.canPlayCard(card, playerHand)
    if GameLogic.phase == "PLAYING" and GameLogic.trickLeadSuit then
        if card.suit ~= GameLogic.trickLeadSuit then
            for _, hc in ipairs(playerHand) do
                if hc.suit == GameLogic.trickLeadSuit then
                    return false
                end
            end
        end
    end
    return true
end

return CallBridge
