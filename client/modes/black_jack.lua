local BlackJack = {}
local GameLogic = nil

function BlackJack.init(gl)
    GameLogic = gl
end

function BlackJack.startRound()
    GameLogic.phase = "BETTING"
    GameLogic.trick = {}
    
    for i=1, 4 do
        GameLogic.players[i].hand = {}
        GameLogic.players[i].currentBet = 0
        GameLogic.players[i].isStood = false
        GameLogic.players[i].isBusted = false
        if not GameLogic.players[i].chips then
            GameLogic.players[i].chips = 1000
        end
    end

    local activePlayersStart = 0
    for i=1, 4 do if GameLogic.players[i].chips > 0 then activePlayersStart = activePlayersStart + 1 end end
    
    if activePlayersStart == 0 then
        GameLogic.phase = "MATCH_OVER"
        GameLogic.syncState()
        return
    end
    
    BlackJack.dealerHand = {}
    BlackJack.dealerStood = false
    BlackJack.dealerBusted = false
    BlackJack.deck = GameLogic.generateDeck()
    
    -- Multiply deck by 4 (4 deck shoe typical for black jack)
    local shoe = {}
    for i=1, 4 do
        for _, c in ipairs(BlackJack.deck) do table.insert(shoe, {suit=c.suit, rank=c.rank}) end
    end
    BlackJack.deck = shoe
    GameLogic.shuffle(BlackJack.deck)
    
    GameLogic.syncState()
end

function BlackJack.dealInitialCards()
    for i=1, 4 do
        if GameLogic.players[i].currentBet > 0 then
            table.insert(GameLogic.players[i].hand, table.remove(BlackJack.deck))
            table.insert(GameLogic.players[i].hand, table.remove(BlackJack.deck))
            -- setup vis
            for j, c in ipairs(GameLogic.players[i].hand) do
                c.visX, c.visY = GameLogic.getPlayerAnchor(i)
            end
        else
            GameLogic.players[i].isStood = true -- auto stand if no bet
        end
    end
    table.insert(BlackJack.dealerHand, table.remove(BlackJack.deck))
    table.insert(BlackJack.dealerHand, table.remove(BlackJack.deck))
    
    GameLogic.phase = "PLAYER_TURNS"
    GameLogic.currentPlayer = 1
    BlackJack.advanceTurnIfFixed()
end

function BlackJack.getValue(hand)
    local val = 0
    local aces = 0
    for _, c in ipairs(hand) do
        if c.rank == "A" then
            val = val + 11
            aces = aces + 1
        elseif c.rank == "K" or c.rank == "Q" or c.rank == "J" then
            val = val + 10
        else
            val = val + tonumber(c.rank)
        end
    end
    while val > 21 and aces > 0 do
        val = val - 10
        aces = aces - 1
    end
    return val
end

function BlackJack.handleAction(playerIdx, action, betAmount)
    local p = GameLogic.players[playerIdx]
    
    if GameLogic.phase == "BETTING" then
        if action == "BET" then
            local toBet = math.min(betAmount, p.chips)
            if toBet > 0 then
                p.chips = p.chips - toBet
                p.currentBet = p.currentBet + toBet
            end
        elseif action == "ALL_IN" then
            local toBet = p.chips
            if toBet > 0 then
                p.chips = 0
                p.currentBet = p.currentBet + toBet
            end
        end
        -- If all have bet > 0 (or have 0 chips), start dealing
        local allBet = true
        for i=1, 4 do 
            local pCheck = GameLogic.players[i]
            if pCheck.currentBet == 0 and pCheck.chips > 0 then 
                allBet = false 
            end 
        end
        if allBet then
            BlackJack.dealInitialCards()
            GameLogic.syncState()
            return
        end
    elseif GameLogic.phase == "PLAYER_TURNS" then
        if action == "HIT" and not p.isStood and not p.isBusted then
            table.insert(p.hand, table.remove(BlackJack.deck))
            local val = BlackJack.getValue(p.hand)
            if val > 21 then
                p.isBusted = true
            end
        elseif action == "STAND" then
            p.isStood = true
        end
        BlackJack.advanceTurnIfFixed()
    end
    
    GameLogic.syncState()
end

