-- ============================================================================
-- Horse Betting - Real-time betting with automatic race start
-- Redesigned: Top track, bottom betting, no lock phase, unpredictable races
-- ============================================================================
local HorseBetting = {}
local GameLogic = nil

-- ----------------------------------------------------------------------------
-- Deterministic PRNG for race simulation (ensures cross-platform sync)
-- ----------------------------------------------------------------------------
local PRNG = {}
PRNG.__index = PRNG

function PRNG.new(seed)
    local self = setmetatable({}, PRNG)
    self.seed = seed or 12345
    return self
end

function PRNG:nextFloat()
    self.seed = (self.seed * 1103515245 + 12345) % 2147483648
    return self.seed / 2147483648
end

function PRNG:randomRange(min, max)
    return min + self:nextFloat() * (max - min)
end

function PRNG:random(min, max)
    if not min then return self:nextFloat() end
    if not max then return math.floor(self:nextFloat() * min) + 1 end
    return math.floor(self:nextFloat() * (max - min + 1)) + min
end

-- ----------------------------------------------------------------------------
-- Helper for bets (robust numeric keys)
-- ----------------------------------------------------------------------------
local function getBet(bets, idx)
    if not bets then return 0 end
    return bets[idx] or 0
end

local function setBet(bets, idx, val)
    if not bets then return end
    bets[idx] = val
end

-- ----------------------------------------------------------------------------
-- Font Cache Helper (Fixes per-frame creation performance degradation)
-- ----------------------------------------------------------------------------
local fontCache = {}
local function getFont(size)
    if not fontCache[size] then
        fontCache[size] = love.graphics.newFont(size)
    end
    return fontCache[size]
end


-- ----------------------------------------------------------------------------
-- Theme – Classic Derby style
-- ----------------------------------------------------------------------------
local THEME = {
    bg          = {0.07, 0.09, 0.13, 1},       -- Deep premium dark slate
    track_bg    = {0.12, 0.28, 0.18, 1},       -- Refined field turf green
    track_dark  = {0.09, 0.22, 0.14, 1},       -- Muted alternating track lanes
    track_border= {0.35, 0.45, 0.55, 0.5},     -- Clean steel borders
    panel       = {0.14, 0.18, 0.25, 0.95},    -- Cohesive card panels
    panel_border= {0.22, 0.28, 0.38, 0.85},    -- Crisp geometric borders
    text_gold   = {0.92, 0.75, 0.38, 1},       -- Elegant accent gold
    text_green  = {0.22, 0.82, 0.48, 1},       -- High-visibility profit green
    text_white  = {0.94, 0.95, 0.98, 1},       -- Pure high-contrast white
    text_muted  = {0.55, 0.62, 0.72, 1},       -- Legible slate grey
    btn_minus   = {0.72, 0.28, 0.28},          -- Controlled luxury red
    btn_plus    = {0.24, 0.50, 0.78},          -- Clean interface blue
    btn_allin   = {0.85, 0.53, 0.18},          -- Action warning amber
    btn_lock    = {0.18, 0.66, 0.38},          -- Success emerald green
}

local HORSE_NAMES = {
    "Silver Bullet", "Gilded Glory", "Thunderbolt", "Midnight Run",
    "Starry Night", "Wind Runner", "Shadow Fox", "Blazing Saddle"
}

local HORSE_COLORS = {
    {0.85, 0.20, 0.20}, -- 1: Crimson
    {0.95, 0.95, 0.95}, -- 2: White
    {0.20, 0.45, 0.85}, -- 3: Royal Blue
    {0.90, 0.80, 0.15}, -- 4: Gold
    {0.12, 0.12, 0.14}, -- 5: Black
}

-- ----------------------------------------------------------------------------
-- Module state
-- ----------------------------------------------------------------------------
HorseBetting.overrideDraw = true
HorseBetting.phase = "BETTING"      -- BETTING, RACING, RESULT
HorseBetting.horses = {}
HorseBetting.raceSeed = 0
HorseBetting.racePRNG = nil
HorseBetting.elapsedTime = 0
HorseBetting.podium = {}
HorseBetting.winningHorseIdx = nil
HorseBetting.dustParticles = {}

local bettingTimer = 20            -- seconds for betting phase
local raceEndTimer = 0
local celebrationParticles = {}
local winnerFlashTimer = 0

