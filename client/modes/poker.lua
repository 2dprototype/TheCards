local Poker = {}
local GameLogic = nil

local handRanks = {"High Card", "Pair", "Two Pair", "3 of a Kind", "Straight", "Flush", "Full House", "4 of a Kind", "Straight Flush"}
local rankValues = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}

function Poker.init(gl)
    GameLogic = gl
end

function Poker.startRound()
    GameLogic.phase = "DEALING"
    GameLogic.trick = {}
    Poker.communityCards = {}
    Poker.pot = 0
    Poker.currentBetToMatch = 0
    Poker.playersActedThisRound = 0
    
    for i=1, 4 do
        GameLogic.players[i].hand = {}
        GameLogic.players[i].currentBet = 0
        GameLogic.players[i].folded = false
        if not GameLogic.players[i].chips then
            GameLogic.players[i].chips = 1000
        end
    end
    
    local deck = GameLogic.generateDeck()
    GameLogic.shuffle(deck)
    Poker.deck = deck
    
    -- Deal 2 cards each
    for i=1, 8 do
        local pIdx = ((i - 1) % 4) + 1
        table.insert(GameLogic.players[pIdx].hand, table.remove(deck))
    end
    
    for i=1, 4 do
        for _, c in ipairs(GameLogic.players[i].hand) do
            local startX, startY = GameLogic.getPlayerAnchor(1)
            c.visX = startX
            c.visY = startY
        end
    end
    
    -- Blinds (assuming P1 is dealer conceptually for now, so P2 SB, P3 BB)
    Poker.dealerIdx = (GameLogic.roundNum % 4) + 1
    local sbIdx = (Poker.dealerIdx % 4) + 1
    local bbIdx = (sbIdx % 4) + 1
    
    -- Deduct blinds
    GameLogic.players[sbIdx].chips = GameLogic.players[sbIdx].chips - 10
    GameLogic.players[sbIdx].currentBet = 10
    GameLogic.players[bbIdx].chips = GameLogic.players[bbIdx].chips - 20
    GameLogic.players[bbIdx].currentBet = 20
    Poker.pot = 30
    Poker.currentBetToMatch = 20
    
    GameLogic.phase = "BETTING_PREFLOP"
    GameLogic.currentPlayer = (bbIdx % 4) + 1
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    Poker.playersActedThisRound = 0
    
    GameLogic.syncState()
end

function Poker.handleAction(playerIdx, action, amount)
    local p = GameLogic.players[playerIdx]
    if action == "FOLD" then
        p.folded = true
    elseif action == "CALL" then
        local toCall = Poker.currentBetToMatch - p.currentBet
        if toCall > p.chips then toCall = p.chips end -- all in
        p.chips = p.chips - toCall
        p.currentBet = p.currentBet + toCall
        Poker.pot = Poker.pot + toCall
    elseif action == "RAISE" then
        local totalBet = Poker.currentBetToMatch + (amount or 20)
        local toAdd = totalBet - p.currentBet
        if toAdd > p.chips then toAdd = p.chips end
        p.chips = p.chips - toAdd
        p.currentBet = p.currentBet + toAdd
        Poker.pot = Poker.pot + toAdd
        Poker.currentBetToMatch = p.currentBet
        Poker.currentBetToMatch = p.currentBet
    end
    Poker.playersActedThisRound = Poker.playersActedThisRound + 1
    Poker.advanceTurn()
end

