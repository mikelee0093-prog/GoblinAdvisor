-- Goblin Advisor: RecipeManager
-- Records recipes and their reagents while a profession window is open.
--
-- Account-wide recipe data lives in ns.db.recipes[recipeID]:
--   { name, prof, out (output itemID or nil), qmin, qmax, reagents = { {qty, ids = {itemID,...}}, ... } }
-- "ids" lists every quality tier of one reagent slot; any tier satisfies the slot.
-- Which recipes the CURRENT character knows lives in character.known[profName][recipeID] = true.
--
-- UNVERIFIED on WoW Forever: this client's docs do not list a recipe-list function or the
-- recipe structure fields, so everything here is guarded. /ga recipes shows what worked.
local _, ns = ...

local RM = {}
ns.RecipeManager = RM

local BATCH = 40          -- recipes read per frame, so a big profession never freezes the game
local DEBOUNCE = 1.5      -- list-update events fire in bursts; wait for them to settle

RM.scanning = false
RM.revision = 0           -- bumps whenever recorded recipes change
RM.lastResult = nil       -- { prof, recorded, known, via, time } from the last finished scan
RM.lastProblem = nil      -- plain-language reason the last scan could not run

local function Problem(text)
	RM.lastProblem = text
	ns.Debug("recipes:", text)
end

-- Name of the profession whose window is open, or nil.
local function OpenProfessionName()
	local TS = C_TradeSkillUI
	if not (TS and TS.GetBaseProfessionInfo) then return nil end
	local ok, info = pcall(TS.GetBaseProfessionInfo)
	if not ok or type(info) ~= "table" then return nil end
	local name = ns.Safe(info.professionName)
	if type(name) ~= "string" or name == "" then return nil end
	return name, info
end

-- Try each known way of listing every recipe of the open profession.
local function ListRecipeIDs()
	local TS = C_TradeSkillUI
	if not TS then return nil, "C_TradeSkillUI is missing" end
	for _, fname in ipairs({ "GetAllRecipeIDs", "GetFilteredRecipeIDs" }) do
		local fn = TS[fname]
		if fn then
			local ok, ids = pcall(fn)
			if ok and type(ids) == "table" and #ids > 0 then return ids, fname end
		end
	end
	return nil, "this client has no usable recipe-list function (tried GetAllRecipeIDs, GetFilteredRecipeIDs)"
end

local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1