-- ----------------------------------------------------------------------------
-- Helper: Draw a stylish button
-- ----------------------------------------------------------------------------
local function drawButton(text, x, y, w, h, bgCol, active, mx, my, pulse)
    local hover = active and (mx >= x and mx <= x + w and my >= y and my <= y + h)
    local alpha = 1
    if pulse and not hover then
        alpha = 0.7 + math.sin(love.timer.getTime() * 5) * 0.3
    end
    if not active then
        love.graphics.setColor(bgCol[1], bgCol[2], bgCol[3], 0.25)
    elseif hover then
        love.graphics.setColor(bgCol[1]*1.15, bgCol[2]*1.15, bgCol[3]*1.15, 1)
    else
        love.graphics.setColor(bgCol[1], bgCol[2], bgCol[3], alpha)
    end
    love.graphics.rectangle("fill", x, y, w, h, 6)
    love.graphics.setColor(1,1,1, active and 0.15 or 0.05)
    love.graphics.rectangle("line", x, y, w, h, 6)
    love.graphics.setColor(1,1,1, active and (hover and 1 or 0.85) or 0.4)
    love.graphics.setFont(getFont(12))
    love.graphics.printf(text, x, y + (h - love.graphics.getFont():getHeight())/2, w, "center")
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------
function HorseBetting.init(gl)
    GameLogic = gl
end

function HorseBetting.startRound()
    bettingTimer = 20
    raceEndTimer = 0
    winnerFlashTimer = 0
    celebrationParticles = {}
    HorseBetting.phase = "BETTING"
    HorseBetting.elapsedTime = 0
    HorseBetting.podium = {}
    HorseBetting.winningHorseIdx = nil
    HorseBetting.dustParticles = {}
    HorseBetting.racePRNG = nil

    -- Reset player bets and ensure chips
    for i = 1, 4 do
        local p = GameLogic.players[i]
        if p then
            if not p.chips or p.chips <= 0 then p.chips = 1000 end
            p.bets = {0, 0, 0, 0, 0}
            p.roundPayout = 0
        end
    end

    -- Generate horses (only host/offline)
    if GameLogic.mode ~= "GUEST" then
        local names = {}
        for _, n in ipairs(HORSE_NAMES) do table.insert(names, n) end
        for i = #names, 2, -1 do
            local j = math.random(i)
            names[i], names[j] = names[j], names[i]
        end

        HorseBetting.horses = {}
        -- Each horse gets unique stats: base speed, variance, burst chance, fatigue
        for lane = 1, 5 do
            -- Random odds between 2.0 and 15.0
            local odds = math.floor((2.0 + math.random() * 13.0) * 10) / 10
            local baseSpeed = 80 + math.random(60)  -- 80-140
            local variance = 15 + math.random(35)   -- 15-50
            local burstChance = 0.1 + math.random() * 0.3
            local burstSpeedBonus = 30 + math.random(40)
            local fatigueFactor = 0.005 + math.random() * 0.015  -- slows over time
            
            table.insert(HorseBetting.horses, {
                name = names[lane] or ("Horse "..lane),
                odds = odds,
                color = HORSE_COLORS[lane],
                baseSpeed = baseSpeed,
                variance = variance,
                burstChance = burstChance,
                burstSpeedBonus = burstSpeedBonus,
                fatigueFactor = fatigueFactor,
                x = 80,
                visX = 80,
                mood = 1.0,        -- random multiplier per race
                trail = {}
            })
            -- random mood
            HorseBetting.horses[lane].mood = 0.7 + math.random() * 0.8
        end
        
        -- Reset bot bets
        for i = 1, 4 do
            local p = GameLogic.players[i]
            if p and p.isBot then
                HorseBetting.generateBotBets(p)
            end
        end
        GameLogic.syncState()
    end
end

function HorseBetting.generateBotBets(bot)
    if not bot.chips then bot.chips = 1000 end
    local maxBet = math.floor(bot.chips * (0.15 + math.random() * 0.4))
    if maxBet < 20 then maxBet = math.min(50, bot.chips) end
    if maxBet <= 0 then return end

    -- Weighted by odds (lower odds = higher weight)
    local weights = {}
    local total = 0
    for idx, h in ipairs(HorseBetting.horses) do
        local w = 1.0 / h.odds
        table.insert(weights, w)
        total = total + w
    end
    local r = math.random() * total
    local selected = 1
    local sum = 0
    for idx, w in ipairs(weights) do
        sum = sum + w
        if r <= sum then selected = idx; break end
    end
    local betAmt = math.floor(maxBet / 10) * 10
    if betAmt > bot.chips then betAmt = bot.chips end
    bot.bets = {0,0,0,0,0}
    setBet(bot.bets, selected, betAmt)