function Poker.advanceTurn()
    -- Sub task: check if betting round is over
    -- If over, advance phase (FLOP, TURN, RIVER, SHOWDOWN)
    
    local activePlayers = 0
    local allMatched = true
    local lastActive = 1
    
    for i=1, 4 do
        local p = GameLogic.players[i]
        if not p.folded then
            activePlayers = activePlayers + 1
            lastActive = i
            if p.currentBet < Poker.currentBetToMatch and p.chips > 0 then
                allMatched = false
            end
        end
    end
    
    if activePlayers == 1 then
        -- Everyone else folded, lastActive wins
        Poker.awardPot(lastActive)
        return
    end
    
    if allMatched and Poker.playersActedThisRound >= activePlayers then
        -- Advance phase
        for i=1, 4 do GameLogic.players[i].currentBet = 0 end
        Poker.currentBetToMatch = 0
        Poker.playersActedThisRound = 0
        
        if GameLogic.phase == "BETTING_PREFLOP" then
            GameLogic.phase = "FLOP"
            for i=1, 3 do 
                local c = table.remove(Poker.deck)
                c.visX = _G.getW() / 2
                c.visY = -100
                table.insert(Poker.communityCards, c)
            end
            GameLogic.phase = "BETTING_FLOP"
            GameLogic.currentPlayer = (Poker.dealerIdx % 4) + 1
        elseif GameLogic.phase == "BETTING_FLOP" then
            local c = table.remove(Poker.deck)
            c.visX = _G.getW() / 2
            c.visY = -100
            table.insert(Poker.communityCards, c)
            GameLogic.phase = "BETTING_TURN"
            GameLogic.currentPlayer = (Poker.dealerIdx % 4) + 1
        elseif GameLogic.phase == "BETTING_TURN" then
            local c = table.remove(Poker.deck)
            c.visX = _G.getW() / 2
            c.visY = -100
            table.insert(Poker.communityCards, c)
            GameLogic.phase = "BETTING_RIVER"
            GameLogic.currentPlayer = (Poker.dealerIdx % 4) + 1
        elseif GameLogic.phase == "BETTING_RIVER" then
            GameLogic.phase = "SHOWDOWN"
            Poker.evaluateShowdown()
        end
        -- skip folded players
        while GameLogic.players[GameLogic.currentPlayer].folded do
            GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
        end
    else
        local originalPlayer = GameLogic.currentPlayer
        GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
        while GameLogic.players[GameLogic.currentPlayer].folded or (GameLogic.players[GameLogic.currentPlayer].chips == 0) do
            GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
            if GameLogic.currentPlayer == originalPlayer then break end
        end
    end
    GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    GameLogic.syncState()
end

function Poker.awardPot(winnerIdx)
    GameLogic.players[winnerIdx].chips = GameLogic.players[winnerIdx].chips + Poker.pot
    Poker.pot = 0
    GameLogic.phase = "ROUND_OVER"
    GameLogic.syncState()
end

local function getHandScore(hand5)
    local ranks = {}
    local suits = {}
    local rCounts = {}
    local sCounts = {}
    for i=1, 14 do rCounts[i] = 0 end
    for _, s in ipairs({"S", "H", "C", "D"}) do sCounts[s] = 0 end
    
    for _, c in ipairs(hand5) do
        local rVal = rankValues[c.rank] or 2
        table.insert(ranks, rVal)
        table.insert(suits, c.suit)
        rCounts[rVal] = rCounts[rVal] + 1
        sCounts[c.suit] = sCounts[c.suit] + 1
    end
    table.sort(ranks, function(a,b) return a > b end)
    
    local isFlush = false
    for _, count in pairs(sCounts) do if count == 5 then isFlush = true end end
    
    local isStraight = false
    local topStraight = 0
    if ranks[1] == ranks[2]+1 and ranks[2] == ranks[3]+1 and ranks[3] == ranks[4]+1 and ranks[4] == ranks[5]+1 then
        isStraight = true
        topStraight = ranks[1]
    elseif ranks[1] == 14 and ranks[2] == 5 and ranks[3] == 4 and ranks[4] == 3 and ranks[5] == 2 then
        isStraight = true
        topStraight = 5 -- A,2,3,4,5
    end
    
    local groups = {}
    for r=14, 2, -1 do
        if rCounts[r] > 0 then
            table.insert(groups, {rank=r, count=rCounts[r]})
        end
    end
    table.sort(groups, function(a,b)
        if a.count == b.count then return a.rank > b.rank end
        return a.count > b.count
    end)
    
    local typeRank = 0
    if isStraight and isFlush then typeRank = 8
    elseif groups[1].count == 4 then typeRank = 7
    elseif groups[1].count == 3 and groups[2].count == 2 then typeRank = 6
    elseif isFlush then typeRank = 5
    elseif isStraight then typeRank = 4
    elseif groups[1].count == 3 then typeRank = 3
    elseif groups[1].count == 2 and groups[2].count == 2 then typeRank = 2
    elseif groups[1].count == 2 then typeRank = 1
    end
    
    local score = {typeRank}
    if isStraight and not (typeRank == 6 or typeRank == 7) then
        table.insert(score, topStraight)
    else
        for _, g in ipairs(groups) do
            for i=1, g.count do table.insert(score, g.rank) end
        end
    end
    return score
