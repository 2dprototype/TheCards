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
        -- Initialize animation variables
        GameLogic.players[i].visChips = GameLogic.players[i].chips
        GameLogic.players[i].visBet = 0
    end
    
    Poker.visPot = 0
    
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
    
    -- If 1 or 0 players have chips, match is over!
    local activePlayersStart = 0
    for i=1, 4 do if GameLogic.players[i].chips > 0 then activePlayersStart = activePlayersStart + 1 end end
    
    if activePlayersStart <= 1 then
        GameLogic.phase = "MATCH_OVER"
        GameLogic.syncState()
        return
    end

    -- Blinds
    Poker.dealerIdx = (GameLogic.roundNum % 4) + 1
    local loops = 0
    while GameLogic.players[Poker.dealerIdx].chips <= 0 and loops < 4 do
        Poker.dealerIdx = (Poker.dealerIdx % 4) + 1
        loops = loops + 1
    end
    
    local sbIdx = (Poker.dealerIdx % 4) + 1
    loops = 0
    while GameLogic.players[sbIdx].chips <= 0 and loops < 4 do
        sbIdx = (sbIdx % 4) + 1
        loops = loops + 1
    end
    
    local bbIdx = (sbIdx % 4) + 1
    loops = 0
    while GameLogic.players[bbIdx].chips <= 0 and loops < 4 do
        bbIdx = (bbIdx % 4) + 1
        loops = loops + 1
    end
    
    -- Deduct blinds gracefully (prevent negative)
    local sbAmount = math.min(10, GameLogic.players[sbIdx].chips)
    GameLogic.players[sbIdx].chips = GameLogic.players[sbIdx].chips - sbAmount
    GameLogic.players[sbIdx].currentBet = sbAmount
    
    local bbAmount = math.min(20, GameLogic.players[bbIdx].chips)
    GameLogic.players[bbIdx].chips = GameLogic.players[bbIdx].chips - bbAmount
    GameLogic.players[bbIdx].currentBet = bbAmount
    
    Poker.pot = sbAmount + bbAmount
    Poker.currentBetToMatch = math.max(sbAmount, bbAmount)
    
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
    end
    Poker.playersActedThisRound = Poker.playersActedThisRound + 1
    Poker.advanceTurn()
end