end

-- Start race immediately (called when timer reaches 0)
local function startRace()
    if GameLogic.mode ~= "GUEST" then
        HorseBetting.raceSeed = math.random(100000, 999999)
        HorseBetting.racePRNG = PRNG.new(HorseBetting.raceSeed)
        HorseBetting.phase = "RACING"
        HorseBetting.elapsedTime = 0
        HorseBetting.podium = {}
        HorseBetting.winningHorseIdx = nil
        raceEndTimer = 0
        for _, h in ipairs(HorseBetting.horses) do
            h.x = 80
            h.visX = 80
            h.trail = {}
        end
        GameLogic.syncState()
    end
end

-- Bet adjustment
local function adjustBet(playerIdx, horseIdx, delta)
    local p = GameLogic.players[playerIdx]
    if not p then return false end
    if not p.chips then p.chips = 1000 end
    if not p.bets then p.bets = {0,0,0,0,0} end
    local currentTotal = 0
    for i=1,5 do currentTotal = currentTotal + getBet(p.bets, i) end
    local cur = getBet(p.bets, horseIdx)
    local new = cur + delta
    if new < 0 then new = 0 end
    if currentTotal - cur + new <= p.chips then
        setBet(p.bets, horseIdx, new)
        return true
    end
    return false
end

local function allIn(playerIdx, horseIdx)
    local p = GameLogic.players[playerIdx]
    if not p then return false end
    if not p.chips then p.chips = 1000 end
    if not p.bets then p.bets = {0,0,0,0,0} end
    local otherTotal = 0
    for i=1,5 do if i ~= horseIdx then otherTotal = otherTotal + getBet(p.bets, i) end end
    local remaining = p.chips - otherTotal
    if remaining > 0 then
        setBet(p.bets, horseIdx, getBet(p.bets, horseIdx) + remaining)
        return true
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Update (physics and timers)
-- ----------------------------------------------------------------------------
function HorseBetting.update(dt)
    -- Betting phase timer countdown
    if HorseBetting.phase == "BETTING" then
        if GameLogic.mode ~= "GUEST" then
            bettingTimer = bettingTimer - dt
            if bettingTimer <= 0 then
                bettingTimer = 0
                startRace()
            end
        end
        return
    end

    -- Racing phase
    if HorseBetting.phase == "RACING" then
        local fixed_dt = 0.03333
        local step = math.min(dt, 0.03333)
        local steps = math.floor(dt / fixed_dt) + 1
        for _ = 1, steps do
            if #HorseBetting.podium < 5 then
                HorseBetting.elapsedTime = HorseBetting.elapsedTime + fixed_dt
                local prng = HorseBetting.racePRNG or PRNG.new(HorseBetting.raceSeed)
                for i = 1,5 do
                    local h = HorseBetting.horses[i]
                    if h.x < 880 then
                        local fatigue = 1.0 - (h.x / 880) * h.fatigueFactor * 30
                        local moodEffect = h.mood
                        local fluc = prng:randomRange(-h.variance, h.variance)
                        local burst = 0
                        if prng:random() < h.burstChance * fixed_dt * 5 then
                            burst = h.burstSpeedBonus * (0.8 + prng:random() * 0.7)
                        end
                        local speed = (h.baseSpeed + fluc + burst) * fatigue * moodEffect
                        h.x = h.x + speed * fixed_dt
                        if h.x >= 880 then
                            h.x = 880
                            table.insert(HorseBetting.podium, i)
                            if #HorseBetting.podium == 1 then
                                HorseBetting.winningHorseIdx = i
                                winnerFlashTimer = 0.5
                            end
                        end
                    end
                end
            else
                raceEndTimer = raceEndTimer + fixed_dt
                if raceEndTimer >= 2.5 then
                    if GameLogic.mode ~= "GUEST" then
                        HorseBetting.phase = "RESULT"
                        HorseBetting.calculatePayouts()
                        -- FIXED: GameLogic.phase = "ROUND_OVER" was removed from here to prevent early game termination bug.
                        GameLogic.syncState()
                    end
                    break
                end
            end
        end

        -- Visual updates
        for i=1,5 do
            local h = HorseBetting.horses[i]
            h.visX = h.visX + (h.x - h.visX) * dt * 12
            if h.x < 880 then
                local center_y = 65 + (i-1)*32 + 16
                if math.random() < 0.3 then
                    table.insert(HorseBetting.dustParticles, {
                        x = h.visX - 10,
                        y = center_y + 5 + math.random(-3,3),
                        vx = -50 - math.random(40),
                        vy = -1 - math.random(4),
                        life = 0.3,
                        maxLife = 0.3,
                        size = 1 + math.random(2)
                    })
                end
                table.insert(h.trail, {x = h.visX, life = 0.2})
            end
            for j=#h.trail,1,-1 do
                h.trail[j].life = h.trail[j].life - dt
                if h.trail[j].life <= 0 then table.remove(h.trail, j) end
            end
        end

        for i=#HorseBetting.dustParticles,1,-1 do
            local p = HorseBetting.dustParticles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            if p.life <= 0 then table.remove(HorseBetting.dustParticles, i) end
        end

        if winnerFlashTimer > 0 then
            winnerFlashTimer = winnerFlashTimer - dt
        end
    end

    -- Result phase particles
    if HorseBetting.phase == "RESULT" then
        if #celebrationParticles < 100 and math.random() < 0.5 then
            table.insert(celebrationParticles, {
                x = _G.getW()/2 + math.random(-200,200),
                y = _G.getH()/2 - 40 + math.random(-60,60),
                vx = math.random(-80,80),
                vy = math.random(-150,-30),
                life = 1.2,
                color = {math.random(), math.random(), math.random()}
            })
        end
        for i=#celebrationParticles,1,-1 do
            local p = celebrationParticles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            if p.life <= 0 then table.remove(celebrationParticles, i) end
        end
    end
