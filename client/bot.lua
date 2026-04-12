local Bot = {}

local rankValues = {["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, ["J"]=11, ["Q"]=12, ["K"]=13, ["A"]=14}

-- Evaluates hand to make a reasonable call (guess how many tricks it can win)
function Bot.makeCall(hand)
    local call = 0
    local counts = {S=0, H=0, D=0, C=0}
    
    for _, card in ipairs(hand) do
        counts[card.suit] = counts[card.suit] + 1
        
        -- High cards evaluate to calls
        if card.rank == "A" then call = call + 1
        elseif card.rank == "K" then call = call + 0.5
        elseif card.rank == "Q" and card.suit == "S" then call = call + 0.5
        end
    end
    
    -- Extra calls for spades length
    if counts["S"] > 4 then
        call = call + (counts["S"] - 4)
    end
    
    call = math.floor(call + 0.5)
    
    -- Minimum call is 1 usually, max 8
    if call < 1 then call = 1 end
    if call > 8 then call = 8 end
    
    return call
end

-- Chooses a card to play based on the current trick and hand
function Bot.playCard(hand, trickLeadSuit, trick, myCall, myTricksWon)
    local validCards = {}
    
    -- Filter valid cards according to follow suit rule
    if trickLeadSuit then
        for _, card in ipairs(hand) do
            if card.suit == trickLeadSuit then
                table.insert(validCards, card)
            end
        end
    end
    
    -- If no valid cards matching suit or no suit lead, all cards are valid
    if #validCards == 0 then
        for _, card in ipairs(hand) do
            table.insert(validCards, card)
        end
    end
    
    -- Need to know if we want to win this trick
    local needTricks = (myTricksWon or 0) < (myCall or 1)
    
    -- Evaluate the current winning card in the trick
    local bestCard = nil
    if trick and #trick > 0 then
        bestCard = trick[1].card
        for i = 2, #trick do
            local c = trick[i].card
            local isSpade = (c.suit == "S")
            local bestIsSpade = (bestCard.suit == "S")
            if isSpade and not bestIsSpade then
                bestCard = c
            elseif isSpade and bestIsSpade and rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c
            elseif c.suit == trickLeadSuit and bestCard.suit == trickLeadSuit and rankValues[c.rank] > rankValues[bestCard.rank] then
                bestCard = c
            end
        end
    end
    
    -- Sort valid cards from lowest value to highest value
    table.sort(validCards, function(a, b) 
        -- Make Spades artificially higher value so bots don't waste spades if they don't have to
        local aVal = rankValues[a.rank] + (a.suit == "S" and 20 or 0)
        local bVal = rankValues[b.rank] + (b.suit == "S" and 20 or 0)
        return aVal < bVal
    end)
    
    local chosenCard = validCards[1] -- default lowest
    
    if needTricks then
        if not bestCard then
            -- Leading a trick and we need tricks: try playing highest card
            -- We might prioritize a high off-suit over a Spade to draw out cards
            -- Resort temporarily to prioritize high rank first
            local tempValid = {}
            for _, v in ipairs(validCards) do table.insert(tempValid, v) end
            table.sort(tempValid, function(a,b) return rankValues[a.rank] < rankValues[b.rank] end)
            chosenCard = tempValid[#tempValid]
        else
            -- Following: try to find the lowest card that can beat the bestCard
            local winningCards = {}
            for _, c in ipairs(validCards) do
                local canWin = false
                if c.suit == "S" and bestCard.suit ~= "S" then canWin = true
                elseif c.suit == "S" and bestCard.suit == "S" and rankValues[c.rank] > rankValues[bestCard.rank] then canWin = true
                elseif c.suit == trickLeadSuit and bestCard.suit == trickLeadSuit and rankValues[c.rank] > rankValues[bestCard.rank] then canWin = true
                end
                if canWin then table.insert(winningCards, c) end
            end
            
            if #winningCards > 0 then
                -- They are already sorted lowest to highest absolute value, so [1] is the lowest winning card
                chosenCard = winningCards[1]
            end
        end
    else
        -- Don't want to win tricks
        if bestCard then
            -- We follow, play our lowest card
            chosenCard = validCards[1]
        else
            -- Leading: play lowest card to offload
            chosenCard = validCards[1]
        end
    end
    
    -- Find index in original hand to remove
    for i, c in ipairs(hand) do
        if c.suit == chosenCard.suit and c.rank == chosenCard.rank then
            return i, c
        end
    end
end

return Bot