function BlackJack.advanceTurnIfFixed()
    if GameLogic.currentPlayer > 4 then
        GameLogic.currentPlayer = 1
        GameLogic.phase = "DEALER_TURN"
        return
    end

    local p = GameLogic.players[GameLogic.currentPlayer]
    if p.isStood or p.isBusted or p.currentBet == 0 then
        GameLogic.currentPlayer = GameLogic.currentPlayer + 1
        BlackJack.advanceTurnIfFixed() -- recursive forward
    else
        GameLogic.turnTimer = GameLogic.maxTurnTime or 15
    end
end

function BlackJack.playTurnBot()
    if GameLogic.phase == "BETTING" then
        for i=1, 4 do
            if GameLogic.players[i].isBot and GameLogic.players[i].currentBet == 0 and GameLogic.players[i].chips > 0 then
                BlackJack.handleAction(i, "BET", 50)
                return
            end
        end
    elseif GameLogic.phase == "PLAYER_TURNS" then
        local p = GameLogic.players[GameLogic.currentPlayer]
        local val = BlackJack.getValue(p.hand)
        if val < 17 then
            BlackJack.handleAction(GameLogic.currentPlayer, "HIT")
        else
            BlackJack.handleAction(GameLogic.currentPlayer, "STAND")
        end
    end
end

function BlackJack.isBotTurn()
    if GameLogic.phase == "BETTING" then
        for i=1, 4 do
            if GameLogic.players[i].isBot and GameLogic.players[i].currentBet == 0 and GameLogic.players[i].chips > 0 then
                return true
            end
        end
        return false
    end
    return GameLogic.players[GameLogic.currentPlayer].isBot
end

