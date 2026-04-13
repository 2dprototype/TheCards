local OldMaid = {}
local GameLogic = nil

function OldMaid.init(gl)
    GameLogic = gl
end

function OldMaid.playTurnBot()
    -- Sub-task
end

function OldMaid.resolveTrick()
    -- Sub-task
end

function OldMaid.update(dt)
    -- Sub-task
end

function OldMaid.drawScoreboard(cx, cy, W, H)
    GameLogic.drawText("SCOREBOARD (Old Maid)", W - 295, 27, 280, "center", {1, 0.85, 0.3, 1})
end

function OldMaid.drawCallingUI(cx, cy, W, H)
    -- Sub-task
end

function OldMaid.mousepressed(x, y, button)
    -- Sub-task
end

function OldMaid.canPlayCard(card, playerHand)
    return true
end

return OldMaid