end


function HorseBetting.calculatePayouts()
    local winnerIdx = HorseBetting.winningHorseIdx
    if not winnerIdx then return end
    local wHorse = HorseBetting.horses[winnerIdx]
    for i=1,4 do
        local p = GameLogic.players[i]
        if p then
            if not p.chips then p.chips = 1000 end
            if not p.bets then p.bets = {0,0,0,0,0} end
            local totalBet = 0
            for h=1,5 do totalBet = totalBet + getBet(p.bets, h) end
            local winBet = getBet(p.bets, winnerIdx)
            local winnings = math.floor(winBet * wHorse.odds)
            p.roundPayout = winnings - totalBet
            p.chips = p.chips + p.roundPayout
            if p.chips <= 0 then p.chips = 500 end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Drawing
-- ----------------------------------------------------------------------------
function HorseBetting.draw(cx, cy, W, H)
    local mx, my = love.mouse.getPosition()
    
    -- Background
    love.graphics.setColor(THEME.bg)
    love.graphics.rectangle("fill", 0, 0, W, H)

    -- ===================== TOP PLAYER BOARD & TIMER =====================
    love.graphics.setColor(THEME.text_gold)
    love.graphics.setFont(getFont(14))
    love.graphics.printf(string.format("ROUND %d/%d", GameLogic.roundNum, GameLogic.totalRounds or 5), 20, 18, 120, "left")
    
    if HorseBetting.phase == "BETTING" then
        local timerText = string.format("BET: %ds", math.ceil(bettingTimer))
        love.graphics.setColor(bettingTimer <= 5 and {1,0.3,0.3,1} or THEME.text_green)
        love.graphics.printf(timerText, 140, 18, 100, "left")
    end

    -- Horizontal Header Scoreboard Container
    local startPX = 250
    local availPW = W - startPX - 20
    local itemW = availPW / 4
    
    for idx=1,4 do
        local p = GameLogic.players[idx]
        if p then
            local px = startPX + (idx-1)*itemW
            love.graphics.setColor(THEME.panel)
            love.graphics.rectangle("fill", px + 4, 10, itemW - 8, 34, 6)
            love.graphics.setColor(THEME.panel_border)
            love.graphics.rectangle("line", px + 4, 10, itemW - 8, 34, 6)

            local isMe = (p.id == (GameLogic.players[GameLogic.myPlayerIdx] and GameLogic.players[GameLogic.myPlayerIdx].id))
            love.graphics.setColor(isMe and THEME.text_green or THEME.text_white)
            love.graphics.setFont(getFont(11))
            love.graphics.print(p.name, px + 12, 13)

            local totalBet = 0
            if p.bets then for h=1,5 do totalBet = totalBet + getBet(p.bets, h) end end
            love.graphics.setColor(THEME.text_gold)
            love.graphics.setFont(getFont(10))
            love.graphics.print(string.format("$%d (Bet: $%d)", p.chips or 1000, totalBet), px + 12, 26)
        end
    end

    -- Divider line
    love.graphics.setColor(THEME.panel_border[1], THEME.panel_border[2], THEME.panel_border[3], 0.3)
    love.graphics.line(20, 52, W-20, 52)

    -- ===================== TRACK (SCALED DOWN LEFT SIDE) =====================
    local trackX, trackY = 20, 65
    local trackW = W * 0.62
    local trackH = 160
    local laneH = trackH / 5

    -- Draw lanes
    for i=1,5 do
        local ly = trackY + (i-1)*laneH
        love.graphics.setColor(i%2==0 and THEME.track_dark or THEME.track_bg)
        love.graphics.rectangle("fill", trackX, ly, trackW, laneH)
    end
    
    love.graphics.setColor(THEME.track_border)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", trackX, trackY, trackW, trackH)
    love.graphics.setLineWidth(1)
    
    -- Lane dividers
    for i=2,5 do
        local ly = trackY + (i-1)*laneH
        love.graphics.setColor(1,1,1,0.12)
        for dx = trackX+5, trackX+trackW-5, 20 do
            love.graphics.line(dx, ly, dx+10, ly)
        end
    end
    
    -- Finish Line calculation
    local finishX = trackX + trackW - 40
    local startGateX = trackX + 25
    love.graphics.setColor(1,1,1,0.3)
    love.graphics.line(startGateX, trackY, startGateX, trackY+trackH)
    love.graphics.rectangle("fill", finishX, trackY, 12, trackH)
    love.graphics.setColor(0.85,0.2,0.2,0.8)
    love.graphics.rectangle("fill", finishX+4, trackY, 3, trackH)

    -- Dust particles
    for _, p in ipairs(HorseBetting.dustParticles) do
        local alpha = (p.life/p.maxLife)*0.5
        love.graphics.setColor(0.5,0.4,0.3, alpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end

    -- Visual Horses scaling loop
    local activeTrackLength = finishX - startGateX
    for i=1,5 do
        local h = HorseBetting.horses[i]
        if h then
            local center_y = trackY + (i-1)*laneH + laneH/2
            local gallop = (h.x < 880 and HorseBetting.phase == "RACING") and math.abs(math.sin(HorseBetting.elapsedTime*22))*3 or 0
            
            -- Precise visual normalization conversion map
            local hx = startGateX + (h.visX - 80) * (activeTrackLength) / 800
            if hx < trackX then hx = trackX end
            if hx > trackX+trackW-12 then hx = trackX+trackW-12 end

            -- Trails
            for _, t in ipairs(h.trail) do
                local tx = startGateX + (t.x - 80) * (activeTrackLength) / 800
                love.graphics.setColor(h.color[1], h.color[2], h.color[3], t.life*0.4)
                love.graphics.circle("fill", tx, center_y+1, 6)
            end

            -- Horse Body Sphere
            love.graphics.setColor(0,0,0,0.25)
            love.graphics.circle("fill", hx, center_y+2, 11)
            love.graphics.setColor(h.color)
            love.graphics.circle("fill", hx, center_y - gallop, 11)
            love.graphics.setColor(1,1,1,0.5)
            love.graphics.circle("line", hx, center_y - gallop, 11)
            
            -- Minimal number tags
            love.graphics.setColor((i==2 or i==4) and {0.1,0.1,0.1,0.9} or {1,1,1,0.9})
            love.graphics.setFont(getFont(10))
            love.graphics.printf(tostring(i), hx-8, center_y-6-gallop, 16, "center")
        end
    end

    -- ===================== STANDINGS LEADERBOARD (RIGHT OF TRACK) =====================
    local lbX = trackX + trackW + 15
    local lbW = W - lbX - 20
    local lbY = trackY
    local lbH = trackH

    love.graphics.setColor(THEME.panel)
    love.graphics.rectangle("fill", lbX, lbY, lbW, lbH, 6)
    love.graphics.setColor(THEME.panel_border)
    love.graphics.rectangle("line", lbX, lbY, lbW, lbH, 6)
    
    love.graphics.setColor(THEME.text_gold)
    love.graphics.setFont(getFont(11))
    love.graphics.printf("RACE STANDINGS", lbX, lbY+6, lbW, "center")
    
    local order = {1,2,3,4,5}
    table.sort(order, function(a,b) return (HorseBetting.horses[a] and HorseBetting.horses[a].x or 0) > (HorseBetting.horses[b] and HorseBetting.horses[b].x or 0) end)
    
    for pos=1,5 do
        local hIdx = order[pos]
        local h = HorseBetting.horses[hIdx]
        if h then
            local py = lbY + 26 + (pos-1)*25
            local suffix = pos==1 and "st" or pos==2 and "nd" or pos==3 and "rd" or "th"
            love.graphics.setColor(THEME.text_muted)
            love.graphics.setFont(getFont(11))
            love.graphics.printf(pos..suffix..":", lbX + 10, py+2, 35, "left")
            
            love.graphics.setColor(THEME.text_white)
            love.graphics.printf(h.name, lbX + 42, py+2, lbW - 75, "left")
            
            love.graphics.setColor(h.color)
            love.graphics.circle("fill", lbX+lbW-16, py+8, 8)
            love.graphics.setColor((hIdx==2 or hIdx==4) and {0.1,0.1,0.1,0.9} or {1,1,1,0.9})
            love.graphics.setFont(getFont(9))
            love.graphics.printf(tostring(hIdx), lbX+lbW-21, py+3, 10, "center")
        end
    end

    -- ===================== BETTING PANEL (BOTTOM REGION) =====================
    if HorseBetting.phase == "BETTING" then
        local panelY = trackY + trackH + 15
        local panelH = H - panelY - 15
        love.graphics.setColor(THEME.panel)
        love.graphics.rectangle("fill", 20, panelY, W-40, panelH, 8)
        love.graphics.setColor(THEME.panel_border)
        love.graphics.rectangle("line", 20, panelY, W-40, panelH, 8)

        local myP = GameLogic.players[GameLogic.myPlayerIdx]
        local myTotal = 0
        if myP and myP.bets then for i=1,5 do myTotal = myTotal + getBet(myP.bets, i) end end
        local myRemaining = myP and ((myP.chips or 1000) - myTotal) or 0

        love.graphics.setColor(THEME.text_gold)
        love.graphics.setFont(getFont(13))
        love.graphics.printf("PLACE YOUR BETS (Available Balance: $"..myRemaining..")", 20, panelY+8, W-40, "center")

        local rowH = (panelH - 35) / 5
        local startY = panelY + 28
        
        for i=1,5 do
            local h = HorseBetting.horses[i]
            local ry = startY + (i-1)*rowH
            
            love.graphics.setColor(THEME.bg)
            love.graphics.rectangle("fill", 32, ry + 2, W-64, rowH - 4, 4)
            
            love.graphics.setColor(h.color)
            love.graphics.circle("fill", 50, ry + rowH/2, 11)
            love.graphics.setColor((i==2 or i==4) and {0.1,0.1,0.1,0.9} or {1,1,1,0.9})
            love.graphics.setFont(getFont(10))
            love.graphics.printf(tostring(i), 42, ry + rowH/2 - 6, 16, "center")
            
            love.graphics.setColor(THEME.text_white)
            love.graphics.setFont(getFont(12))
            love.graphics.print(h.name, 72, ry + (rowH/2 - 7))
            
            love.graphics.setColor(THEME.text_gold)
            love.graphics.print(string.format("%.1fx", h.odds), 205, ry + (rowH/2 - 7))
            
            local bet = myP and getBet(myP.bets, i) or 0
            love.graphics.setColor(THEME.text_muted)
            love.graphics.print("Bet:", 265, ry + (rowH/2 - 7))
            love.graphics.setColor(bet>0 and THEME.text_green or THEME.text_muted)
            love.graphics.print(bet>0 and ("$"..bet) or "-", 300, ry + (rowH/2 - 7))
            
            -- Symmetrically aligned operational hitboxes 
            local btnY = ry + (rowH - 26)/2
            drawButton("-50", 355, btnY, 50, 26, THEME.btn_minus, bet>=50, mx, my, false)
            drawButton("+10", 412, btnY, 50, 26, THEME.btn_plus, myRemaining>=10, mx, my, false)
            drawButton("+50", 469, btnY, 50, 26, THEME.btn_plus, myRemaining>=50, mx, my, false)
            drawButton("ALL", 526, btnY, 50, 26, THEME.btn_allin, myRemaining>0, mx, my, false)
        end
    end

    -- Overlay Module Interface Handler
    if HorseBetting.phase == "RESULT" then
        love.graphics.setColor(0,0,0,0.7)
        love.graphics.rectangle("fill", 0, 0, W, H)
        for _, p in ipairs(celebrationParticles) do
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], p.life)
            love.graphics.circle("fill", p.x, p.y, 4)
        end
        local pw, ph = 420, 310
        local px, py = cx-pw/2, cy-ph/2
        love.graphics.setColor(THEME.panel)
        love.graphics.rectangle("fill", px, py, pw, ph, 12)
        love.graphics.setColor(THEME.panel_border)
        love.graphics.rectangle("line", px, py, pw, ph, 12)
        
        love.graphics.setColor(THEME.text_gold)
        love.graphics.setFont(getFont(24))
        love.graphics.printf("RACE FINISHED", px, py+24, pw, "center")
        
        local winner = HorseBetting.horses[HorseBetting.winningHorseIdx]
        if winner then
            love.graphics.setColor(winner.color)
            love.graphics.circle("fill", cx, py+95, 24)
            love.graphics.setColor(THEME.text_white)
            love.graphics.setFont(getFont(14))
            love.graphics.printf(winner.name, px, py+135, pw, "center")
            love.graphics.setColor(THEME.text_gold)
            love.graphics.setFont(getFont(12))
            love.graphics.printf(string.format("Payout Multiplier: %.1fx", winner.odds), px, py+158, pw, "center")
        end

        local myP = GameLogic.players[GameLogic.myPlayerIdx]
        local payout = myP and myP.roundPayout or 0
        local payoutColor = payout>0 and THEME.text_green or (payout<0 and {1,0.4,0.4,1} or THEME.text_muted)
        love.graphics.setColor(payoutColor)
        love.graphics.setFont(getFont(18))
        love.graphics.printf(payout>0 and ("YOU WON $"..payout) or (payout<0 and ("LOSS $"..math.abs(payout)) or "NO CHANGE"), px, py+195, pw, "center")

        local nextBtn = (GameLogic.mode=="HOST" or GameLogic.mode=="OFFLINE") and "NEXT RACE" or "WAITING FOR HOST..."
        drawButton(nextBtn, cx-90, py+ph-55, 180, 38, THEME.btn_lock, (GameLogic.mode=="HOST" or GameLogic.mode=="OFFLINE"), mx, my, false)
    end
