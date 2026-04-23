local Poker = {}
local GameLogic = nil

local handRanks = {"High Card", "Pair", "Two Pair", "3 of a Kind", "Straight", "Flush", "Full House", "4 of a Kind", "Straight Flush"}
local rankValues = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}

Poker.botProfiles = {}
Poker.playerTendencies = {}

Poker.raiseAmount = 20  -- Default raise amount
Poker.minRaise = 20     -- Minimum raise (typically big blind)
Poker.raiseStep = 10    -- Increment/decrement step

-- Pre-allocated colors for zero-allocation drawing (Memory Optimization)
local UI_THEMES = {
    bg = {0, 0, 0, 0.65},
    border = {1, 1, 1, 0.1},
    text_active = {1, 1, 1, 1},
    text_inactive = {0.6, 0.6, 0.6, 1},
    text_muted = {0.7, 0.7, 0.7, 1},
    disabled = {0.3, 0.3, 0.3, 1},
    fold  = { normal = {0.75, 0.2, 0.2, 1}, hover = {0.9, 0.3, 0.3, 1}, border = {0.4, 0.1, 0.1, 1} },
    call  = { normal = {0.2, 0.65, 0.3, 1}, hover = {0.3, 0.8, 0.4, 1}, border = {0.1, 0.4, 0.15, 1} },
    raise = { normal = {0.2, 0.5, 0.8, 1},  hover = {0.3, 0.65, 0.95, 1}, border = {0.1, 0.3, 0.5, 1} },
    allin = { normal = {0.85, 0.5, 0.1, 1}, hover = {1.0, 0.65, 0.2, 1}, border = {0.5, 0.3, 0.05, 1} },
    preset_normal = {0.2, 0.2, 0.2, 0.8},
    preset_hover = {0.4, 0.4, 0.4, 1},
    preset_selected = {0.2, 0.6, 0.3, 1},
    preset_border = {0.5, 0.5, 0.5, 1},
    preset_border_selected = {0.4, 0.9, 0.4, 1},
    showdown_bg = {0, 0, 0, 0.75},
    showdown_panel = {0.1, 0.1, 0.12, 0.95},
    showdown_border = {1, 0.85, 0.2, 0.5},
    showdown_gold = {1, 0.85, 0.2, 1},
    showdown_green = {0.4, 1.0, 0.5, 1},
    pot_bg = {0.05, 0.05, 0.08, 0.8},
    pot_border = {1, 0.85, 0.2, 0.4},
    bet_label_bg = {0, 0, 0, 0.6},
    bet_label_text = {0.5, 0.9, 0.5, 1},
    dealer_bg = {0.9, 0.9, 0.9, 1},
    dealer_border = {0.1, 0.1, 0.1, 1},
    dealer_text = {0.1, 0.1, 0.1, 1}
}

-- Highly optimized flat button drawer (no table allocations)
local function drawFlatButton(txt, bx, by, bw, bh, theme, active, mx, my)
    local isHover = active and mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
    local fill = isHover and theme.hover or theme.normal
    if not active then fill = UI_THEMES.disabled end
    
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", bx, by, bw, bh, 4)
    
    local txtColor = active and UI_THEMES.text_active or UI_THEMES.text_inactive
    GameLogic.drawText(txt, bx, by + math.floor(bh/2) - 7, bw, "center", txtColor)
end

function Poker.init(gl)
    GameLogic = gl
end

function Poker.initBots()
    local personalities = {"aggressive", "conservative", "normal", "normal"}
    for i = 1, 4 do
        if GameLogic and GameLogic.players and GameLogic.players[i] and GameLogic.players[i].isBot then
            Poker.botProfiles[i] = personalities[i] or "normal"
        end
    end
end

function Poker.updateTendencies(playerIdx, action, amount)
    if not Poker.playerTendencies[playerIdx] then
        Poker.playerTendencies[playerIdx] = {aggression = 0, bluffCount = 0, handsPlayed = 0}
    end
    
    local t = Poker.playerTendencies[playerIdx]
    t.handsPlayed = t.handsPlayed + 1
    
    if action == "RAISE" then
        t.aggression = t.aggression + 1
    elseif action == "ALL_IN" then
        t.aggression = t.aggression + 2
    end
end

function Poker.startRound()
    Poker.initBots()
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
            GameLogic.players[i].chips = 5000
        end
        -- Initialize animation variables
        GameLogic.players[i].visChips = GameLogic.players[i].chips
        GameLogic.players[i].visBet = 0
    end
    
    Poker.visPot = 0
    
    local deck = GameLogic.generateDeck()
    GameLogic.shuffle(deck)
    Poker.deck = deck
    
    GameLogic.flyingCards = {}
    Poker.pendingDeals = {{}, {}, {}, {}}
    
    -- Deal 2 cards each using physical flying cards from center
    for i=1, 8 do
        local pIdx = ((i - 1) % 4) + 1
        local c = table.remove(deck)
        c.visX = _G.getW() / 2
        c.visY = _G.getH() / 2
        table.insert(GameLogic.flyingCards, { card = c, targetId = pIdx })
        table.insert(Poker.pendingDeals[pIdx], c)
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
    
    GameLogic.phase = "DEAL_ANIMATION"
    GameLogic.currentPlayer = (bbIdx % 4) + 1
    GameLogic.turnTimer = 1.2
    Poker.playersActedThisRound = 0
    Poker.showdownResults = nil
    
    GameLogic.syncState()
