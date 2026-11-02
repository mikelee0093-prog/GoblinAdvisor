-- Goblin Advisor: GatheringAdvisor
-- Suggests which gatherable materials are worth collecting, from real scanned prices, for the
-- gathering professions the current character actually has. Advice only: it never moves,
-- targets or gathers for you.
--
-- NOT available (so never shown as if it were): zone-specific spawns, required skill levels,
-- demand and competition. The client does not provide them. They need an outside data source.
local _, ns = ...

local GA = {}
ns.GatheringAdvisor = GA

-- Profession name (English client) -> item subclass of the materials it gathers.
-- Subclass ids are looked up from the client's Enum first; the numbers are the Classic/Retail values.
GA.PROFESSIONS = {
	{ name = "Mining", enumKey = "MetalStone", fallback = 7 },
	{ name = "Herbalism", enumKey = "Herb", fallback = 9 },
	{ name = "Skinning", enumKey = "Leather", fallback = 6 },
}

local function TradeGoodsClass() return (Enum and Enum.ItemClass and Enum.ItemClass.Tradeskill) or 7 end

local function SubclassOf(def)
	return (Enum and Enum.ItemTradeGoodSubclass and Enum.ItemTradeGoodSubclass[def.enumKey]) or def.fallback
end

local classCache = {}
-- classID, subClassID for an item, or nil when the client does not know the item yet.
function GA.ItemClass(itemID)
	local c = classCache[itemID]
	if c then return c[1], c[2] end
	if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
	local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
	if ok and type(classID) == "number" then
		classCache[itemID] = { classID, subClassID }
		return classID, subClassID
	end
end

-- Items owned by this character: whatever is larger of the game's own count and
-- (bags now + last recorded bank + Warband bank). The bank parts only update when the bank is opened.
function GA.Owned(itemID)
	local live
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
		n = ok and ns.Safe(n)
		live = type(n) == "number" and n or nil
	end
	local b = ns.Inventory and ns.Inventory.Breakdown(itemID)
	local summed = b and b.bags and (b.bags + b.bank + b.warband) or nil
	if live and summed then return math.max(live, summed) end
	return live or summed
end

local function CharacterProfessions()
	local cur = ns.CharacterManager.GetCurrent()
	local have = {}
	for _, p in ipairs(cur and cur.professions or {}) do have[p.name:lower()] = p end
	return have, cur
end

-- Priced gatherable items for one gathering profession, most valuable first.
-- Each entry is { id, st } where st comes from MarketData.GetStats.
local function Candidates(def)
	local tradeClass, sub = TradeGoodsClass(), SubclassOf(def)
	local ids = {}
	for id in pairs(ns.db.market.prices) do ids[id] = true end
	for id in pairs(ns.db.market.manual) do ids[id] = true end
	local items = {}
	for id in pairs(ids) do
		local classID, subClassID = GA.ItemClass(id)
		if classID == tradeClass and subClassID == sub then
			local st = ns.MarketData.GetStats(id)
			if st then items[#items + 1] = { id = id, st = st } end
		end
	end
	table.sort(items, function(a, b) if a.st.price ~= b.st.price then return a.st.price > b.st.price end return a.id < b.id end)
	return items
end

-- { professions = { {name, skill, maxSkill, items = {...}} }, anyProfession, character }
-- items: { id, price, avg, change, trend, stale, owned, usedIn } sorted by price, highest first.
function GA.Suggest()
	local have, cur = CharacterProfessions()
	local result = { professions = {}, anyProfession = next(have) ~= nil, character = cur }
	local used = ns.ProfitCalculator.All().usedBy
	for _, def in ipairs(GA.PROFESSIONS) do
		local mine = have[def.name:lower()]
		if mine then
			local items = {}
			for _, c in ipairs(Candidates(def)) do
				local st = c.st
				items[#items + 1] = {
					id = c.id, price = st.price, avg = st.avg, change = st.change, trend = st.trend,
					stale = st.stale, owned = GA.Owned(c.id), usedIn = used[c.id] and #used[c.id] or 0,
				}
			end
			result.professions[#result.professions + 1] = { name = def.name, skill = mine.skill, maxSkill = mine.maxSkill, items = items }
		end
	end
	return result
end

-- Top picks are looked up once per row of the Market tab, so they are cached until a price
-- changes or the character's professions change.
local topCache = { key = nil, set = {} }
local TOP_N = 5

-- Is this item among the top 5 most valuable gatherables for this character? -> true, professionName
function GA.IsTopPick(itemID)
	local have, cur = CharacterProfessions()
	local sig = {}
	for _, def in ipairs(GA.PROFESSIONS) do if have[def.name:lower()] then sig[#sig + 1] = def.name end end
	local key = ns.MarketData.revision .. "|" .. tostring(cur and cur.name) .. "|" .. table.concat(sig, ",")
	if topCache.key ~= key then
		local set = {}
		for _, def in ipairs(GA.PROFESSIONS) do
			if have[def.name:lower()] then
				local list = Candidates(def)
				for i = 1, math.min(TOP_N, #list) do set[list[i].id] = set[list[i].id] or def.name end
			end
		end
		topCache = { key = key, set = set }
	end
	local prof = topCache.set[itemID]
	return prof ~= nil, prof
end