-- Read one recipe. Returns the stored table and whether the character knows it, or nil.
local function ReadRecipe(rid, profName)
	local TS = C_TradeSkillUI
	local okI, info = pcall(TS.GetRecipeInfo, rid)
	if not okI or type(info) ~= "table" then return nil end
	local okS, schem = pcall(TS.GetRecipeSchematic, rid, false)
	if not okS or type(schem) ~= "table" then return nil end

	local name = ns.Safe(info.name)
	if type(name) ~= "string" then return nil end

	local reagents = {}
	for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
		if slot.reagentType == nil or slot.reagentType == BASIC then
			local ids = {}
			for _, r in ipairs(slot.reagents or {}) do
				if type(r.itemID) == "number" then ids[#ids + 1] = r.itemID end
			end
			if #ids > 0 then
				reagents[#reagents + 1] = { qty = tonumber(slot.quantityRequired) or 1, ids = ids }
			end
		end
	end

	local rec = {
		name = name,
		prof = profName,
		out = type(schem.outputItemID) == "number" and schem.outputItemID or nil,
		qmin = tonumber(schem.quantityMin) or 1,
		qmax = tonumber(schem.quantityMax) or 1,
		reagents = reagents,
		-- profession skill needed before the recipe can be learned (UNVERIFIED field name; nil if absent)
		req = tonumber(ns.Safe(info.unlockedRecipeLevel)),
	}
	return rec, info.learned and true or false
end

local function IsViewingSomeoneElse()
	local TS = C_TradeSkillUI
	for _, fname in ipairs({ "IsNPCCrafting", "IsTradeSkillLinked", "IsTradeSkillGuild" }) do
		local fn = TS and TS[fname]
		if fn then
			local ok, res = pcall(fn)
			if ok and res then return true end
		end
	end
	return false
end

-- Scan the profession window that is currently open.
function RM.Scan(reason)
	if RM.scanning or not ns.db then return end
	local TS = C_TradeSkillUI
	if not TS then return Problem("C_TradeSkillUI is missing on this client") end
	if IsViewingSomeoneElse() then return Problem("window shows another player's or an NPC's recipes; not recorded") end

	local profName = OpenProfessionName()
	if not profName then return Problem("could not read which profession is open") end
	local ids, via = ListRecipeIDs()
	if not ids then return Problem(via) end

	local charKey = ns.CharacterManager.currentKey
	local char = charKey and ns.db.characters[charKey]
	local knownSet = {}
	local recorded, known, i, n = 0, 0, 0, #ids
	RM.scanning = true
	RM.lastProblem = nil

	local function finish()
		RM.scanning = false
		RM.revision = RM.revision + 1
		if char then
			char.known = char.known or {}
			char.known[profName] = knownSet
		end
		local firstTime = not (RM.lastResult and RM.lastResult.prof == profName)
		RM.lastResult = { prof = profName, recorded = recorded, known = known, via = via, time = (GetServerTime and GetServerTime()) or (time and time()) or 0 }
		ns.Debug(("recipes: %s recorded=%d known=%d via=%s reason=%s"):format(profName, recorded, known, tostring(via), tostring(reason)))
		if firstTime then
			ns.Print(("recorded %d %s recipes (%d known)."):format(recorded, profName, known))
		end
		ns.UI.RefreshIfShown()
	end

	local function step()
		local stop = math.min(i + BATCH, n)
		for j = i + 1, stop do
			local ok, rec, learned = pcall(ReadRecipe, ids[j], profName)
			if ok and rec then
				ns.db.recipes[ids[j]] = rec
				recorded = recorded + 1
				if learned then knownSet[ids[j]] = true; known = known + 1 end
			elseif not ok then
				ns.Debug("recipes: read failed for", tostring(ids[j]), tostring(rec))
			end
		end
		i = stop
		if i < n then C_Timer.After(0, step) else finish() end
	end
	step()
end

-- Debounced entry point for the noisy trade skill events.
local token = 0
function RM.QueueScan(reason)
	token = token + 1
	local mine = token
	C_Timer.After(DEBOUNCE, function()
		if mine == token then ns.Try("recipe scan", RM.Scan, reason) end
	end)
end

-- A recipe learned while the window is closed: record just that one.
function RM.RecordSingle(recipeID)
	local TS = C_TradeSkillUI
	if not (ns.db and TS and TS.GetProfessionInfoByRecipeID and type(recipeID) == "number") then return end
	local ok, pinfo = pcall(TS.GetProfessionInfoByRecipeID, recipeID)
	local profName = ok and type(pinfo) == "table" and ns.Safe(pinfo.professionName)
	if type(profName) ~= "string" or profName == "" then return end
	local rec, learned = ReadRecipe(recipeID, profName)
	if not rec then return end
	ns.db.recipes[recipeID] = rec
	RM.revision = RM.revision + 1
	local char = ns.CharacterManager.GetCurrent()
	if char and learned then
		char.known = char.known or {}
		char.known[profName] = char.known[profName] or {}
		char.known[profName][recipeID] = true
	end
	ns.Debug("recipes: learned and recorded", rec.name)
end

---------------------------------------------------------------- helpers for the UI
function RM.Count()
	local n = 0
	for _ in pairs(ns.db.recipes) do n = n + 1 end
	return n
end

RM.nameRequested = {}     -- items whose names we already asked the client to load

-- Item name if the client has it cached, otherwise a placeholder. The load request is sent
-- once per item, so redrawing a window can never start a request loop.
function RM.ItemName(itemID)
	local name
	if C_Item and C_Item.GetItemNameByID then
		local ok, res = pcall(C_Item.GetItemNameByID, itemID)
		if ok then name = ns.Safe(res) end
	end
	if not name and C_Item and C_Item.RequestLoadItemDataByID and not RM.nameRequested[itemID] then
		RM.nameRequested[itemID] = true
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	return name or ("item " .. tostring(itemID))
end

function RM.PrintStatus()
	ns.Print("recipe data:")
	local TS = C_TradeSkillUI
	print("  C_TradeSkillUI: " .. (TS and "present" or "MISSING"))
	for _, f in ipairs({ "GetBaseProfessionInfo", "GetRecipeInfo", "GetRecipeSchematic", "GetAllRecipeIDs", "GetFilteredRecipeIDs", "IsTradeSkillLinked" }) do
		print(("  %s: %s"):format(f, (TS and TS[f]) and "yes" or "no"))
	end
	print("  recipes stored: " .. RM.Count())
	local r = RM.lastResult
	if r then
		print(("  last scan: %s, %d recipes (%d known) via %s"):format(r.prof, r.recorded, r.known, tostring(r.via)))
	else
		print("  last scan: none yet. Open a profession window in game.")
	end
	if RM.lastProblem then print("  last problem: " .. RM.lastProblem) end
end

function RM.Clear()
	ns.db.recipes = {}
	for _, c in pairs(ns.db.characters) do c.known = nil end
	RM.lastResult = nil
	RM.revision = RM.revision + 1
end