end

function Poker.handleAction(playerIdx, action, amount)
    Poker.updateTendencies(playerIdx, action, amount)
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
    elseif action == "ALL_IN" then
        local toAdd = p.chips
        p.chips = 0
        p.currentBet = p.currentBet + toAdd
        Poker.pot = Poker.pot + toAdd
        if p.currentBet > Poker.currentBetToMatch then
            Poker.currentBetToMatch = p.currentBet
        end
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
            GameLogic.phase = "FLOP_ANIMATION"
            GameLogic.turnTimer = 0.8
            for i=1, 3 do 
                local c = table.remove(Poker.deck)
                c.visX = _G.getW() / 2
                c.visY = -200 - (i*50) -- staggered spawn
                table.insert(Poker.communityCards, c)
            end
        elseif GameLogic.phase == "BETTING_FLOP" then
            GameLogic.phase = "TURN_ANIMATION"
            GameLogic.turnTimer = 0.5
            local c = table.remove(Poker.deck)
            c.visX = _G.getW() / 2
            c.visY = -200
            table.insert(Poker.communityCards, c)
        elseif GameLogic.phase == "BETTING_TURN" then
            GameLogic.phase = "RIVER_ANIMATION"
            GameLogic.turnTimer = 0.5
            local c = table.remove(Poker.deck)
            c.visX = _G.getW() / 2
            c.visY = -200
            table.insert(Poker.communityCards, c)
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
    
    if GameLogic.currentPlayer == GameLogic.myPlayerIdx then
        Poker.resetRaiseAmount()
    end
    
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
    
    local typeRank = 1
    if isStraight and isFlush then typeRank = 9
    elseif groups[1].count == 4 then typeRank = 8
    elseif groups[1].count == 3 and groups[2].count == 2 then typeRank = 7
    elseif isFlush then typeRank = 6
    elseif isStraight then typeRank = 5
    elseif groups[1].count == 3 then typeRank = 4
    elseif groups[1].count == 2 and groups[2].count == 2 then typeRank = 3
    elseif groups[1].count == 2 then typeRank = 2
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
    local playerHandsMap = {}
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
            playerHandsMap[i] = {name=handRanks[bestScore[1]]}
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
    
    local wStr = #winners > 1 and "SPLIT POT (" or "WINNER ("
    wStr = wStr .. (handRanks[highest[1]] or "High Card") .. "): "
    for idx, wIdx in ipairs(winners) do
        wStr = wStr .. GameLogic.players[wIdx].name
        if idx < #winners then wStr = wStr .. ", " end
    end
    
    Poker.showdownResults = {
        winners = winners,
        playerHands = playerHandsMap,
        winnerString = wStr
    }
    
    GameLogic.turnTimer = 8.0
    GameLogic.syncState()
end

function Poker.getOpponentAggression(opponentIdx)
    local t = Poker.playerTendencies[opponentIdx]
    if not t or t.handsPlayed < 5 then return 0.5 end
    return math.min(1.0, t.aggression / t.handsPlayed)
end

function Poker.getPositionAdvantage(playerIdx)
    local positions = {}
    local currentPos = 1
    for i = 1, 4 do
        if not GameLogic.players[i].folded then
            positions[currentPos] = i
            currentPos = currentPos + 1
        end
    end
    
    for pos, idx in ipairs(positions) do
        if idx == playerIdx then
            return pos / #positions
        end
    end
    return 0.5
end

function Poker.evaluatePreFlop(hand)
    if not hand or #hand < 2 then return 0.20 end
    local rank1 = rankValues[hand[1].rank] or 2
    local rank2 = rankValues[hand[2].rank] or 2
    local suited = hand[1].suit == hand[2].suit
    
    if (rank1 == 14 and rank2 == 14) or (rank1 == 13 and rank2 == 13) then
        return 0.95
    elseif (rank1 == 12 and rank2 == 12) or (rank1 == 11 and rank2 == 11) then
        return 0.85
    elseif (rank1 == 14 and rank2 == 13) or (rank1 == 13 and rank2 == 14) then
        return suited and 0.80 or 0.70
    elseif rank1 == rank2 then
        return 0.60
    elseif math.abs(rank1 - rank2) <= 2 and suited then
        return 0.50
    elseif suited then
        return 0.35
    else
        return 0.20
    end
end