local evalTimer = 0
function BlackJack.update(dt)
    -- Animate other players' hands physically (since GameLogic only animates local)
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    for i=1, 4 do
        if i ~= GameLogic.myPlayerIdx then
            local p = GameLogic.players[i]
            if p.hand and #p.hand > 0 then
                local px, py = GameLogic.getPlayerAnchor(i)
                local dirX, dirY = cx - px, cy - py
                local rel = (i - GameLogic.myPlayerIdx) % 4
                local targetXBase = px
                local targetYBase = py
                if rel == 1 then -- LEFT
                    targetXBase = px + math.min(#p.hand * 15 + 100, 200)
                    targetYBase = py - 40
                elseif rel == 2 then -- TOP
                    targetXBase = cx
                    targetYBase = py + 120
                elseif rel == 3 then -- RIGHT
                    targetXBase = px - math.min(#p.hand * 15 + 100, 200)
                    targetYBase = py - 40
                end
                
                local startX = targetXBase - (#p.hand * 30)/2
                for j, c in ipairs(p.hand) do
                    local targetX = startX + (j-1)*30
                    local targetY = targetYBase
                    if not c.visX then c.visX, c.visY = px, py end
                    c.visX = c.visX + (targetX - c.visX) * dt * 8
                    c.visY = c.visY + (targetY - c.visY) * dt * 8
                end
            end
        end
    end

    if GameLogic.phase == "DEALER_TURN" then
        evalTimer = evalTimer + dt
        if evalTimer > 1.0 then
            evalTimer = 0
            if GameLogic.mode ~= "GUEST" then
                local val = BlackJack.getValue(BlackJack.dealerHand)
                if val < 17 then
                    table.insert(BlackJack.dealerHand, table.remove(BlackJack.deck))
                else
                    BlackJack.dealerStood = true
                    if val > 21 then BlackJack.dealerBusted = true end
                    GameLogic.phase = "PAYOUTS"
                    BlackJack.resolvePayouts()
                end
                GameLogic.syncState()
            end
        end
    elseif GameLogic.phase == "PAYOUTS" then
        evalTimer = evalTimer + dt
        if evalTimer > 3.0 then
            evalTimer = 0
            if GameLogic.mode ~= "GUEST" then
                BlackJack.startRound()
            end
        end
    end
end

function BlackJack.resolvePayouts()
    local dealerVal = BlackJack.getValue(BlackJack.dealerHand)
    for i=1, 4 do
        local p = GameLogic.players[i]
        if p.currentBet > 0 then
            local pVal = BlackJack.getValue(p.hand)
            if p.isBusted then
                -- lose
            elseif BlackJack.dealerBusted then
                if pVal == 21 and #p.hand == 2 then
                    p.chips = p.chips + math.floor(p.currentBet * 2.5)
                else
                    p.chips = p.chips + (p.currentBet * 2)
                end
            elseif pVal == 21 and #p.hand == 2 then
                p.chips = p.chips + math.floor(p.currentBet * 2.5) -- Natural blackjack pays 3:2!
            elseif pVal > dealerVal then
                p.chips = p.chips + (p.currentBet * 2)
            elseif pVal == dealerVal then
                p.chips = p.chips + p.currentBet -- push
            end
            p.currentBet = 0
        end
    end
end


function BlackJack.drawScoreboard(cx, cy, W, H)
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

    local btnText = isCollapsed and "[+] SCOREBOARD" or "[-] SCOREBOARD"
    love.graphics.setColor(1, 0.85, 0.3, 1)
    love.graphics.printf(btnText, sbX, sbY + 8, sbWidth, "center")

    if not isCollapsed then
        local colName = 10
        local colChips = 130
        local colBet = 190 -- Defined here correctly

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
            local isCurrent = (i == GameLogic.currentPlayer and GameLogic.phase ~= "ROUND_OVER")
            
            local pColor = isCurrent and {0.3, 0.95, 0.4, 1} or {1, 1, 1, 1}
            if p.isStood then pColor = {0.6, 0.9, 0.6, 1} end
            if p.isBusted then pColor = {0.8, 0.5, 0.5, 1} end
            
            GameLogic.drawTruncatedText(p.name, sbX + colName, scoreY, colChips - colName - 5, "left", pColor)
            GameLogic.drawText("$" .. tostring(p.chips), sbX + colChips, scoreY, 60, "left", {0.8, 0.8, 0.8, 1})
            
            -- FIXED: Changed coBet to colBet
            if p.currentBet and p.currentBet > 0 then
                GameLogic.drawText("$" .. p.currentBet, sbX + colBet, scoreY, 60, "right", {0.4, 0.9, 0.4, 1})
            else
                GameLogic.drawText("-", sbX + colBet, scoreY, 60, "right", {0.4, 0.4, 0.4, 1})
            end
            scoreY = scoreY + 24
        end
    end

    love.graphics.setFont(oldFont)
end


function BlackJack.drawCallingUI(cx, cy, W, H)
    -- Dealer Hand
    if GameLogic.phase ~= "BETTING" and BlackJack.dealerHand and #BlackJack.dealerHand > 0 then
        local startX = cx - (#BlackJack.dealerHand * 35)
        local startY = cy - 100
        GameLogic.drawText("House Dealer", 0, startY - 20, W, "center", {1, 0.8, 0.8, 1})
        for i, c in ipairs(BlackJack.dealerHand) do
            if i == 1 and GameLogic.phase == "PLAYER_TURNS" then
                -- Face down
                GameLogic.drawCardBack(startX + (i-1)*75 + 35, startY + 50, 0)
            else
                GameLogic.drawCard(c, startX + (i-1)*75, startY, true)
            end
        end
        -- Dealer total (only visible after player turns)
        if GameLogic.phase == "DEALER_TURN" or GameLogic.phase == "PAYOUTS" then
            local val = BlackJack.getValue(BlackJack.dealerHand)
            GameLogic.drawText("Val: " .. val, 0, startY + 110, W, "center", {1, 0.9, 0.4, 1})
        end
    end

    -- Draw other players' hands and their Blackjack Values
    for i=1, 4 do
        local p = GameLogic.players[i]
        
        -- Physical cards for non-local
        if i ~= GameLogic.myPlayerIdx and p.hand then
            for _, c in ipairs(p.hand) do
                if c.visX then GameLogic.drawCard(c, c.visX, c.visY, true) end
            end
        end
        
        -- Hand values for all players who are active
        if p.hand and #p.hand > 0 then
            local pVal = BlackJack.getValue(p.hand)
            local px, py
            if i == GameLogic.myPlayerIdx then
                -- Local hand floats just above their cards
                px, py = cx, H - 150
            else
                local bx, by = GameLogic.getPlayerAnchor(i)
                local rel = (i - GameLogic.myPlayerIdx) % 4
                if rel == 1 then -- LEFT
                    px = bx + math.min(#p.hand * 15 + 100, 200)
                    py = by + 60
                elseif rel == 2 then -- TOP
                    px = cx
                    py = by + 190
                elseif rel == 3 then -- RIGHT
                    px = bx - math.min(#p.hand * 15 + 100, 200)
                    py = by + 60
                end
            end
            
            local color = {0.8, 0.8, 1, 1}
            local txt = "Val: " .. pVal
            if p.isBusted then txt = "BUSTED"; color = {1, 0.3, 0.3, 1} end
            if p.isStood then txt = txt .. " (Stood)"; color = {0.6, 0.9, 0.6, 1} end
            
            GameLogic.drawText(txt, px - 60, py, 120, "center", color)
        end
    end

    -- User Actions Panel
    if GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.myPlayerIdx].isBot then
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local startY = cy + 50
        
        if GameLogic.phase == "BETTING" and p.currentBet == 0 then
            local startX = cx - 110
            
            love.graphics.setColor(0.3, 0.8, 0.3, 1)
            love.graphics.rectangle("fill", startX, startY, 100, 40, 8)
            GameLogic.drawText("BET $50", startX, startY + 10, 100, "center")
            
            love.graphics.setColor(0.9, 0.6, 0.1, 1)
            love.graphics.rectangle("fill", startX + 120, startY, 100, 40, 8)
            GameLogic.drawText("ALL IN", startX + 120, startY + 10, 100, "center")
        elseif GameLogic.phase == "PLAYER_TURNS" and not p.isStood and not p.isBusted then
            local startX = cx - 100
            
            love.graphics.setColor(0.8, 0.2, 0.2, 1)
            love.graphics.rectangle("fill", startX, startY, 80, 40, 8)
            GameLogic.drawText("HIT", startX, startY + 10, 80, "center")
            
            love.graphics.setColor(0.2, 0.8, 0.8, 1)
            love.graphics.rectangle("fill", startX + 120, startY, 80, 40, 8)
            GameLogic.drawText("STAND", startX + 120, startY + 10, 80, "center")
        end
    end
end

function BlackJack.mousepressed(x, y, button)
    local W, H = _G.getW(), _G.getH()
    local cx, cy = W / 2, H / 2
    local p = GameLogic.players[GameLogic.myPlayerIdx]
    
    local sbWidth = 260
    local sbX = W - sbWidth - 15
    local sbY = 15
    if x >= sbX and x <= sbX + sbWidth and y >= sbY and y <= sbY + 30 then
        GameLogic.isScoreboardCollapsed = not GameLogic.isScoreboardCollapsed
        return
    end

    local startY = cy + 50
    
    if GameLogic.currentPlayer == GameLogic.myPlayerIdx and not p.isBot then
        if GameLogic.phase == "BETTING" and p.currentBet == 0 then
            local startX = cx - 110
            if x >= startX and x <= startX + 100 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="BET", amount=50})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "BET", 50) end
            elseif x >= startX + 120 and x <= startX + 220 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="ALL_IN"})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "ALL_IN") end
            end
        elseif GameLogic.phase == "PLAYER_TURNS" and not p.isStood and not p.isBusted then
            local playStartX = cx - 100
            if x >= playStartX and x <= playStartX + 80 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="HIT"})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "HIT") end
            elseif x >= playStartX + 120 and x <= playStartX + 200 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="STAND"})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "STAND") end
            end
        end
    end