function Poker.advanceTurn()
    local activePlayers = 0
    local bettingPlayers = 0
    local allMatched = true
    local lastActive = 1
    
    for i=1, 4 do
        local p = GameLogic.players[i]
        if not p.folded and p.chips ~= nil then
            activePlayers = activePlayers + 1
            lastActive = i
            if p.chips > 0 then
                bettingPlayers = bettingPlayers + 1
                if p.currentBet < Poker.currentBetToMatch then
                    allMatched = false
                end
            end
        end
    end
    
    if activePlayers == 1 then
        Poker.awardPot(lastActive)
        return
    end

    -- If 0 or 1 players can still bet (others are all-in), we automatically advance phases if matching is done
    if bettingPlayers <= 1 and allMatched then
        Poker.playersActedThisRound = 99 -- force phase advance
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
        -- skip folded or all-in players
        local safeLoops = 0
        while (GameLogic.players[GameLogic.currentPlayer].folded or GameLogic.players[GameLogic.currentPlayer].chips <= 0) and safeLoops < 4 do
            GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
            safeLoops = safeLoops + 1
        end
    else
        local originalPlayer = GameLogic.currentPlayer
        GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
        while GameLogic.players[GameLogic.currentPlayer].folded or (GameLogic.players[GameLogic.currentPlayer].chips <= 0) do
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
    
    if #winners > 0 then
        local winSplit = math.floor(Poker.pot / #winners)
        for _, wIdx in ipairs(winners) do
            GameLogic.players[wIdx].chips = GameLogic.players[wIdx].chips + winSplit
        end
    end
    Poker.pot = 0
    GameLogic.phase = "ROUND_OVER"
    GameLogic.syncState()
end

function Poker.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if not p.folded then
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
    -- Card sliding animations
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

    -- Dynamic Chip Animations (Stacks build up/down smoothly)
    local animSpeed = 5
    if not Poker.visPot then Poker.visPot = Poker.pot or 0 end
    Poker.visPot = Poker.visPot + ((Poker.pot or 0) - Poker.visPot) * dt * animSpeed

    for i=1, 4 do
        local p = GameLogic.players[i]
        if p then
            if not p.visChips then p.visChips = p.chips or 0 end
            if not p.visBet then p.visBet = p.currentBet or 0 end
            
            p.visChips = p.visChips + ((p.chips or 0) - p.visChips) * dt * animSpeed
            p.visBet = p.visBet + ((p.currentBet or 0) - p.visBet) * dt * animSpeed
        end
    end
end

local chipColors = {
    {val=100, col={0.15, 0.15, 0.15, 1}},-- Black
    {val=25, col={0.1, 0.6, 0.2, 1}},   -- Casino Green
    {val=5, col={0.8, 0.15, 0.15, 1}},  -- Red
    {val=1, col={0.9, 0.9, 0.9, 1}}     -- White
}

local function drawChipStack(amount, x, y, spreadRight)
    local cx, cy = x, y
    local stackTotal = amount
    local hOffset = 0
    local zOffset = 0
    local chipsInStack = 0

    if stackTotal < 1 then return end
    
    for _, cv in ipairs(chipColors) do
        local num = math.floor(stackTotal / cv.val)
        stackTotal = stackTotal - (num * cv.val)
        
        for i=1, num do
            -- Drop Shadow
            love.graphics.setColor(0, 0, 0, 0.4)
            love.graphics.circle("fill", cx + hOffset + 2, cy - zOffset + 2, 12)

            -- Base Chip Color
            love.graphics.setColor(cv.col)
            love.graphics.circle("fill", cx + hOffset, cy - zOffset, 12)
            
            -- Casino Edge Stripes
            love.graphics.setColor(1, 1, 1, 0.6)
            love.graphics.setLineWidth(2)
            love.graphics.line(cx + hOffset - 12, cy - zOffset, cx + hOffset - 7, cy - zOffset)
            love.graphics.line(cx + hOffset + 7, cy - zOffset, cx + hOffset + 12, cy - zOffset)
            love.graphics.line(cx + hOffset, cy - zOffset - 12, cx + hOffset, cy - zOffset - 7)
            love.graphics.line(cx + hOffset, cy - zOffset + 7, cx + hOffset, cy - zOffset + 12)
            love.graphics.setLineWidth(1)
            
            -- Inner detailing
            love.graphics.setColor(cv.col)
            love.graphics.circle("fill", cx + hOffset, cy - zOffset, 8)
            love.graphics.setColor(1, 1, 1, 0.3)
            love.graphics.circle("line", cx + hOffset, cy - zOffset, 8)
            love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
            love.graphics.circle("line", cx + hOffset, cy - zOffset, 12)
            
            zOffset = zOffset + 3
            chipsInStack = chipsInStack + 1
            
            -- Build stacks 6 high before spreading out to make money look more substantial
            if chipsInStack >= 6 then 
                hOffset = hOffset + (spreadRight and 26 or -26)
                zOffset = 0
                chipsInStack = 0
            end
        end
    end
end

function Poker.drawScoreboard(cx, cy, W, H)
    -- Increased width and height to prevent squishing
    local sbWidth = 340
    local sbHeight = 100 + (4 * 35)
    local sbX = W - sbWidth - 20
    local sbY = 20

    -- Background
    love.graphics.setColor(0.05, 0.05, 0.1, 0.85)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 10)
    love.graphics.setColor(1, 1, 1, 0.15)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 10)

    -- Header
    GameLogic.drawText("SCOREBOARD (Texas Hold'em)", sbX, sbY + 12, sbWidth, "center", {1, 0.85, 0.3, 1})
    
    -- Entries
    local scoreY = sbY + 50
    for i=1, 4 do
        local p = GameLogic.players[i]
        local pColor = p.folded and {0.5, 0.5, 0.5, 1} or {1, 1, 1, 1}
        local nameStr = (i == Poker.dealerIdx and "[D] " or "") .. p.name
        
        -- Strict columns prevent text overlap
        GameLogic.drawText(nameStr, sbX + 15, scoreY, 130, "left", pColor)
        GameLogic.drawText("$" .. tostring(p.chips), sbX + 150, scoreY, 80, "left", {0.8, 0.8, 0.8, 1})
        
        if p.folded then
            GameLogic.drawText("FOLD", sbX + 230, scoreY, 95, "right", {0.8, 0.3, 0.3, 1})
        elseif p.currentBet > 0 then
            GameLogic.drawText("Bet: $" .. p.currentBet, sbX + 230, scoreY, 95, "right", {0.4, 0.9, 0.4, 1})
        else
            GameLogic.drawText("-", sbX + 230, scoreY, 95, "right", {0.4, 0.4, 0.4, 1})
        end
        scoreY = scoreY + 35
    end
    
    -- Pot Section
    love.graphics.setColor(1, 0.85, 0.2, 1)
    love.graphics.rectangle("line", sbX + 15, scoreY + 10, sbWidth - 30, 40, 5)
    GameLogic.drawText("CURRENT POT: $" .. Poker.pot, sbX + 15, scoreY + 20, sbWidth - 30, "center", {1, 0.85, 0.2, 1})
end