function Poker.getHandStrength(playerIdx)
    local p = GameLogic.players[playerIdx]
    local allCards = {}
    for _, c in ipairs(p.hand) do table.insert(allCards, c) end
    for _, c in ipairs(Poker.communityCards) do table.insert(allCards, c) end
    
    if #allCards < 5 then
        return Poker.evaluatePreFlop(p.hand)
    else
        local combos = getCombinations(allCards, 5)
        local bestScore = {-1}
        for _, combo in ipairs(combos) do
            local sc = getHandScore(combo)
            if compareScores(sc, bestScore) > 0 then
                bestScore = sc
            end
        end
        return bestScore[1] / 9  -- Normalize 0-1
    end
end

function Poker.calculateRaiseAmount(handStrength, potOdds, myStack, profile)
    local baseRaise = 20
    local multiplier = 1.0
    
    if handStrength > 0.90 then
        multiplier = 3.0
    elseif handStrength > 0.70 then
        multiplier = 2.0
    elseif handStrength > 0.50 then
        multiplier = 1.5
    elseif handStrength > 0.30 and math.random() < 0.3 then
        multiplier = 1.0
    end
    
    if profile == "aggressive" then
        multiplier = multiplier * 1.5
    elseif profile == "conservative" then
        multiplier = multiplier * 0.7
    end
    
    local raiseAmount = math.min(baseRaise * multiplier, myStack * 0.3)
    return math.max(20, math.floor(raiseAmount / 10) * 10)
end

function Poker.resetRaiseAmount()
    local p = GameLogic.players[GameLogic.myPlayerIdx]
    if p then
        local minRequiredRaise = math.max(Poker.minRaise, (Poker.currentBetToMatch - p.currentBet) + Poker.minRaise)
        Poker.raiseAmount = math.max(minRequiredRaise, math.min(20, p.chips))
    else
        Poker.raiseAmount = 20
    end
end

function Poker.decideAction(handStrength, potOdds, toCall, myStack, betToMatch, profile)
    local positionAdvantage = Poker.getPositionAdvantage(GameLogic.currentPlayer)
    local aggression = profile == "aggressive" and 1.2 or (profile == "conservative" and 0.8 or 1.0)
    aggression = aggression * (0.8 + positionAdvantage * 0.6)
    
    if handStrength > 0.80 then
        if betToMatch > myStack * 0.3 then
            return "ALL_IN"
        elseif toCall == 0 then
            return "RAISE"
        else
            return "RAISE"
        end
    elseif handStrength > 0.50 then
        if toCall == 0 then
            return (math.random() < 0.6 * aggression) and "RAISE" or "CALL"
        elseif potOdds > 2.0 then
            return "CALL"
        elseif betToMatch > myStack * 0.4 then
            return "FOLD"
        else
            return "CALL"
        end
    elseif handStrength > 0.30 then
        if toCall == 0 then
            return (math.random() < 0.3 * aggression) and "RAISE" or "CALL"
        elseif potOdds > 3.0 and toCall < myStack * 0.2 then
            return (math.random() < 0.2 * aggression) and "RAISE" or "CALL"
        elseif toCall > 0 and math.random() < 0.15 * aggression then
            -- Bluff 15% of the time, especially aggressive ones
            return "CALL"
        else
            return "FOLD"
        end
    else
        -- Trash hands. We need them to not ALWAYS fold early on to keep the pot alive! Check heavily, and sometimes bluff call.
        if toCall == 0 then
            return (math.random() < 0.15 * aggression) and "RAISE" or "CALL"
        elseif toCall <= GameLogic.players[GameLogic.currentPlayer].chips * 0.05 then
            -- If it's a very cheap small bet compared to their stack, occasionally call.
            return (math.random() < 0.40 * aggression) and "CALL" or "FOLD"
        else
            -- Huge bets? Occasionally completely shock everyone with an insane bluff!
            if math.random() < 0.05 * aggression then
                return (math.random() < 0.2) and "ALL_IN" or "CALL"
            end
            return "FOLD"
        end
    end
end

function Poker.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if p.folded then
        Poker.advanceTurn()
        return
    end
    
    local profile = Poker.botProfiles[GameLogic.currentPlayer] or "normal"
    local handStrength = Poker.getHandStrength(GameLogic.currentPlayer)
    local toCall = Poker.currentBetToMatch - p.currentBet
    local potOdds = toCall > 0 and (Poker.pot / toCall) or 999
    local myStack = p.chips
    local betToMatch = Poker.currentBetToMatch
    
    local action = Poker.decideAction(handStrength, potOdds, toCall, myStack, betToMatch, profile)
    
    if action == "FOLD" then
        Poker.handleAction(GameLogic.currentPlayer, "FOLD")
    elseif action == "CALL" then
        Poker.handleAction(GameLogic.currentPlayer, "CALL")
    elseif action == "RAISE" then
        local raiseAmount = Poker.calculateRaiseAmount(handStrength, potOdds, myStack, profile)
        Poker.handleAction(GameLogic.currentPlayer, "RAISE", raiseAmount)
    elseif action == "ALL_IN" then
        Poker.handleAction(GameLogic.currentPlayer, "ALL_IN")
    end
end

function Poker.isBotTurn()
    if string.match(GameLogic.phase, "BETTING") then
        return GameLogic.players[GameLogic.currentPlayer].isBot
    end
    return false
