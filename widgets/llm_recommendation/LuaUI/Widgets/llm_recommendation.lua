--[[
    Beyond All Reason Game Widget
    --------------------------------------
    This widget is designed for the Beyond All Reason (BAR) game. It dumps current game information to a JSON file every N seconds and displays current LLM recommendation.
--]]

local widgetName = "LLM Recommendation"
local widgetDesc = "Dumps current game state to JSON every N seconds and displays current LLM recommendation."
local widgetVersion = "0.1"
local widgetHandler = true
-- Include necessary Spring API functions
local gl = gl
local Spring = Spring
local widgetHandler = widgetHandler
local VFS = VFS
local fontfile = "fonts/" .. Spring.GetConfigString("bar_font", "Exo2-SemiBold.otf")
local font
local UnitDefs = UnitDefs
local WeaponDefs = WeaponDefs

-- Variables for display
local vsx, vsy = Spring.GetViewGeometry()
local energyText = "Energy Generation: 0/s"
local recommendationText = "LLM: <none>"
local fontSize = 16
local bgPadding = 4
local textColor = {1, 1, 0, 1} -- Yellow for energy
local bgColor = {0, 0, 0, 0.6} -- Semi-transparent black background
local xPos, yPos -- Will be calculated in Initialize and ViewResize

-- Variables for JSON logging
local outputDir = "luaui"
local outputFile = "luaui/game_state.json"
local recommendationPath = "luaui/recommendation.json"
local startFrame = 0
local lastWriteGameTime = 0 -- Track last write time in seconds

-- Function to wrap text to fit within a given width
local function wrapText(text, maxWidth, font, fontSize)
    local lines = {}
    local currentLine = ""
    for word in text:gmatch("%S+") do
        local testLine = currentLine == "" and word or (currentLine .. " " .. word)
        local testWidth = font:GetTextWidth(testLine) * fontSize
        if testWidth > maxWidth and currentLine ~= "" then
            table.insert(lines, currentLine)
            currentLine = word
        else
            currentLine = testLine
        end
    end
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    return lines
end

-- Simple JSON serialization for multiple key-value pairs
local function toJson(data, gameTime)
    local minutes = math.floor(gameTime / 60)
    local seconds = math.floor(gameTime % 60)
    local gameTimeStr = string.format("%02d:%02d", minutes, seconds)
    return string.format(
        '{"game_time": %.1f, "game_time_str": "%s", "energy_generation": %.1f, "energy_consumption": %.1f, "energy_capacity": %.1f, "energy": %.1f, "metal_generation": %.1f, "metal_consumption": %.1f, "metal": %.1f}',
        gameTime, gameTimeStr, data.energy_generation, data.energy_consumption, data.energy_capacity, data.energy, data.metal_generation, data.metal_consumption, data.metal
    )
end

function widget:GetInfo()
    return {
        name      = widgetName,
        desc      = widgetDesc,
        author    = "[cls]format37",
        date      = "2025-05-18",
        license   = "Public Domain",
        layer     = 0,
        enabled   = true
    }
end

function widget:Initialize()
    font = gl.LoadFont(fontfile, fontSize, 0, 0)
    -- Ensure the output directory exists
    Spring.CreateDir(outputDir)
    -- Initial position calculation
    UpdatePosition()
    startFrame = Spring.GetGameFrame() or 0
end

function widget:Shutdown()
    gl.DeleteFont(font)
end

function UpdatePosition()
    -- Calculate max width for recommendation (30% of screen)
    local maxTextWidth = vsx * 0.3
    -- Wrap the recommendation text
    local wrappedLines = wrapText(recommendationText, maxTextWidth, font, fontSize)
    -- Calculate the widest line for background sizing
    local widest = 0
    for _, line in ipairs(wrappedLines) do
        local w = font:GetTextWidth(line) * fontSize
        if w > widest then widest = w end
    end
    local textHeight = fontSize * 1.2 * #wrappedLines
    -- Left-align the text
    xPos = bgPadding
    yPos = (vsy - textHeight) / 2
end

