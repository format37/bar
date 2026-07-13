-- Economy Assist
--
-- Lower the build priority of builders working on energy producers or
-- energy-to-metal converters when the team's energy state calls for it.
-- This is intentionally a control widget: the BAR Builder Priority gadget
-- performs the resource gating for builders marked low priority.

local widget = widget

function widget:GetInfo()
	return {
		name    = "economy-assist",
		desc    = "Lowers energy and converter builder priority based on team economy",
		author  = "",
		version = "0.1",
		layer   = 0,
		enabled = false,
		control = true,
	}
end

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

local UPDATE_FRAMES    = 12
local MIN_DWELL_FRAMES = 15

-- The policy is driven only by BAR's aggregate converter state:
--   mmUse < mmCapacity  -> at least one converter is energy-starved
--   mmUse >= mmCapacity -> all available converters can run
-- A zero capacity or missing rules means that no reliable converter state is
-- available, so the widget leaves both categories at Normal.

local EXCLUDE_COMMANDER = false -- commanders participate in the same policy
local DEBUG = false

--------------------------------------------------------------------------------
-- Spring aliases
--------------------------------------------------------------------------------

local spGetMyTeamID          = Spring.GetMyTeamID
local spGetMyPlayerID        = Spring.GetMyPlayerID
local spGetSpectatingState   = Spring.GetSpectatingState
local spGetTeamUnits         = Spring.GetTeamUnits
local spGetTeamRulesParam    = Spring.GetTeamRulesParam
local spGetUnitDefID         = Spring.GetUnitDefID
local spGetUnitIsBuilding    = Spring.GetUnitIsBuilding
local spGetUnitCurrentCommand = Spring.GetUnitCurrentCommand
local spGetUnitRulesParam    = Spring.GetUnitRulesParam
local spGiveOrderToUnit      = Spring.GiveOrderToUnit
local spValidUnitID          = Spring.ValidUnitID

local CMD_GUARD = CMD and CMD.GUARD

-- The BAR gadget registers GameCMD.PRIORITY.  In LuaUI the same engine
-- command is normally exposed as CMD.PRIORITY; keep the GameCMD fallback for
-- builds that expose only that table.
local CMD_PRIORITY = (GameCMD and GameCMD.PRIORITY) or (CMD and CMD.PRIORITY)

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local myTeamID
local spectating = false

local isBuilder = {}       -- [unitDefID] = true for controllable constructors
local category = {}        -- [unitDefID] = "energy", "converter", or "other"

local builders = {}        -- [unitID] = true for our tracked builders
local throttled = {}       -- [unitID] = true only after this widget set Low

local economyMode = nil     -- "converter-starved", "converters-active", or nil
local lastModeChange = -999999

local function debugLog(message)
	if DEBUG then
		Spring.Echo("[economy-assist] " .. message)
	end
end

local function clearTable(tableToClear)
	for key in pairs(tableToClear) do
		tableToClear[key] = nil
	end
end

--------------------------------------------------------------------------------
-- Unit classification
--------------------------------------------------------------------------------

local fallbackConverters = {
	armmakr       = true,
	cormakr       = true,
	legeconv      = true,
	legadveconv   = true,
	legfeconv     = true,
	leganavaleconv = true,
	legadveconvt3 = true,
}

local function lower(value)
	return string.lower(tostring(value or ""))
end

local function isCommanderDef(unitDef)
	local customParams = unitDef.customParams or {}
	local commanderFlag = customParams.iscommander
	local name = lower(unitDef.name)

	if commanderFlag == true or commanderFlag == "true" or tonumber(commanderFlag) == 1 then
		return true
	end

	-- BAR's commander definitions use these names, including evolved and
	-- faction-specific commander variants.
	if name == "armcom" or name == "corcom" or name == "legcom" or name == "scavcom" then
		return true
	end
	if name:match("^armcomlvl%d+$") or name:match("^corcomlvl%d+$") or name:match("^legcomlvl%d+$") then
		return true
	end
	if name == "armcomnew" or name == "armcomcon" or name == "corcomcon" then
		return true
	end
	if name:match("^legcomt2") or name:match("^legcomoff") or name:match("^legcomecon") then
		return true
	end

	return false
end