end

local function getCombinations(arr, k)
    local result = {}
    local function comb(start_idx, current_combo)
        if #current_combo == k then
            table.insert(result, current_combo)
            return
        end
        for i = start_idx, #arr do
            local next_combo = {}
            for _, v in ipairs(current_combo) do table.insert(next_combo, v) end
            table.insert(next_combo, arr[i])
            comb(i + 1, next_combo)
        end
    end
    comb(1, {})
    return result
end

local function compareScores(s1, s2)
    for i=1, #s1 do
        if s1[i] > s2[i] then return 1
        elseif s1[i] < s2[i] then return -1
        end
    end
    return 0
end

function Poker.evaluateShowdown()
    local bestScores = {}
    for i=1, 4 do
        local p = GameLogic.players[i]
        if not p.folded then
            local pool = {}
            for _, c in ipairs(p.hand) do table.insert(pool, c) end
            for _, c in ipairs(Poker.communityCards) do table.insert(pool, c) end
            
            local combos = getCombinations(pool, 5)
            local bestScore = {-1}
            for _, cbo in ipairs(combos) do
                local sc = getHandScore(cbo)
                if compareScores(sc, bestScore) > 0 then
                    bestScore = sc
                end
            end
            bestScores[i] = {playerIdx=i, score=bestScore}
        end
    end
    
    local winners = {}
    local highest = {-1}
    for idx, bs in pairs(bestScores) do
        local cmp = compareScores(bs.score, highest)
        if cmp > 0 then
            highest = bs.score
            winners = {bs.playerIdx}
        elseif cmp == 0 then
            table.insert(winners, bs.playerIdx)
        end
    end
    
    local winSplit = math.floor(Poker.pot / #winners)
    for _, wIdx in ipairs(winners) do
        GameLogic.players[wIdx].chips = GameLogic.players[wIdx].chips + winSplit
    end
    Poker.pot = 0
    GameLogic.phase = "ROUND_OVER"
    GameLogic.syncState()
end

function Poker.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if not p.folded then
        -- basic bot just calls
        Poker.handleAction(GameLogic.currentPlayer, "CALL")
    else
        Poker.advanceTurn()
    end
end

function Poker.isBotTurn()
    if string.match(GameLogic.phase, "BETTING") then
        return GameLogic.players[GameLogic.currentPlayer].isBot
    end
    return false
end

function Poker.update(dt)
    if Poker.communityCards then
        local cx = _G.getW() / 2
        local cy = _G.getH() / 2
        local startX = cx - (#Poker.communityCards * 35) + 35
        local startY = cy - 40
        
        for i, c in ipairs(Poker.communityCards) do
            local targetX = startX + (i-1)*75
            local targetY = startY
            if not c.visX then c.visX = targetX; c.visY = targetY end
            
            c.visX = c.visX + (targetX - c.visX) * dt * 8
            c.visY = c.visY + (targetY - c.visY) * dt * 8
        end
    end
end

local chipColors = {
    {val=500, col={0.6, 0.1, 0.6, 1}},
    {val=100, col={0.2, 0.2, 0.2, 1}},
    {val=25, col={0.2, 0.8, 0.2, 1}},
    {val=5, col={0.8, 0.2, 0.2, 1}},
    {val=1, col={0.9, 0.9, 0.9, 1}}
}

local function drawChipStack(amount, x, y, spreadRight)
    local cx, cy = x, y
    local stackTotal = amount
    local hOffset = 0
    local zOffset = 0

    if stackTotal == 0 then return end
    
    for _, cv in ipairs(chipColors) do
        local num = math.floor(stackTotal / cv.val)
        stackTotal = stackTotal - (num * cv.val)
        
        for i=1, num do
            love.graphics.setColor(cv.col)
            love.graphics.circle("fill", cx + hOffset, cy - zOffset, 12)
            love.graphics.setColor(1, 1, 1, 0.5)
            love.graphics.circle("line", cx + hOffset, cy - zOffset, 12)
            love.graphics.setColor(1, 1, 1, 0.2)
            love.graphics.circle("line", cx + hOffset, cy - zOffset, 8)
            zOffset = zOffset + 3
            
            if zOffset > 15 then 
                hOffset = hOffset + (spreadRight and 14 or -14)
                zOffset = 0
            end
        end
    end
end

function Poker.drawScoreboard(cx, cy, W, H)
    local sbWidth = 280
    local sbHeight = 80 + (4 * 30)
    local sbX = W - sbWidth - 15
    local sbY = 15

    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 10)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 10)

    GameLogic.drawText("SCOREBOARD (Texas Hold'em)", sbX, sbY + 12, sbWidth, "center", {1, 0.85, 0.3, 1})
    
    local scoreY = sbY + 50
    for i=1, 4 do
        local p = GameLogic.players[i]
        local pColor = p.folded and {0.5, 0.5, 0.5, 1} or {1, 1, 1, 1}
        local nameStr = (i == Poker.dealerIdx and "*D* " or "") .. p.name
        
        GameLogic.drawText(nameStr .. ": $" .. tostring(p.chips), sbX + 15, scoreY, 200, "left", pColor)
        
        if p.folded then
            GameLogic.drawText("[FOLDED]", sbX + 180, scoreY, 80, "left", {0.8, 0.3, 0.3, 1})
        elseif p.currentBet > 0 then
            GameLogic.drawText("Bet: $" .. p.currentBet, sbX + 180, scoreY, 80, "left", {0.4, 0.9, 0.4, 1})
        end
        scoreY = scoreY + 30
    end
    
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.rectangle("line", sbX + 15, scoreY + 10, sbWidth - 30, 40, 5)
    GameLogic.drawText("CURRENT POT: $" .. Poker.pot, sbX + 15, scoreY + 20, sbWidth - 30, "center", {1, 0.85, 0.2, 1})