function Poker.drawCallingUI(cx, cy, W, H)
    -- Draw Action Buttons safely above local hand
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.myPlayerIdx].isBot then
        local btnWidth = 100
        local btnHeight = 40
        local gap = 20
        -- Total width = (100*3) + (20*2) = 340. Half is 170.
        local startX = cx - 170 
        local startY = H - 180 -- Safely above bottom player's hand
        
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local toCall = Poker.currentBetToMatch - p.currentBet
        local callStr = (toCall == 0) and "CHECK" or ("CALL $" .. toCall)
        
        -- FOLD
        love.graphics.setColor(0.8, 0.2, 0.2, 1)
        love.graphics.rectangle("fill", startX, startY, btnWidth, btnHeight, 8)
        GameLogic.drawText("FOLD", startX, startY + 10, btnWidth, "center")
        
        -- CALL/CHECK
        love.graphics.setColor(0.2, 0.8, 0.2, 1)
        love.graphics.rectangle("fill", startX + btnWidth + gap, startY, btnWidth, btnHeight, 8)
        GameLogic.drawText(callStr, startX + btnWidth + gap, startY + 10, btnWidth, "center")
        
        -- RAISE
        love.graphics.setColor(0.2, 0.4, 0.8, 1)
        love.graphics.rectangle("fill", startX + (btnWidth + gap) * 2, startY, btnWidth, btnHeight, 8)
        GameLogic.drawText("RAISE $20", startX + (btnWidth + gap) * 2, startY + 10, btnWidth, "center")
    end
    
    -- Draw Community Cards
    if Poker.communityCards and #Poker.communityCards > 0 then
        for i, c in ipairs(Poker.communityCards) do
            GameLogic.drawCard(c, c.visX, c.visY, true)
        end
    end
    
    -- Draw Player Chips dynamically
    for i=1, 4 do
        local px, py = GameLogic.getPlayerAnchor(i)
        local p = GameLogic.players[i]
        
        -- Calculate vector toward center to push bets neatly into the middle
        local dirX = cx - px
        local dirY = cy - py
        local dist = math.sqrt(dirX*dirX + dirY*dirY)
        
        -- 1. Draw Total Bankroll (Available Money Stacks)
        if (p.visChips or 0) >= 1 then
            local bankX, bankY
            if i == GameLogic.myPlayerIdx then
                -- Place local player bankroll completely to the left
                bankX = 120
                bankY = H - 60
            else
                local isRightSide = px > cx
                bankX = isRightSide and (px - 100) or (px + 100)
                bankY = py + 15
            end
            
            drawChipStack(p.visChips, bankX, bankY, not (px > cx))
            
            -- Optional label under the bankroll stack
            GameLogic.drawText("$"..math.floor(p.visChips), bankX - 30, bankY + 10, 60, "center", {0.8, 0.8, 0.8, 1})
        end

        -- 2. Draw Active Bets
        local betX, betY = px, py
        if dist > 0 then
            betX = px + (dirX/dist) * 90 -- Push inward safely
            betY = py + (dirY/dist) * 90
        end
        if i == GameLogic.myPlayerIdx then
            -- Push local bet far enough up to avoid hand collision
            betY = betY - 80
        end
        
        if (p.visBet or 0) >= 1 then
            drawChipStack(p.visBet, betX, betY, true)
            GameLogic.drawText("$"..math.floor(p.visBet), betX - 30, betY + 15, 60, "center", {1, 1, 1, 1})
        end
        
        -- Dealer Button (pushed inward slightly less and offset)
        if Poker.dealerIdx == i then
            local dbX = px + (dirX/dist) * 60 - 25
            local dbY = py + (dirY/dist) * 60
            
            love.graphics.setColor(0.9, 0.9, 0.9, 1)
            love.graphics.circle("fill", dbX, dbY, 14)
            love.graphics.setColor(0.1, 0.1, 0.1, 1)
            love.graphics.circle("line", dbX, dbY, 14, 3)
            GameLogic.drawText("D", dbX - 10, dbY - 7, 20, "center", {0.1, 0.1, 0.1, 1})
        end
    end
    
    -- Draw Pot centrally, safely above the community cards
    if (Poker.visPot or 0) >= 1 then
        drawChipStack(Poker.visPot, cx - 15, cy - 100, true)
        GameLogic.drawText("POT: $"..math.floor(Poker.visPot), cx - 100, cy - 140, 200, "center", {1, 0.85, 0.2, 1})
    end
end

function Poker.mousepressed(x, y, button)
    local W, H = _G.getW(), _G.getH()
    local cx, cy = W / 2, H / 2
    
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx then
        local btnWidth = 100
        local btnHeight = 40
        local gap = 20
        local startX = cx - 170
        local startY = H - 180 -- Updated to match the new drawing Y
        
        if x >= startX and x <= startX + btnWidth and y >= startY and y <= startY + btnHeight then
            -- FOLD
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="FOLD"})
            else Poker.handleAction(GameLogic.myPlayerIdx, "FOLD") end
        elseif x >= startX + btnWidth + gap and x <= startX + btnWidth*2 + gap and y >= startY and y <= startY + btnHeight then
            -- CALL
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="CALL"})
            else Poker.handleAction(GameLogic.myPlayerIdx, "CALL") end
        elseif x >= startX + (btnWidth + gap)*2 and x <= startX + (btnWidth + gap)*2 + btnWidth and y >= startY and y <= startY + btnHeight then
            -- RAISE
            if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="POKER_ACTION", type="RAISE", amount=20})
            else Poker.handleAction(GameLogic.myPlayerIdx, "RAISE", 20) end
        end
    end
end

function Poker.canPlayCard(card, hand) return false end 

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