end

function BlackJack.canPlayCard(card, hand) return false end 

function BlackJack.applyStateExt(state)
    BlackJack.dealerHand = state.dealerHand or {}
    BlackJack.dealerStood = state.dealerStood or false
    BlackJack.dealerBusted = state.dealerBusted or false
end

function BlackJack.getStateExt(state)
    state.dealerHand = BlackJack.dealerHand
    state.dealerStood = BlackJack.dealerStood
    state.dealerBusted = BlackJack.dealerBusted
end

function BlackJack.handleNetworkMessage(evt)
    if evt.data.action == "BLACKJACK_ACTION" then
        for i=1, 4 do
            if GameLogic.players[i].id == evt.clientId and i == GameLogic.currentPlayer then
                BlackJack.handleAction(i, evt.data.type, evt.data.amount)
                return true
            end
        end
    end
    return false
end

function BlackJack.getPlayerStateExt(p, pSafe)
    pSafe.chips = p.chips
    pSafe.currentBet = p.currentBet
    pSafe.isStood = p.isStood
    pSafe.isBusted = p.isBusted
end

function BlackJack.applyPlayerStateExt(pSafe, p)
    p.chips = pSafe.chips or 0
    p.currentBet = pSafe.currentBet or 0
    p.isStood = pSafe.isStood or false
    p.isBusted = pSafe.isBusted or false
end

return BlackJack