end

-- ----------------------------------------------------------------------------
-- Mouse handling
-- ----------------------------------------------------------------------------
function HorseBetting.mousepressed(x, y, button)
    if button ~= 1 then return end

    if HorseBetting.phase == "BETTING" then
        local myP = GameLogic.players[GameLogic.myPlayerIdx]
        if not myP then return end
        local W, H = _G.getW(), _G.getH()
        
        local trackY = 65
        local trackH = 160
        local panelY = trackY + trackH + 15
        local panelH = H - panelY - 15
        local rowH = (panelH - 35) / 5
        local startY = panelY + 28
        
        for i=1,5 do
            local ry = startY + (i-1)*rowH
            local btnY = ry + (rowH - 26)/2
            local btnH = 26
            local btnW = 50

            -- Minus 50
            if x >= 355 and x <= 355 + btnW and y >= btnY and y <= btnY + btnH then
                if GameLogic.mode == "GUEST" then
                    local newBet = getBet(myP.bets,i)-50
                    if newBet<0 then newBet=0 end
                    require("network").sendGameMessage("host", {action="HORSE_BET", horseIdx=i, amount=newBet})
                else adjustBet(GameLogic.myPlayerIdx, i, -50) end
                return
            -- Plus 10
            elseif x >= 412 and x <= 412 + btnW and y >= btnY and y <= btnY + btnH then
                if GameLogic.mode == "GUEST" then
                    local newBet = getBet(myP.bets,i)+10
                    require("network").sendGameMessage("host", {action="HORSE_BET", horseIdx=i, amount=newBet})
                else adjustBet(GameLogic.myPlayerIdx, i, 10) end
                return
            -- Plus 50
            elseif x >= 469 and x <= 469 + btnW and y >= btnY and y <= btnY + btnH then
                if GameLogic.mode == "GUEST" then
                    local newBet = getBet(myP.bets,i)+50
                    require("network").sendGameMessage("host", {action="HORSE_BET", horseIdx=i, amount=newBet})
                else adjustBet(GameLogic.myPlayerIdx, i, 50) end
                return
            -- All In
            elseif x >= 526 and x <= 526 + btnW and y >= btnY and y <= btnY + btnH then
                if GameLogic.mode == "GUEST" then
                    require("network").sendGameMessage("host", {action="HORSE_ALL_IN", horseIdx=i})
                else allIn(GameLogic.myPlayerIdx, i) end
                return
            end
        end
    end

    -- Result overlay action validation bounds 
    if HorseBetting.phase == "RESULT" and (GameLogic.mode=="HOST" or GameLogic.mode=="OFFLINE") then
        local cx, cy = _G.getW()/2, _G.getH()/2
        local ph = 310
        local py = cy - ph/2
        local btnX = cx-90
        local btnY = py+ph-55
        if x>=btnX and x<=btnX+180 and y>=btnY and y<=btnY+38 then
            if GameLogic.roundNum >= (GameLogic.totalRounds or 5) then
                GameLogic.phase = "MATCH_OVER"
                GameLogic.syncState()
            else
                GameLogic.roundNum = GameLogic.roundNum + 1
                HorseBetting.startRound()
            end
            return
        end
    end
