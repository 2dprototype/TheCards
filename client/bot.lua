local Bot = {}

-- Evaluates hand to make a reasonable call (guess how many tricks it can win)
function Bot.makeCall(hand)
    local call = 0
    local counts = {S=0, H=0, D=0, C=0}
    
    for _, card in ipairs(hand) do
        counts[card.suit] = counts[card.suit] + 1
        
        -- High cards evaluate to calls
        if card.rank == "A" then call = call + 1
        elseif card.rank == "K" and card.suit == "S" then call = call + 1
        elseif card.rank == "K" and math.random() > 0.5 then call = call + 1
        end
    end
    
    -- Extra calls for spades length
    if counts["S"] > 4 then
        call = call + (counts["S"] - 4)
    end
    
    -- Minimum call is 1 usually, but let's say minimum is 1 for bot safety
    if call < 1 then call = 1 end
    if call > 8 then call = 8 end
    
    return call
end

-- Chooses a card to play based on the current trick and hand
function Bot.playCard(hand, trickLeadSuit)
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
    
    -- Extremely simple AI: Play random valid card
    -- For a "better" bot, it would try to win if it hasn't reached its call, or lose if it has.
    local choiceIdx = math.random(1, #validCards)
    local chosenCard = validCards[choiceIdx]
    
    -- Find index in original hand to remove
    for i, c in ipairs(hand) do
        if c.suit == chosenCard.suit and c.rank == chosenCard.rank then
            return i, c
        end
    end
end

return Bot