end

function Poker.update(dt)
    if GameLogic.phase == "DEAL_ANIMATION" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                for i=1, 4 do
                    if Poker.pendingDeals[i] then
                        for _, c in ipairs(Poker.pendingDeals[i]) do
                            table.insert(GameLogic.players[i].hand, c)
                        end
                    end
                end
                
                GameLogic.phase = "BETTING_PREFLOP"
                GameLogic.turnTimer = GameLogic.maxTurnTime or 15
                GameLogic.syncState()
            end
        end
    elseif GameLogic.phase == "FLOP_ANIMATION" or GameLogic.phase == "TURN_ANIMATION" or GameLogic.phase == "RIVER_ANIMATION" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                if GameLogic.phase == "FLOP_ANIMATION" then GameLogic.phase = "BETTING_FLOP"
                elseif GameLogic.phase == "TURN_ANIMATION" then GameLogic.phase = "BETTING_TURN"
                elseif GameLogic.phase == "RIVER_ANIMATION" then GameLogic.phase = "BETTING_RIVER" end
                GameLogic.turnTimer = GameLogic.maxTurnTime or 15
                GameLogic.currentPlayer = (Poker.dealerIdx % 4) + 1
				local safeLoops = 0
				while (GameLogic.players[GameLogic.currentPlayer].folded or GameLogic.players[GameLogic.currentPlayer].chips <= 0) and safeLoops < 4 do
					GameLogic.currentPlayer = (GameLogic.currentPlayer % 4) + 1
					safeLoops = safeLoops + 1
				end
                GameLogic.syncState()
            end
        end
    elseif GameLogic.phase == "SHOWDOWN" then
        if GameLogic.turnTimer then
            GameLogic.turnTimer = GameLogic.turnTimer - dt
            if GameLogic.turnTimer <= 0 then
                if Poker.showdownResults and #Poker.showdownResults.winners > 0 then
                    local winSplit = math.floor(Poker.pot / #Poker.showdownResults.winners)
                    for _, wIdx in ipairs(Poker.showdownResults.winners) do
                        GameLogic.players[wIdx].chips = GameLogic.players[wIdx].chips + winSplit
                    end
                end
                Poker.pot = 0
                GameLogic.phase = "ROUND_OVER"
                GameLogic.syncState()
            end
        end
    end
    
    -- Card sliding animations loop!
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
    {val=5000, col={0.90, 0.40, 0.20, 1}}, -- Burnt Orange/Brown (high roller)
    {val=1000, col={0.95, 0.75, 0.10, 1}}, -- Electric Yellow/Gold
    {val=500,  col={0.60, 0.20, 0.70, 1}}, -- Vibrant Purple
    {val=100,  col={0.10, 0.10, 0.12, 1}}, -- Rich Black
    {val=69,   col={0.95, 0.50, 0.75, 1}}, -- Hot Pink
    {val=50,   col={0.00, 0.45, 0.80, 1}}, -- Electric Blue
    {val=25,   col={0.05, 0.65, 0.15, 1}}, -- Emerald Green
    {val=10,   col={0.95, 0.50, 0.00, 1}}, -- Bright Orange
    {val=5,    col={0.85, 0.15, 0.20, 1}}, -- Ruby Red
    {val=1,    col={0.92, 0.92, 0.95, 1}}  -- Pearl White
}