local function isConverterDef(unitDef)
	local customParams = unitDef.customParams or {}
	local capacity = customParams.energyconv_capacity
	local efficiency = customParams.energyconv_efficiency

	-- This is the authoritative BAR converter marker used by
	-- game_energy_conversion.lua.
	if capacity ~= nil and efficiency ~= nil then
		return true
	end

	return fallbackConverters[lower(unitDef.name)] == true
end

local function positive(value)
	if value == true then
		return true
	end
	return (tonumber(value) or 0) > 0
end

local function isEnergyDef(unitDef)
	local customParams = unitDef.customParams or {}

	if positive(unitDef.energyMake)
		or positive(unitDef.windGenerator)
		or positive(unitDef.tidal)
		or (tonumber(unitDef.energyUpkeep) or 0) < 0 then
		return true
	end

	-- These cover common mod/unit-definition spellings without making the
	-- normal BAR customParams path a requirement.
	local customEnergy = customParams.energy_income
		or customParams.energyincome
		or customParams.energy_make
		or customParams.energyMake
	return positive(customEnergy)
end

local function buildTables()
	clearTable(isBuilder)
	clearTable(category)

	for unitDefID, unitDef in pairs(UnitDefs) do
		local commander = EXCLUDE_COMMANDER and isCommanderDef(unitDef)
		isBuilder[unitDefID] = (unitDef.isBuilder and not unitDef.isFactory and not commander) or false

		-- Converters must be checked first: some definitions also expose an
		-- energy-related field and must still be classified as converters.
		category[unitDefID] = isConverterDef(unitDef) and "converter"
			or isEnergyDef(unitDef) and "energy"
			or "other"
	end
end

local function addBuilder(unitID, unitDefID, teamID)
	if spectating or teamID ~= myTeamID then
		return
	end

	unitDefID = unitDefID or spGetUnitDefID(unitID)
	if isBuilder[unitDefID] then
		builders[unitID] = true
	end
end

--------------------------------------------------------------------------------
-- Work resolution
--------------------------------------------------------------------------------

local function resolveWorkCategory(unitID, depth)
	depth = depth or 0
	if depth > 4 or not unitID then
		return "other"
	end
	if spValidUnitID and not spValidUnitID(unitID) then
		return "other"
	end

	local builtID = spGetUnitIsBuilding(unitID)
	if not builtID then
		local commandID, _, _, parameter1 = spGetUnitCurrentCommand(unitID)
		if commandID == CMD_GUARD and parameter1 then
			return resolveWorkCategory(parameter1, depth + 1)
		end
		return "idle"
	end

	return category[spGetUnitDefID(builtID)] or "other"
end

--------------------------------------------------------------------------------
-- Priority control
--------------------------------------------------------------------------------

-- Current BAR uses the builderPriority rules parameter.  The older spelling
-- is retained for compatibility with builds that used buildpriority.
local function readPriority(unitID)
	if not spGetUnitRulesParam then
		return nil
	end
	return spGetUnitRulesParam(unitID, "builderPriority")
		or spGetUnitRulesParam(unitID, "buildpriority")
end

-- BAR's Builder Priority gadget handles this as an absolute set: 0 is Low;
-- 1 is the default/non-low mode.  It is not a toggle-cycle command.
local function setPriority(unitID, level)
	if not CMD_PRIORITY then
		return false
	end
	if spValidUnitID and not spValidUnitID(unitID) then
		return false
	end

	spGiveOrderToUnit(unitID, CMD_PRIORITY, {level}, 0)
	debugLog(string.format("unit %d priority -> %d (rules=%s)", unitID, level, tostring(readPriority(unitID))))
	return true
end

local function restoreUnit(unitID)
	if throttled[unitID] then
		setPriority(unitID, 1)
		throttled[unitID] = nil
	end
end

local function restoreAll()
	for unitID in pairs(throttled) do
		setPriority(unitID, 1)
		throttled[unitID] = nil
	end
end

local function removeUnit(unitID, restore)
	if restore then
		restoreUnit(unitID)
	else
		throttled[unitID] = nil
	end
	builders[unitID] = nil
end