function widget:ViewResize(viewSizeX, viewSizeY)
    vsx, vsy = viewSizeX, viewSizeY
    UpdatePosition()
end

function widget:GameFrame(n)
    -- Read recommendation from file every frame (or optimize to every N frames if needed)
    local file = io.open(recommendationPath, "r")
    if file then
        local contents = file:read("*a")
        file:close()
        local rec = contents and contents:match('"recommendation"%s*:%s*"(.-)"')
        if rec then
            recommendationText = "LLM: " .. rec
        else
            recommendationText = "<invalid recommendation.json>"
        end
    else
        recommendationText = "<could not read recommendation.json>"
    end
    UpdatePosition() -- Recalculate position as text width may change

    -- Get current team's energy and metal stats
    local teamID = Spring.GetMyTeamID()
    local energy, energyStorage, energyPull, energyIncome, energyExpense = Spring.GetTeamResources(teamID, "energy")
    local metal, metalStorage, metalPull, metalIncome, metalExpense = Spring.GetTeamResources(teamID, "metal")
    energyText = string.format("Energy Generation: %.1f/s", energyIncome or 0)

    -- Count specific buildings (completed only)
    local unitCounts = {
        wind = 0,
        solar = 0,
        advsolar = 0,
        energystorage = 0,
        advenergystorage = 0,
        metalstorage = 0,
        advmetalstorage = 0,
        fusion = 0,
        advfusion = 0,
        geo = 0,
        advgeo = 0,
        nano = 0,
        convertor = 0,
        advconvertor = 0,
        -- Add mex and advmex
        mex = 0,
        advmex = 0,
    }
    -- NEW: counts of buildings currently being constructed (build progress < 100%)
    local unitInProgressCounts = {
        wind = 0,
        solar = 0,
        advsolar = 0,
        energystorage = 0,
        advenergystorage = 0,
        metalstorage = 0,
        advmetalstorage = 0,
        fusion = 0,
        advfusion = 0,
        geo = 0,
        advgeo = 0,
        nano = 0,
        convertor = 0,
        advconvertor = 0,
        -- Add mex and advmex
        mex = 0,
        advmex = 0,
    }
    -- NEW: track overall build progress fraction sums
    local totalBuildProgressFraction = 0
    local totalBuildsInProgress = 0
    -- NEW: capture per-building progress for detailed JSON section
    local buildingProgressList = {}
    local teamUnits = Spring.GetTeamUnits and Spring.GetTeamUnits(teamID) or {}
    for _, unitID in ipairs(teamUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local def = unitDefID and UnitDefs and UnitDefs[unitDefID]
        if def then
            local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
            if buildProgress == 1 then
                local name = def.name
                if name == "armwin" or name == "corwin" then unitCounts.wind = unitCounts.wind + 1 end
                if name == "armsolar" or name == "corsolar" then unitCounts.solar = unitCounts.solar + 1 end
                if name == "armadvsol" or name == "coradvsol" then unitCounts.advsolar = unitCounts.advsolar + 1 end
                if name == "armestor" or name == "corestor" then unitCounts.energystorage = unitCounts.energystorage + 1 end
                if name == "armuwadves" or name == "coruwadves" then unitCounts.advenergystorage = unitCounts.advenergystorage + 1 end
                if name == "armmstor" or name == "cormstor" then unitCounts.metalstorage = unitCounts.metalstorage + 1 end
                if name == "armuwadvms" or name == "coruwadvms" then unitCounts.advmetalstorage = unitCounts.advmetalstorage + 1 end
                if name == "armfus" or name == "corfus" then unitCounts.fusion = unitCounts.fusion + 1 end
                if name == "armafus" or name == "corafus" then unitCounts.advfusion = unitCounts.advfusion + 1 end
                if name == "armgeo" or name == "corgeo" then unitCounts.geo = unitCounts.geo + 1 end
                if name == "armageo" or name == "corageo" then unitCounts.advgeo = unitCounts.advgeo + 1 end
                if name == "armnanotc" or name == "cornanotc" then unitCounts.nano = unitCounts.nano + 1 end
                if name == "armmmkr" or name == "cormmkr" then unitCounts.convertor = unitCounts.convertor + 1 end
                if name == "armfmkr" or name == "corfmkr" then unitCounts.advconvertor = unitCounts.advconvertor + 1 end
                -- Add mex and advmex
                if name == "armmex" or name == "cormex" then unitCounts.mex = unitCounts.mex + 1 end
                if name == "armmoho" or name == "cormoho" then unitCounts.advmex = unitCounts.advmex + 1 end
            elseif buildProgress and buildProgress > 0 then -- NEW: unit still being built
                local name = def.name
                local alias = nil
                -- Map unit def names to generic aliases used in JSON
                if name == "armwin" or name == "corwin" then
                    alias = "wind"
                    unitInProgressCounts.wind = unitInProgressCounts.wind + 1
                elseif name == "armsolar" or name == "corsolar" then
                    alias = "solar"
                    unitInProgressCounts.solar = unitInProgressCounts.solar + 1
                elseif name == "armadvsol" or name == "coradvsol" then
                    alias = "advsolar"
                    unitInProgressCounts.advsolar = unitInProgressCounts.advsolar + 1
                elseif name == "armestor" or name == "corestor" then
                    alias = "energystorage"
                    unitInProgressCounts.energystorage = unitInProgressCounts.energystorage + 1
                elseif name == "armuwadves" or name == "coruwadves" then
                    alias = "advenergystorage"
                    unitInProgressCounts.advenergystorage = unitInProgressCounts.advenergystorage + 1
                elseif name == "armmstor" or name == "cormstor" then
                    alias = "metalstorage"
                    unitInProgressCounts.metalstorage = unitInProgressCounts.metalstorage + 1
                elseif name == "armuwadvms" or name == "coruwadvms" then
                    alias = "advmetalstorage"
                    unitInProgressCounts.advmetalstorage = unitInProgressCounts.advmetalstorage + 1
                elseif name == "armfus" or name == "corfus" then
                    alias = "fusion"
                    unitInProgressCounts.fusion = unitInProgressCounts.fusion + 1
                elseif name == "armafus" or name == "corafus" then
                    alias = "advfusion"
                    unitInProgressCounts.advfusion = unitInProgressCounts.advfusion + 1
                elseif name == "armgeo" or name == "corgeo" then
                    alias = "geo"
                    unitInProgressCounts.geo = unitInProgressCounts.geo + 1
                elseif name == "armageo" or name == "corageo" then
                    alias = "advgeo"
                    unitInProgressCounts.advgeo = unitInProgressCounts.advgeo + 1
                elseif name == "armnanotc" or name == "cornanotc" then
                    alias = "nano"
                    unitInProgressCounts.nano = unitInProgressCounts.nano + 1
                elseif name == "armmmkr" or name == "cormmkr" then
                    alias = "convertor"
                    unitInProgressCounts.convertor = unitInProgressCounts.convertor + 1
                elseif name == "armfmkr" or name == "corfmkr" then
                    alias = "advconvertor"
                    unitInProgressCounts.advconvertor = unitInProgressCounts.advconvertor + 1
                -- Add mex and advmex
                elseif name == "armmex" or name == "cormex" then
                    alias = "mex"
                    unitInProgressCounts.mex = unitInProgressCounts.mex + 1
                elseif name == "armmoho" or name == "cormoho" then
                    alias = "advmex"
                    unitInProgressCounts.advmex = unitInProgressCounts.advmex + 1
                end

                -- Append to per-building progress list if we found an alias
                if alias then
                    table.insert(buildingProgressList, string.format('["%s","%.1f%%"]', alias, (buildProgress or 0)*100))
                end
                -- track build completion progress
                totalBuildProgressFraction = totalBuildProgressFraction + (buildProgress or 0)
                totalBuildsInProgress = totalBuildsInProgress + 1
            end
        end
    end

    -- Count attacking units, their total DPS and HP
    local attackingUnitCount = 0
    local totalAttackerDPS = 0
    local totalAttackerHP = 0
    for _, unitID in ipairs(teamUnits) do
        local unitDefID = Spring.GetUnitDefID(unitID)
        local def = unitDefID and UnitDefs and UnitDefs[unitDefID]
        if def then
            local _, _, _, _, buildProgress = Spring.GetUnitHealth(unitID)
            if buildProgress == 1 then
                if def.weapons and #def.weapons > 0 then
                    attackingUnitCount = attackingUnitCount + 1
                    -- Sum DPS for all weapons using WeaponDefs
                    local unitDPS = 0
                    for _, weapon in ipairs(def.weapons or {}) do
                        if weapon.weaponDef then
                            local wdef = WeaponDefs[weapon.weaponDef]
                            if wdef and wdef.damages and wdef.damages[0] and wdef.reload and wdef.reload > 0 then
                                unitDPS = unitDPS + (wdef.damages[0] / wdef.reload)
                            end
                        end
                    end
                    totalAttackerDPS = totalAttackerDPS + unitDPS
                    -- Sum HP
                    totalAttackerHP = totalAttackerHP + (def.health or def.maxHealth or 0)
                end
            end
        end
    end

    -- Log to JSON every 10 seconds using game_time
    local gameTime = (n or 0) / 30
    if (gameTime - lastWriteGameTime) >= 30 then
        -- Build extra JSON fields for nonzero counts
        local extra = ""
        for k, v in pairs(unitCounts) do
            if v > 0 then
                extra = extra .. string.format(', "%s": %d', k, v)
            end
        end
        -- NEW: append detailed buildings in progress section
        if #buildingProgressList > 0 then
            extra = extra .. string.format(', "buildings_in_progress": [%s]', table.concat(buildingProgressList, ","))
        end
        -- Add attacking unit stats to JSON
        extra = extra .. string.format(', "attacking_unit_count": %d, "attacking_unit_dps": %.1f, "attacking_unit_hp": %.1f', attackingUnitCount, totalAttackerDPS, totalAttackerHP)
        local jsonData = string.format(
            '{"game_time": %.1f, "game_time_str": "%s", "energy_generation": %.1f, "energy_consumption": %.1f, "energy_capacity": %.1f, "energy": %.1f, "metal_generation": %.1f, "metal_consumption": %.1f, "metal": %.1f%s}',
            gameTime, string.format("%02d:%02d", math.floor(gameTime / 60), math.floor(gameTime % 60)),
            energyIncome or 0, energyExpense or 0, energyStorage or 0, energy or 0, metalIncome or 0, metalExpense or 0, metal or 0, extra
        )
        -- Log to console as a fallback
        Spring.Echo("Game state JSON: " .. jsonData)
        -- Attempt to write to file safely
        local success, err = pcall(function()
            local file = io.open(outputFile, "w")
            if file then
                file:write(jsonData)
                file:close()
            else
                Spring.Echo("Failed to open file for writing: " .. outputFile)
            end
        end)
        if not success then
            Spring.Echo("Error writing to file: " .. tostring(err))
        end
        lastWriteGameTime = gameTime -- Update last write time
    end
end

function widget:DrawScreen()
    -- Calculate max width for recommendation (30% of screen)
    local maxTextWidth = vsx * 0.3
    -- Wrap the recommendation text
    local wrappedLines = wrapText(recommendationText, maxTextWidth, font, fontSize)
    -- Calculate the widest line for background sizing
    local widest = 0
    for _, line in ipairs(wrappedLines) do
        local w = font:GetTextWidth(line) * fontSize
        if w > widest then widest = w end
    end
    local textHeight = fontSize * 1.2 * #wrappedLines
    -- Draw background rectangle
    gl.Color(bgColor)
    gl.Rect(xPos - bgPadding, yPos - bgPadding, xPos + widest + bgPadding, yPos + textHeight + bgPadding)
    -- Draw each line
    gl.Color(textColor)
    font:Begin()
    for i, line in ipairs(wrappedLines) do
        font:Print(line, xPos, yPos + textHeight - i * fontSize * 1.2, fontSize, "o")
    end
    font:End()
end
