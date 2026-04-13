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
        table.insert(GameLogic.players[i].hand, table.remove(BlackJack.deck))
        table.insert(GameLogic.players[i].hand, table.remove(BlackJack.deck))
        -- setup vis
        for j, c in ipairs(GameLogic.players[i].hand) do
            c.visX, c.visY = GameLogic.getPlayerAnchor(i)
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
            if p.chips >= betAmount then
                p.chips = p.chips - betAmount
                p.currentBet = p.currentBet + betAmount
            end
        end
        -- If all have bet > 0, start dealing
        local allBet = true
        for i=1, 4 do if GameLogic.players[i].currentBet == 0 then allBet = false end end
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
    local p = GameLogic.players[GameLogic.currentPlayer]
    if p.isStood or p.isBusted then
        GameLogic.currentPlayer = GameLogic.currentPlayer + 1
        if GameLogic.currentPlayer > 4 then
            GameLogic.phase = "DEALER_TURN"
        end
        BlackJack.advanceTurnIfFixed() -- recursive forward
    end
end

function BlackJack.playTurnBot()
    local p = GameLogic.players[GameLogic.currentPlayer]
    if GameLogic.phase == "BETTING" then
        BlackJack.handleAction(GameLogic.currentPlayer, "BET", 50)
    elseif GameLogic.phase == "PLAYER_TURNS" then
        local val = BlackJack.getValue(p.hand)
        if val < 17 then
            BlackJack.handleAction(GameLogic.currentPlayer, "HIT")
        else
            BlackJack.handleAction(GameLogic.currentPlayer, "STAND")
        end
    end
end

function BlackJack.isBotTurn()
    return GameLogic.players[GameLogic.currentPlayer].isBot
end

local evalTimer = 0
function BlackJack.update(dt)
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
        local pVal = BlackJack.getValue(p.hand)
        if p.isBusted then
            -- lose
        elseif BlackJack.dealerBusted then
            p.chips = p.chips + (p.currentBet * 2)
        elseif pVal > dealerVal then
            p.chips = p.chips + (p.currentBet * 2)
        elseif pVal == dealerVal then
            p.chips = p.chips + p.currentBet -- push
        end
        p.currentBet = 0
    end
end

function BlackJack.drawScoreboard(cx, cy, W, H)
    -- Custom Scoreboard code
    local sbWidth = 280
    local sbHeight = 80 + (4 * 30)
    local sbX = W - sbWidth - 15
    local sbY = 15

    love.graphics.setColor(0.05, 0.05, 0.1, 0.75)
    love.graphics.rectangle("fill", sbX, sbY, sbWidth, sbHeight, 10)
    love.graphics.setColor(1, 1, 1, 0.1)
    love.graphics.rectangle("line", sbX, sbY, sbWidth, sbHeight, 10)

    GameLogic.drawText("SCOREBOARD (Black Jack)", sbX, sbY + 12, sbWidth, "center", {1, 0.85, 0.3, 1})
    
    local scoreY = sbY + 65
    for i=1, 4 do
        local p = GameLogic.players[i]
        GameLogic.drawText(p.name .. ": $" .. tostring(p.chips), sbX + 15, scoreY, 200, "left")
        if p.currentBet > 0 then
            GameLogic.drawText("[$" .. p.currentBet .. "]", sbX + 220, scoreY, 50, "left", {0.4, 0.9, 0.4, 1})
        end
        scoreY = scoreY + 30
    end
end

function BlackJack.drawCallingUI(cx, cy, W, H)
    -- Dealer Hand
    if GameLogic.phase ~= "BETTING" and BlackJack.dealerHand and #BlackJack.dealerHand > 0 then
        local startX = cx - (#BlackJack.dealerHand * 35)
        local startY = cy - 140
        GameLogic.drawText("House Dealer", 0, startY - 20, W, "center", {1, 0.8, 0.8, 1})
        for i, c in ipairs(BlackJack.dealerHand) do
            if i == 1 and GameLogic.phase == "PLAYER_TURNS" then
                -- Face down
                GameLogic.drawCardBack(startX + (i-1)*75 + 35, startY + 50, 0)
            else
                GameLogic.drawCard(c, startX + (i-1)*75, startY, true)
            end
        end
    end

    if GameLogic.currentPlayer == GameLogic.myPlayerIdx and not GameLogic.players[GameLogic.myPlayerIdx].isBot then
        local p = GameLogic.players[GameLogic.myPlayerIdx]
        local startX = cx - 100
        local startY = cy + 50
        
        if GameLogic.phase == "BETTING" and p.currentBet == 0 then
            love.graphics.setColor(0.3, 0.8, 0.3, 1)
            love.graphics.rectangle("fill", startX + 50, startY, 100, 40, 8)
            GameLogic.drawText("BET $50", startX + 50, startY + 10, 100, "center")
        elseif GameLogic.phase == "PLAYER_TURNS" and not p.isStood and not p.isBusted then
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
    local cx, cy = _G.getW() / 2, _G.getH() / 2
    local p = GameLogic.players[GameLogic.myPlayerIdx]
    local startX = cx - 100
    local startY = cy + 50
    
    if GameLogic.currentPlayer == GameLogic.myPlayerIdx and not p.isBot then
        if GameLogic.phase == "BETTING" and p.currentBet == 0 then
            if x >= startX + 50 and x <= startX + 150 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="BET", amount=50})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "BET", 50) end
            end
        elseif GameLogic.phase == "PLAYER_TURNS" and not p.isStood and not p.isBusted then
            if x >= startX and x <= startX + 80 and y >= startY and y <= startY + 40 then
                if GameLogic.mode == "GUEST" then require("network").sendGameMessage("host", {action="BLACKJACK_ACTION", type="HIT"})
                else BlackJack.handleAction(GameLogic.myPlayerIdx, "HIT") end
            elseif x >= startX + 120 and x <= startX + 200 and y >= startY and y <= startY + 40 then
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