end

function Poker.drawCallingUI(cx, cy, W, H)
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.myPlayerIdx].isBot then
        -- Draw FOLD / CALL / RAISE
        local startX = cx - 150
        local startY = cy + 50
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local toCall = Poker.currentBetToMatch - p.currentBet
        local callStr = (toCall == 0) and "CHECK" or ("CALL $" .. toCall)
        
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", startX, startY, 80, 40, 8)
        GameLogic.drawText("FOLD", startX, startY + 10, 80, "center")
        
        love.graphics.setColor(0.2, 0.8, 0.2, 1)
        love.graphics.rectangle("fill", startX + 100, startY, 80, 40, 8)
        GameLogic.drawText(callStr, startX + 100, startY + 10, 80, "center")
        
        love.graphics.setColor(0.2, 0.2, 0.8, 1)
        love.graphics.rectangle("fill", startX + 200, startY, 80, 40, 8)
        GameLogic.drawText("RAISE $20", startX + 200, startY + 10, 80, "center")
    end
    
    -- Draw Community Cards
    if Poker.communityCards and #Poker.communityCards > 0 then
        for i, c in ipairs(Poker.communityCards) do
            GameLogic.drawCard(c, c.visX, c.visY, true)
        end
    end
    
    -- Draw Player Chips on Table
    for i=1, 4 do
        local px, py = GameLogic.getPlayerAnchor(i)
        local p = GameLogic.players[i]
        
        -- Adjust to sit in front of players on table
        local cx = px
        local cy = py
        
        if GameLogic.myPlayerIdx == i then cy = cy - 40
        elseif GameLogic.myPlayerIdx == (i-1 == 0 and 4 or i-1) then cx = cx + 80
        elseif GameLogic.myPlayerIdx == (i-2 <= 0 and i+2 or i-2) then cy = cy + 120
        elseif GameLogic.myPlayerIdx == (i+1 == 5 and 1 or i+1) then cx = cx - 80 end
        
        if p.currentBet > 0 then
            drawChipStack(p.currentBet, cx, cy, true)
            GameLogic.drawText("$"..p.currentBet, cx - 25, cy + 10, 50, "center", {1, 1, 1, 1})
        end
        
        -- Dealer Button
        if Poker.dealerIdx == i then
            love.graphics.setColor(0.9, 0.9, 0.9, 1)
            love.graphics.circle("fill", cx - 30, cy, 14)
            love.graphics.setColor(0.1, 0.1, 0.1, 1)
            love.graphics.circle("line", cx - 30, cy, 14, 3)
            GameLogic.drawText("D", cx - 40, cy - 6, 20, "center", {0.1, 0.1, 0.1, 1})
        end
    end
    
    -- Draw Pot in center
    if Poker.pot > 0 then
        drawChipStack(Poker.pot, cx - 40, cy - 140, true)
        GameLogic.drawText("POT: $"..Poker.pot, cx - 100, cy - 120, 120, "center", {1, 0.85, 0.2, 1})
    end