end

function HorseBetting.keypressed(key)
    if key == "space" and (GameLogic.mode=="HOST" or GameLogic.mode=="OFFLINE") then
        if HorseBetting.phase == "BETTING" then
            startRace()
        elseif HorseBetting.phase == "RESULT" then
            if GameLogic.roundNum >= (GameLogic.totalRounds or 5) then
                GameLogic.phase = "MATCH_OVER"
                GameLogic.syncState()
            else
                GameLogic.roundNum = GameLogic.roundNum + 1
                HorseBetting.startRound()
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Network state sync
-- ----------------------------------------------------------------------------
function HorseBetting.getStateExt(state)
    state.hb_phase = HorseBetting.phase
    state.hb_horses = HorseBetting.horses
    state.hb_raceSeed = HorseBetting.raceSeed
    state.hb_elapsedTime = HorseBetting.elapsedTime
    state.hb_podium = HorseBetting.podium
    state.hb_winningHorseIdx = HorseBetting.winningHorseIdx
    state.hb_bettingTimer = bettingTimer
end

function HorseBetting.applyStateExt(state)
    HorseBetting.phase = state.hb_phase or "BETTING"
    HorseBetting.horses = state.hb_horses or {}
    HorseBetting.raceSeed = state.hb_raceSeed or 0
    HorseBetting.elapsedTime = state.hb_elapsedTime or 0
    HorseBetting.podium = state.hb_podium or {}
    HorseBetting.winningHorseIdx = state.hb_winningHorseIdx
    bettingTimer = state.hb_bettingTimer or 20
    if HorseBetting.phase == "RACING" and not HorseBetting.racePRNG then
        HorseBetting.racePRNG = PRNG.new(HorseBetting.raceSeed)
    end