-- 'maxCols' determines how many stacks wide the grid can be before wrapping to a new row
local function drawChipStack(amount, x, y)
    maxCols = 4 -- Default to 4 columns if not specified
    local cx, cy = x, y
    local stackTotal = amount
    
    local spacingX = 28 -- Horizontal distance between stacks
    local spacingY = 28 -- Vertical distance between rows of stacks
    local maxChipsPerStack = 6
    
    local currentStackIndex = 0

    if stackTotal < 1 then return end

    for _, cv in ipairs(chipColors) do
        -- Calculate how many chips of this specific color we need
        local num = math.floor(stackTotal / cv.val)
        stackTotal = stackTotal - (num * cv.val)
        
        if num > 0 then
            local chipsInCurrentStack = 0
            
            for i = 1, num do
                -- Calculate grid position based on the current stack index
                local col = currentStackIndex % maxCols
                local row = math.floor(currentStackIndex / maxCols)
                
                local hOffset = col * spacingX
                local vOffset = row * spacingY
                local zOffset = chipsInCurrentStack * 3
                
                local drawX = cx + hOffset
                local drawY = cy + vOffset - zOffset

                -- Drop Shadow
                love.graphics.setColor(0, 0, 0, 0.4)
                love.graphics.circle("fill", drawX + 2, drawY + 2, 12)

                -- Base Chip Color
                love.graphics.setColor(cv.col)
                love.graphics.circle("fill", drawX, drawY, 12)
                
                -- Casino Edge Stripes
                love.graphics.setColor(1, 1, 1, 0.6)
                love.graphics.setLineWidth(2)
                love.graphics.line(drawX - 12, drawY, drawX - 7, drawY)
                love.graphics.line(drawX + 7, drawY, drawX + 12, drawY)
                love.graphics.line(drawX, drawY - 12, drawX, drawY - 7)
                love.graphics.line(drawX, drawY + 7, drawX, drawY + 12)
                love.graphics.setLineWidth(1)
                
                -- Inner detailing
                love.graphics.setColor(cv.col)
                love.graphics.circle("fill", drawX, drawY, 8)
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.circle("line", drawX, drawY, 8)
                love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
                love.graphics.circle("line", drawX, drawY, 12)
                
                chipsInCurrentStack = chipsInCurrentStack + 1
                
                -- If the stack reaches the height limit, start a new stack (unless it's the last chip of this color)
                if chipsInCurrentStack >= maxChipsPerStack and i ~= num then 
                    currentStackIndex = currentStackIndex + 1
                    chipsInCurrentStack = 0
                end
            end
            
            -- Important: Once we finish drawing all chips of the current color, 
            -- force the next color to begin in a brand-new stack.
            currentStackIndex = currentStackIndex + 1
        end
    end
end

function Poker.drawScoreboard(cx, cy, W, H)
    if not GameLogic.sbFont then
        local currentSize = love.graphics.getFont():getHeight()
        GameLogic.sbFont = love.graphics.newFont(math.max(10, math.floor(currentSize * 0.85)))
    end
    local oldFont = love.graphics.getFont()
    love.graphics.setFont(GameLogic.sbFont)

    local isCollapsed = GameLogic.isScoreboardCollapsed

    local sbWidth = 260
    local sbHeight = isCollapsed and 30 or (60 + (4 * 24) + 24)
    local sbX = W - sbWidth - 15
    local sbY = 15

    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 8)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 8)

    local btnText = isCollapsed and "[+] SCOREBOARD" or "[-] SCOREBOARD"
    love.graphics.setColor(1, 0.85, 0.3, 1)
    love.graphics.printf(btnText, sbX, sbY + 8, sbWidth, "center")

    if not isCollapsed then
        local colName = 10
        local colChips = 130
        local colBet = 190

        local labelY = sbY + 28
        local labelColor = {0.6, 0.6, 0.6, 1}
        GameLogic.drawText("Player", sbX + colName, labelY, 110, "left", labelColor)
        GameLogic.drawText("Chips",  sbX + colChips, labelY, 50, "left", labelColor)
        GameLogic.drawText("Bet",    sbX + colBet, labelY, 60, "right", labelColor)

        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.line(sbX + 10, sbY + 45, sbX + sbWidth - 10, sbY + 45)

        local scoreY = sbY + 52
        for i = 1, 4 do
            local p = GameLogic.players[i]
            local isCurrent = (i == GameLogic.currentPlayer and not string.match(GameLogic.phase, "ROUND_OVER"))
            if isCurrent then
                love.graphics.setColor(1, 1, 1, 0.05)
                love.graphics.rectangle("fill", sbX + 5, scoreY - 2, sbWidth - 10, 20, 4)
            end
            
            local pColor = p.folded and {0.5, 0.5, 0.5, 1} or (isCurrent and {0.3, 0.95, 0.4, 1} or {1, 1, 1, 1})
            
            GameLogic.drawTruncatedText(p.name, sbX + colName, scoreY, colChips - colName - 5, "left", pColor)
            GameLogic.drawText("$" .. tostring(p.chips), sbX + colChips, scoreY, 60, "left", {0.8, 0.8, 0.8, 1})
            
            if p.folded then
                GameLogic.drawText("FOLD", sbX + colBet, scoreY, 60, "right", {0.8, 0.3, 0.3, 1})
            elseif p.currentBet > 0 then
                GameLogic.drawText("$" .. p.currentBet, sbX + colBet, scoreY, 60, "right", {0.4, 0.9, 0.4, 1})
            else
                GameLogic.drawText("-", sbX + colBet, scoreY, 60, "right", {0.4, 0.4, 0.4, 1})
            end
            scoreY = scoreY + 24
        end
        
        love.graphics.setColor(1, 1, 1, 0.1)
        love.graphics.line(sbX + 10, scoreY, sbX + sbWidth - 10, scoreY)
        scoreY = scoreY + 5
        GameLogic.drawText("POT", sbX + colName, scoreY, 100, "left", {1, 0.85, 0.2, 1})
        GameLogic.drawText("$" .. Poker.pot, sbX + colBet, scoreY, 60, "right", {1, 0.85, 0.2, 1})
    end

    love.graphics.setFont(oldFont)
end