end

function Poker.mousepressed(x, y, button)
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx then
        local startX = cx - 150
        local startY = cy + 50
        if x >= startX and x <= startX + 80 and y >= startY and y <= startY + 40 then
            -- FOLD
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="FOLD"})
            else Poker.handleAction(GameLogic.myPlayerIdx, "FOLD") end
        elseif x >= startX + 100 and x <= startX + 180 and y >= startY and y <= startY + 40 then
            -- CALL
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="CALL"})
            else Poker.handleAction(GameLogic.myPlayerIdx, "CALL") end
        elseif x >= startX + 200 and x <= startX + 280 and y >= startY and y <= startY + 40 then
            -- RAISE
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="RAISE", amount=20})
            else Poker.handleAction(GameLogic.myPlayerIdx, "RAISE", 20) end
        end
    end
end

function Poker.canPlayCard(card, hand) return false end -- No playing from hand

-- Expose to engine sync
function Poker.applyStateExt(state)
    Poker.communityCards = state.communityCards or {}
    Poker.pot = state.pot or 0
    Poker.currentBetToMatch = state.currentBetToMatch or 0
    Poker.dealerIdx = state.dealerIdx or 1
    Poker.playersActedThisRound = state.playersActedThisRound or 0
end

function Poker.getStateExt(state)
    state.communityCards = Poker.communityCards
    state.pot = Poker.pot
    state.currentBetToMatch = Poker.currentBetToMatch
    state.dealerIdx = Poker.dealerIdx
    state.playersActedThisRound = Poker.playersActedThisRound
end

function Poker.handleNetworkMessage(evt)
    if evt.data.action == "POKER_ACTION" then
        for i=1, 4 do
            if GameLogic.players[i].id == evt.clientId and i == GameLogic.currentPlayer and string.match(GameLogic.phase, "BETTING") then
                Poker.handleAction(i, evt.data.type, evt.data.amount)
                return true
            end
        end
    end
    return false
end

function Poker.getPlayerStateExt(p, pSafe)
    pSafe.chips = p.chips
    pSafe.currentBet = p.currentBet
    pSafe.folded = p.folded
end

function Poker.applyPlayerStateExt(pSafe, p)
    p.chips = pSafe.chips or 0
    p.currentBet = pSafe.currentBet or 0
    p.folded = pSafe.folded or false
end

return Poker