end

function HorseBetting.getPlayerStateExt(p, pSafe)
    pSafe.chips = p.chips
    pSafe.bets = p.bets or {0,0,0,0,0}
    pSafe.roundPayout = p.roundPayout or 0
end

function HorseBetting.applyPlayerStateExt(pSafe, p)
    p.chips = pSafe.chips or 0
    p.bets = pSafe.bets or {0,0,0,0,0}
    p.roundPayout = pSafe.roundPayout or 0
end

function HorseBetting.handleNetworkMessage(evt)
    local p = nil
    for idx=1,4 do
        if GameLogic.players[idx] and GameLogic.players[idx].id == evt.clientId then
            p = GameLogic.players[idx]
            break
        end
    end
    if not p then return false end
    if not p.chips then p.chips = 1000 end
    if not p.bets then p.bets = {0,0,0,0,0} end

    if evt.data.action == "HORSE_BET" then
        local horseIdx = evt.data.horseIdx
        local amount = evt.data.amount
        if horseIdx>=1 and horseIdx<=5 and amount>=0 then
            local otherTotal = 0
            for i=1,5 do if i~=horseIdx then otherTotal = otherTotal + getBet(p.bets, i) end end
            if otherTotal + amount <= p.chips then
                setBet(p.bets, horseIdx, amount)
                GameLogic.syncState()
            end
        end
        return true
    elseif evt.data.action == "HORSE_ALL_IN" then
        local horseIdx = evt.data.horseIdx
        for idx=1,4 do
            if GameLogic.players[idx] and GameLogic.players[idx].id == evt.clientId then
                allIn(idx, horseIdx)
                break
            end
        end
        GameLogic.syncState()
        return true
    end
    return false
end

return HorseBetting