function Poker.drawCallingUI(cx, cy, W, H)
    local mx, my = love.mouse.getPosition()

    -- 1. DRAW COMMUNITY CARDS (Bottom layer)
    if Poker.communityCards and #Poker.communityCards > 0 then
        for i, c in ipairs(Poker.communityCards) do
            GameLogic.drawCard(c, c.visX, c.visY, true)
        end
    end
    
    -- 2. DRAW PLAYER CHIPS AND DEALER BUTTON
    for i=1, 4 do
        local px, py = GameLogic.getPlayerAnchor(i)
        local p = GameLogic.players[i]
        
        local dirX = cx - px
        local dirY = cy - py
        local dist = math.sqrt(dirX*dirX + dirY*dirY)
        
        -- Bankroll Stacks
        if (p.visChips or 0) >= 1 then
            local bankX, bankY
            local rel = (i - GameLogic.myPlayerIdx) % 4
            
            if rel == 0 then bankX = cx + 130; bankY = H - 110
            elseif rel == 1 then bankX = 140; bankY = cy - 100
            elseif rel == 2 then bankX = cx - 290; bankY = 140
            elseif rel == 3 then bankX = W - 180; bankY = cy + 100 end
            
            drawChipStack(p.visChips, bankX, bankY)
        end

        -- Active Bets
        local betX, betY = px, py
        if dist > 0 then
            betX = px + (dirX/dist) * 90
            betY = py + (dirY/dist) * 90
        end
        if i == GameLogic.myPlayerIdx then betY = betY - 80 end
        
        if (p.visBet or 0) >= 1 then
            drawChipStack(p.visBet, betX, betY)
            love.graphics.setColor(UI_THEMES.bet_label_bg)
            love.graphics.rectangle("fill", betX - 25, betY + 12, 50, 18, 4)
            GameLogic.drawText("$"..math.floor(p.visBet), betX - 25, betY + 14, 50, "center", UI_THEMES.bet_label_text)
        end
        
        -- Dealer Button
        if Poker.dealerIdx == i then
            local dbX = px + (dirX/dist) * 60 - 25
            local dbY = py + (dirY/dist) * 60
            
            love.graphics.setColor(UI_THEMES.dealer_bg)
            love.graphics.circle("fill", dbX, dbY, 14)
            love.graphics.setColor(UI_THEMES.dealer_border)
            love.graphics.circle("line", dbX, dbY, 14, 3)
            GameLogic.drawText("D", dbX, dbY, 20, "center", UI_THEMES.dealer_text)
        end
    end

    -- 4. ACTION BUTTONS (Flat, Clean UI)
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.myPlayerIdx].isBot then
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local toCall = Poker.currentBetToMatch - p.currentBet
        
        local maxPossibleRaise = p.chips
        local minRequiredRaise = math.max(Poker.minRaise, (Poker.currentBetToMatch - p.currentBet) + Poker.minRaise)
        Poker.raiseAmount = math.max(minRequiredRaise, math.min(Poker.raiseAmount, maxPossibleRaise))
        
        local btnWidth, btnHeight, smallBtnWidth, gap = 90, 40, 35, 10
        local totalWidth = btnWidth * 3 + smallBtnWidth * 2 + btnWidth + gap * 6
        local startX = cx - totalWidth / 2
        local startY = H - 140
        
        love.graphics.setColor(UI_THEMES.bg)
        love.graphics.rectangle("fill", startX - 15, startY - 45, totalWidth + 30, btnHeight + 60, 12)
        love.graphics.setColor(UI_THEMES.border)
        love.graphics.rectangle("line", startX - 15, startY - 45, totalWidth + 30, btnHeight + 60, 12)

        local currentX = startX
        
        -- Main Actions
        drawFlatButton("FOLD", currentX, startY, btnWidth, btnHeight, UI_THEMES.fold, true, mx, my)
        currentX = currentX + btnWidth + gap
        
        drawFlatButton((toCall == 0) and "CHECK" or ("CALL $" .. toCall), currentX, startY, btnWidth, btnHeight, UI_THEMES.call, p.chips > 0, mx, my)
        currentX = currentX + btnWidth + gap
        
        local canRaise = p.chips > toCall
        drawFlatButton("-", currentX, startY, smallBtnWidth, btnHeight, UI_THEMES.raise, canRaise and Poker.raiseAmount > minRequiredRaise, mx, my)
        currentX = currentX + smallBtnWidth + 5
        
        drawFlatButton("RAISE $" .. Poker.raiseAmount, currentX, startY, btnWidth, btnHeight, UI_THEMES.raise, canRaise, mx, my)
        currentX = currentX + btnWidth + 5
        
        drawFlatButton("+", currentX, startY, smallBtnWidth, btnHeight, UI_THEMES.raise, canRaise and Poker.raiseAmount < maxPossibleRaise, mx, my)
        currentX = currentX + smallBtnWidth + gap
        
        drawFlatButton("ALL IN", currentX, startY, btnWidth, btnHeight, UI_THEMES.allin, true, mx, my)
        
        -- PRESETS
        local presetY = startY - 34
        local presetWidth, presetHeight = 55, 22
        local presets = {20, 50, 100, 200}
        local presetGap = (btnWidth + smallBtnWidth * 2 + 10 - (#presets * presetWidth)) / (#presets + 1)
        local presetX = startX + btnWidth*2 + gap*2 + 5 + presetGap
        
        for _, val in ipairs(presets) do
            if val <= maxPossibleRaise and val >= minRequiredRaise then
                local isSelected = (Poker.raiseAmount == val)
                local isHover = mx >= presetX and mx <= presetX + presetWidth and my >= presetY and my <= presetY + presetHeight
                
                love.graphics.setColor(isSelected and UI_THEMES.preset_selected or (isHover and UI_THEMES.preset_hover or UI_THEMES.preset_normal))
                love.graphics.rectangle("fill", presetX, presetY, presetWidth, presetHeight, 4)
                love.graphics.setColor(isSelected and UI_THEMES.preset_border_selected or UI_THEMES.preset_border)
                love.graphics.rectangle("line", presetX, presetY, presetWidth, presetHeight, 4)
                
                GameLogic.drawText("$" .. val, presetX, presetY + 3, presetWidth, "center", UI_THEMES.text_active)
                presetX = presetX + presetWidth + presetGap
            end
        end
    end
    
    -- 5. SHOWDOWN OVERLAY (Proper Modal Display)
    if GameLogic.phase == "SHOWDOWN" and Poker.showdownResults then
        love.graphics.setColor(UI_THEMES.showdown_bg)
        love.graphics.rectangle("fill", 0, 0, W, H)
        
        local panelW, panelH = 400, 260
        local panelX, panelY = cx - panelW/2, cy - panelH/2 - 40
        
        -- Main Panel
        love.graphics.setColor(UI_THEMES.showdown_panel)
        love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8)
        love.graphics.setColor(UI_THEMES.showdown_border)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8)
        love.graphics.setLineWidth(1)
        
        -- Header
        GameLogic.drawText("SHOWDOWN RESULTS", panelX, panelY + 15, panelW, "center", UI_THEMES.showdown_gold)
        love.graphics.setColor(UI_THEMES.showdown_border)
        love.graphics.line(panelX + 20, panelY + 45, panelX + panelW - 20, panelY + 45)
        
        -- Player Rows
        local currentY = panelY + 60
        for i=1, 4 do
            local p = GameLogic.players[i]
            local res = Poker.showdownResults.playerHands[i]
            local isWinner = false
            for _, wIdx in ipairs(Poker.showdownResults.winners) do
                if wIdx == i then isWinner = true; break end
            end
            
            local nameCol = isWinner and UI_THEMES.showdown_gold or UI_THEMES.text_active
            local handCol = isWinner and UI_THEMES.showdown_green or UI_THEMES.text_inactive
            
            if isWinner then
                love.graphics.setColor(UI_THEMES.showdown_gold)
                love.graphics.circle("fill", panelX + 20, currentY + 8, 4)
            end
            
            GameLogic.drawText(p.name, panelX + 35, currentY, 150, "left", nameCol)
            
            if p.folded then
                GameLogic.drawText("FOLDED", panelX + 180, currentY, 190, "right", UI_THEMES.disabled)
            elseif res then
                GameLogic.drawText(res.name, panelX + 180, currentY, 190, "right", handCol)
            end
            
            currentY = currentY + 35
        end
        
        -- Footer
        love.graphics.setColor(UI_THEMES.showdown_border)
        love.graphics.line(panelX + 20, currentY, panelX + panelW - 20, currentY)
        
        if #Poker.showdownResults.winners > 0 then
            local winAmt = math.floor(Poker.pot / #Poker.showdownResults.winners)
            local footerText = #Poker.showdownResults.winners > 1 and "SPLIT POT! $" .. winAmt .. " EACH" or "WINNER TAKES $" .. winAmt .. "!"
            GameLogic.drawText(footerText, panelX, currentY + 15, panelW, "center", UI_THEMES.showdown_green)
        end
    end
end

function Poker.keypressed(key, scancode, isrepeat)
    -- Debug keys for phase control (only works in single player or host mode)
    if GameLogic.mode ~= "GUEST" then
        if key == "f1" then
            GameLogic.phase = "DEALING"
            Poker.startRound()
        elseif key == "f2" then
            GameLogic.phase = "BETTING_PREFLOP"
        elseif key == "f3" then
            GameLogic.phase = "FLOP_ANIMATION"
        elseif key == "f4" then
            GameLogic.phase = "BETTING_FLOP"
        elseif key == "f5" then
            GameLogic.phase = "TURN_ANIMATION"
        elseif key == "f6" then
            GameLogic.phase = "BETTING_TURN"
        elseif key == "f7" then
            GameLogic.phase = "RIVER_ANIMATION"
        elseif key == "f8" then
            GameLogic.phase = "BETTING_RIVER"
        elseif key == "f9" then
            GameLogic.phase = "SHOWDOWN"
            Poker.evaluateShowdown()
        elseif key == "f10" then
            GameLogic.phase = "ROUND_OVER"
        elseif key == "f11" then
            -- Force deal community cards for testing
            if not Poker.communityCards then Poker.communityCards = {} end
            if #Poker.communityCards < 5 and Poker.deck and #Poker.deck > 0 then
                local c = table.remove(Poker.deck)
                c.visX = _G.getW() / 2
                c.visY = _G.getH() / 2
                table.insert(Poker.communityCards, c)
            end
        elseif key == "f12" then
            -- Print current state to console
            print("=== DEBUG INFO ===")
            print("Phase:", GameLogic.phase)
            print("Pot:", Poker.pot)
            print("Current Bet:", Poker.currentBetToMatch)
            print("Community Cards:", #Poker.communityCards)
            print("Deck Size:", Poker.deck and #Poker.deck or 0)
            for i=1, 4 do
                local p = GameLogic.players[i]
                print(string.format("P%d: %s | Chips: %d | Bet: %d | Folded: %s", 
                    i, p.name, p.chips or 0, p.currentBet or 0, tostring(p.folded or false)))
            end
        end
        GameLogic.syncState()
    end
end

function Poker.mousepressed(x, y, button)
    local W, H = _G.getW(), _G.getH()
    local cx, cy = W / 2, H / 2
    
    -- Scoreboard toggle
    local sbWidth = 260
    local sbX = W - sbWidth - 15
    local sbY = 15
    if x >= sbX and x <= sbX + sbWidth and y >= sbY and y <= sbY + 30 then
        GameLogic.isScoreboardCollapsed = not GameLogic.isScoreboardCollapsed
        return
    end
    
    if string.match(GameLogic.phase, "BETTING") and GameLogic.currentPlayer == GameLogic.myPlayerIdx then
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local toCall = Poker.currentBetToMatch - p.currentBet
        
        local btnWidth = 90
        local btnHeight = 40
        local smallBtnWidth = 35
        local gap = 10
        local totalWidth = btnWidth * 3 + smallBtnWidth * 2 + btnWidth + gap * 6
        local startX = cx - totalWidth / 2
        local startY = H - 140
        
        -- FOLD button
        if x >= startX and x <= startX + btnWidth and y >= startY and y <= startY + btnHeight then
            if GameLogic.mode == "GUEST" then 
                require("network").sendGameMessage("host", {action="POKER_ACTION", type="FOLD"})
            else 
                Poker.handleAction(GameLogic.myPlayerIdx, "FOLD") 
            end
            return
        end
        
        local currentX = startX + btnWidth + gap
        
        -- CALL/CHECK button
        if x >= currentX and x <= currentX + btnWidth and y >= startY and y <= startY + btnHeight then
            if GameLogic.mode == "GUEST" then 
                require("network").sendGameMessage("host", {action="POKER_ACTION", type="CALL"})
            else 
                Poker.handleAction(GameLogic.myPlayerIdx, "CALL") 
            end
            return
        end
        
        currentX = currentX + btnWidth + gap
        
        -- MINUS button
        if x >= currentX and x <= currentX + smallBtnWidth and y >= startY and y <= startY + btnHeight then
            local minRequiredRaise = math.max(Poker.minRaise, (Poker.currentBetToMatch - p.currentBet) + Poker.minRaise)
            Poker.raiseAmount = math.max(minRequiredRaise, Poker.raiseAmount - Poker.raiseStep)
            return
        end
        
        currentX = currentX + smallBtnWidth + 5
        
        -- RAISE button (the amount display)
        if x >= currentX and x <= currentX + btnWidth and y >= startY and y <= startY + btnHeight then
            if GameLogic.mode == "GUEST" then 
                require("network").sendGameMessage("host", {action="POKER_ACTION", type="RAISE", amount=Poker.raiseAmount})
            else 
                Poker.handleAction(GameLogic.myPlayerIdx, "RAISE", Poker.raiseAmount) 
            end
            return
        end
        
        currentX = currentX + btnWidth + 5
        
        -- PLUS button
        if x >= currentX and x <= currentX + smallBtnWidth and y >= startY and y <= startY + btnHeight then
            Poker.raiseAmount = math.min(p.chips, Poker.raiseAmount + Poker.raiseStep)
            return
        end
        
        currentX = currentX + smallBtnWidth + gap
        
        -- ALL IN button
        if x >= currentX and x <= currentX + btnWidth and y >= startY and y <= startY + btnHeight then
            if GameLogic.mode == "GUEST" then 
                require("network").sendGameMessage("host", {action="POKER_ACTION", type="ALL_IN"})
            else 
                Poker.handleAction(GameLogic.myPlayerIdx, "ALL_IN") 
            end
            return
        end
        
        -- Preset buttons
        local presetY = startY - 34
        local presetWidth = 55
        local presetHeight = 25
        local presetStartX = startX + btnWidth + gap + btnWidth + gap
        local presets = {20, 50, 100, 200}
        local presetGap = (btnWidth + smallBtnWidth * 2 + 10 - (#presets * presetWidth)) / (#presets + 1)
        local presetX = presetStartX + presetGap
        
        for _, val in ipairs(presets) do
            if val <= p.chips then
                if x >= presetX and x <= presetX + presetWidth and y >= presetY and y <= presetY + presetHeight then
                    Poker.raiseAmount = val
                    return
                end
                presetX = presetX + presetWidth + presetGap
            end
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