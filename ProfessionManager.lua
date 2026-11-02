-- Goblin Advisor: ProfessionManager
-- Turns the recorded recipes into per-profession summaries and side-by-side comparisons.
-- Everything here is counted from recorded data. Anything that needs prices is reported as
-- nil ("no data") and is filled in by the profit modules in Phase 3: nothing is estimated.
local _, ns = ...

local PM = {}
ns.ProfessionManager = PM

local TOP_MATERIALS = 5

-- Summaries for every profession we know about, sorted by name.
-- Each: { name, recipes, avgReagents, distinctMaterials, topMaterials = {{id, uses}}, characters = {...} }
function PM.Summaries()
	local byName = {}
	local function Get(name)
		if not byName[name] then
			byName[name] = { name = name, recipes = 0, reagentSlots = 0, uses = {}, characters = {}, outputs = 0 }
		end
		return byName[name]
	end

	for _, r in pairs(ns.db.recipes) do
		local s = Get(r.prof)
		s.recipes = s.recipes + 1
		if r.out then s.outputs = s.outputs + 1 end
		for _, slot in ipairs(r.reagents) do
			s.reagentSlots = s.reagentSlots + 1
			-- Count a slot once, by its lowest-tier item, so quality tiers are not double counted.
			local id = slot.ids[1]
			s.uses[id] = (s.uses[id] or 0) + 1
		end
	end

	-- Professions the characters have (even when no recipes were recorded yet).
	for key, c in pairs(ns.db.characters) do
		for _, p in ipairs(c.professions or {}) do
			local s = Get(p.name)
			local known = 0
			for _ in pairs((c.known and c.known[p.name]) or {}) do known = known + 1 end
			s.characters[#s.characters + 1] = {
				key = key, name = c.name, skill = p.skill, maxSkill = p.maxSkill,
				known = c.known and c.known[p.name] and known or nil,
			}
		end
	end

	local list = {}
	for _, s in pairs(byName) do
		local top = {}
		local distinct = 0
		for id, n in pairs(s.uses) do top[#top + 1] = { id = id, uses = n }; distinct = distinct + 1 end
		table.sort(top, function(a, b) if a.uses ~= b.uses then return a.uses > b.uses end return a.id < b.id end)
		while #top > TOP_MATERIALS do table.remove(top) end
		s.topMaterials = top
		s.distinctMaterials = distinct
		s.avgReagents = s.recipes > 0 and (s.reagentSlots / s.recipes) or nil
		s.uses = nil
		table.sort(s.characters, function(a, b) return (a.name or "") < (b.name or "") end)
		list[#list + 1] = s
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

-- Recipes of one profession, known ones first, then by name.
function PM.Recipes(profName, knownSet)
	local list = {}
	for rid, r in pairs(ns.db.recipes) do
		if r.prof == profName then
			list[#list + 1] = { id = rid, rec = r, known = knownSet and knownSet[rid] and true or false }
		end
	end
	table.sort(list, function(a, b)
		if a.known ~= b.known then return a.known end
		if a.rec.name ~= b.rec.name then return a.rec.name < b.rec.name end
		return a.id < b.id
	end)
	return list
end

-- Which recipes does the current character know for this profession?
function PM.CurrentKnown(profName)
	local c = ns.CharacterManager.GetCurrent()
	return c and c.known and c.known[profName] or nil
end

-- Side-by-side rows for two summaries. A nil cell means "no data".
function PM.Compare(a, b)
	local function cell(s, f) return s and f(s) or nil end
	local rows = {
		{ label = "Recipes recorded", a = cell(a, function(s) return s.recipes end), b = cell(b, function(s) return s.recipes end) },
		{ label = "Avg reagents per recipe",
		  a = cell(a, function(s) return s.avgReagents and tonumber(("%.1f"):format(s.avgReagents)) end),
		  b = cell(b, function(s) return s.avgReagents and tonumber(("%.1f"):format(s.avgReagents)) end) },
		{ label = "Distinct materials", a = cell(a, function(s) return s.recipes > 0 and s.distinctMaterials or nil end),
		  b = cell(b, function(s) return s.recipes > 0 and s.distinctMaterials or nil end) },
		{ label = "Characters with it", a = cell(a, function(s) return #s.characters end), b = cell(b, function(s) return #s.characters end) },
		{ label = "Priced recipes", a = cell(a, function(s) local p = ns.ProfitCalculator.Profession(s.name); return p and (#p.priced .. "/" .. p.total) or nil end),
		  b = cell(b, function(s) local p = ns.ProfitCalculator.Profession(s.name); return p and (#p.priced .. "/" .. p.total) or nil end),
		  note = "scan the AH" },
		{ label = "Profit, best 5 avg (per craft)", money = true,
		  a = cell(a, function(s) local p = ns.ProfitCalculator.Profession(s.name); return p and p.score or nil end),
		  b = cell(b, function(s) local p = ns.ProfitCalculator.Profession(s.name); return p and p.score or nil end),
		  note = "needs 3+ priced recipes" },
		{ label = "Startup investment", a = nil, b = nil, note = "not available from the client" },
		{ label = "Gold per hour", a = nil, b = nil, note = "only from recorded sessions" },
	}
	return rows
end