local function applyBuilder(unitID)
	if spValidUnitID and not spValidUnitID(unitID) then
		builders[unitID] = nil
		throttled[unitID] = nil
		return
	end

	local workCategory = resolveWorkCategory(unitID)
	local shouldLow = (workCategory == "converter" and economyMode == "converter-starved")
		or (workCategory == "energy" and economyMode == "converters-active")

	if shouldLow then
		if not throttled[unitID] and setPriority(unitID, 0) then
			throttled[unitID] = true
		end
	elseif throttled[unitID] then
		restoreUnit(unitID)
	end
end

--------------------------------------------------------------------------------
-- Economy state
--------------------------------------------------------------------------------

local function updateStates(frame)
	local converterCapacity = tonumber(spGetTeamRulesParam(myTeamID, "mmCapacity"))
	local converterUse = tonumber(spGetTeamRulesParam(myTeamID, "mmUse"))
	local desiredMode

	if converterCapacity and converterUse and converterCapacity > 0 then
		if converterUse < converterCapacity then
			desiredMode = "converter-starved"
		else
			desiredMode = "converters-active"
		end
	end

	if desiredMode ~= economyMode and frame - lastModeChange >= MIN_DWELL_FRAMES then
		economyMode = desiredMode
		lastModeChange = frame
		debugLog(string.format(
			"mode -> %s (use %.3f, capacity %.3f)",
			desiredMode or "normal",
			converterUse or -1,
			converterCapacity or -1
		))
	end
end

--------------------------------------------------------------------------------
-- Ownership/context maintenance
--------------------------------------------------------------------------------

local function currentSpectatingState()
	local isSpec, fullView = spGetSpectatingState()
	return isSpec or fullView
end

local function seedBuilders()
	clearTable(builders)
	for _, unitID in ipairs(spGetTeamUnits(myTeamID) or {}) do
		addBuilder(unitID, spGetUnitDefID(unitID), myTeamID)
	end
end

local function refreshContext()
	local newSpectating = currentSpectatingState()
	local newTeamID = spGetMyTeamID()

	if newSpectating then
		if not spectating then
			restoreAll()
			clearTable(builders)
			economyMode = nil
			lastModeChange = -999999
		end
		spectating = true
		myTeamID = newTeamID
		return false
	end

	if spectating or myTeamID ~= newTeamID then
		restoreAll()
		clearTable(builders)
		economyMode = nil
		lastModeChange = -999999
		myTeamID = newTeamID
		spectating = false
		seedBuilders()
	end

	return myTeamID ~= nil
end

--------------------------------------------------------------------------------
-- Widget call-ins
--------------------------------------------------------------------------------

function widget:Initialize()
	if self.canControlUnits == false then
		Spring.Echo("[economy-assist] disabled: this game disallows unit-control widgets")
		return
	end
	if not CMD_PRIORITY then
		Spring.Echo("[economy-assist] disabled: CMD.PRIORITY is unavailable")
		return
	end

	buildTables()
	spectating = currentSpectatingState()
	myTeamID = spGetMyTeamID()
	if not spectating then
		seedBuilders()
	end

	debugLog("initialized")
end

function widget:GameFrame(frame)
	if frame % UPDATE_FRAMES ~= 0 then
		return
	end
	if not refreshContext() then
		return
	end

	updateStates(frame)
	for unitID in pairs(builders) do
		applyBuilder(unitID)
	end
end

function widget:PlayerChanged(playerID)
	if spGetMyPlayerID and playerID ~= spGetMyPlayerID() then
		return
	end
	refreshContext()
end

function widget:UnitCreated(unitID, unitDefID, unitTeam)
	addBuilder(unitID, unitDefID, unitTeam)
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	addBuilder(unitID, unitDefID, unitTeam)
end

function widget:UnitDestroyed(unitID)
	removeUnit(unitID, false)
end

function widget:UnitGiven(unitID, unitDefID, newTeamID)
	if newTeamID == myTeamID and not spectating then
		addBuilder(unitID, unitDefID, newTeamID)
	else
		removeUnit(unitID, true)
	end
end

function widget:UnitTaken(unitID, unitDefID, oldTeamID, newTeamID)
	if newTeamID == myTeamID and not spectating then
		addBuilder(unitID, unitDefID, newTeamID)
	else
		removeUnit(unitID, true)
	end
end

function widget:Shutdown()
	restoreAll()
	clearTable(builders)
end
