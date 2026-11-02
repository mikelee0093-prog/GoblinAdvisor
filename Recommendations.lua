-- Goblin Advisor: Recommendations
-- Pulls the profit, price and gathering data together into advice. Every recommendation says
-- what it is based on, and with no price data there is simply no recommendation.
local _, ns = ...

local R = {}
ns.Recommendations = R

local SELL_HIGH = 0.10       -- price this far above its recent average -> good time to sell
local HOLD_LOW = -0.10       -- this far below -> hold for a better price
local CRAFT_MARGIN = 0.10    -- crafting must clear 10% margin to be suggested over selling

local function Pct(x) return ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))) end

---------------------------------------------------------------- character stage
-- fresh / leveling / established / max, from level and profession skill. nil without a character.
function R.Stage()
	local cur = ns.CharacterManager.GetCurrent()
	if not cur or not cur.level then return nil end
	local maxLevel
	if GetMaxLevelForPlayerExpansion then
		local ok, v = pcall(GetMaxLevelForPlayerExpansion)
		maxLevel = ok and ns.Safe(v) or nil
	end
	if maxLevel and cur.level >= maxLevel then return "max", "level cap reached" end
	if cur.level <= 10 then return "fresh", "level " .. cur.level end
	for _, p in ipairs(cur.professions or {}) do
		if (p.maxSkill or 0) > 0 and p.skill >= 0.75 * p.maxSkill then
			return "established", p.name .. " is " .. p.skill .. "/" .. p.maxSkill
		end
	end
	return "leveling", "level " .. cur.level
end

R.STAGE_LABEL = { fresh = "Fresh character", leveling = "Leveling character", established = "Established character", max = "Max-level character" }

function R.StageAdvice(stage)
	local lines = {}
	if stage == "fresh" then
		lines[1] = "Gathering needs no startup money. Mining, Herbalism or Skinning pay for themselves while you level."
	elseif stage == "leveling" then
		lines[1] = "Sell gathered materials as you go, and keep the ones your crafting profession needs."
	elseif stage == "established" then
		lines[1] = "Compare crafting against selling raw materials; the Market tab shows which wins right now."
	elseif stage == "max" then
		lines[1] = "Crafted goods and market timing pay best at max level: watch price trends before selling."
	end
	return lines
end

---------------------------------------------------------------- professions
-- { name, score, priced, total, coverage, mine } best score first; unscored ones last.
function R.ProfessionRanking()
	local have = {}
	local cur = ns.CharacterManager.GetCurrent()
	for _, p in ipairs(cur and cur.professions or {}) do have[p.name] = true end

	local out = {}
	for _, s in ipairs(ns.ProfessionManager.Summaries()) do
		local p = ns.ProfitCalculator.Profession(s.name)
		out[#out + 1] = {
			name = s.name, recipes = s.recipes, mine = have[s.name] or false,
			score = p and p.score or nil, priced = p and #p.priced or 0,
			total = p and p.total or s.recipes, coverage = p and p.coverage or 0,
		}
	end
	table.sort(out, function(a, b)
		if (a.score ~= nil) ~= (b.score ~= nil) then return a.score ~= nil end
		if a.score and a.score ~= b.score then return a.score > b.score end
		return a.name < b.name
	end)
	return out
end

---------------------------------------------------------------- materials
-- Every item used as a reagent in a recorded recipe (each quality tier separately).
local matCache = { rev = nil, ids = nil }
function R.MaterialIDs()
	if matCache.rev == ns.RecipeManager.revision and matCache.ids then return matCache.ids end
	local seen, ids = {}, {}
	for _, rec in pairs(ns.db.recipes) do
		for _, slot in ipairs(rec.reagents) do
			for _, id in ipairs(slot.ids) do
				if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
			end
		end
	end
	table.sort(ids)
	matCache = { rev = ns.RecipeManager.revision, ids = ids }
	return ids
end

-- Sell / Hold / Gather / Craft with a plain-language reason. nil action = no price data.
function R.MaterialAction(itemID)
	local st = ns.MarketData.GetStats(itemID)
	if not st then return nil, "no price data" end

	local best = ns.ProfitCalculator.BestUseOf(itemID)
	if best and best.profit > 0 and best.margin and best.margin >= CRAFT_MARGIN then
		return "Craft", ("used in %s: about %s profit per craft"):format(best.name, ns.FormatMoney(best.profit))
	end
	if st.change and st.change >= SELL_HIGH then
		return "Sell", ("price is %s above its recent average"):format(Pct(st.change))
	end
	if st.change and st.change <= HOLD_LOW then
		return "Hold", ("price is %s below its recent average"):format(Pct(st.change))
	end
	local top, prof = ns.GatheringAdvisor.IsTopPick(itemID)
	if top then
		return "Gather", ("one of the most valuable %s materials you can collect"):format(prof)
	end
	if st.samples and st.samples < 3 then
		return "Hold", "not enough price history yet for a stronger call"
	end
	return "Hold", "no strong signal either way"
end

-- Total value of owned materials on this character (bags and banks), and how many owned
-- material stacks had no price. A partial total is labelled as such by the caller.
function R.InventoryValue()
	local value, priced, unpriced = 0, 0, 0
	for _, id in ipairs(R.MaterialIDs()) do
		local owned = ns.GatheringAdvisor.Owned(id)
		if owned and owned > 0 then
			local st = ns.MarketData.GetStats(id)
			if st then value = value + st.price * owned; priced = priced + 1 else unpriced = unpriced + 1 end
		end
	end
	return value, priced, unpriced
end

---------------------------------------------------------------- activities
-- { kind, text, amount (copper), unit, basis } best first. Units are never mixed up:
-- crafts are "per craft", gathering is "per item", sessions are "per hour (recorded)".
function R.Activities()
	local out = {}

	-- Only this character's professions. A recipe it knows is ready now; one it has not learned
	-- stays in the list only when its skill requirement is known and already met - and says so.
	local cur = ns.CharacterManager.GetCurrent()
	local skills = {}
	for _, p in ipairs(cur and cur.professions or {}) do skills[p.name] = p.skill or 0 end
	local candidates = {}
	for _, e in ipairs(ns.ProfitCalculator.Top(200)) do
		if e.profit > 0 and skills[e.prof] then
			local ks = ns.ProfessionManager.CurrentKnown(e.prof)
			local rec = ns.db.recipes[e.id]
			if ks and ks[e.id] then
				candidates[#candidates + 1] = { e = e }
			elseif rec and rec.req and skills[e.prof] >= rec.req then
				candidates[#candidates + 1] = { e = e, needsRecipe = true, req = rec.req }
			end
		end
	end
	for i = 1, math.min(3, #candidates) do
		local c = candidates[i]
		local e = c.e
		out[#out + 1] = {
			kind = "craft", amount = e.profit, unit = "per craft", needsRecipe = c.needsRecipe,
			text = ("Craft %s (%s)%s"):format(e.name, e.prof,
				c.needsRecipe and ns.Color("orange", ("  - learn the recipe first (skill %d needed, you have it)"):format(c.req)) or ""),
			basis = "market estimate after the 5% AH cut" .. (e.stale and ", prices are stale" or ""),
		}
	end

	local g = ns.GatheringAdvisor.Suggest()
	for _, p in ipairs(g.professions) do
		for i = 1, math.min(2, #p.items) do
			local it = p.items[i]
			out[#out + 1] = {
				kind = "gather", amount = it.price, unit = "per item",
				text = ("Gather %s (%s)"):format(ns.RecipeManager.ItemName(it.id), p.name),
				basis = "current scanned price" .. (it.stale and ", stale" or ""),
			}
		end
	end

	local s, rate = ns.GoldTracker.Best(ns.CharacterManager.currentKey)
	if s then
		out[#out + 1] = {
			kind = "session", amount = rate, unit = "per hour",
			text = "Repeat your best recorded session on this character" .. (s.zone and (" (" .. s.zone .. ")") or ""),
			basis = "recorded gold change, not market value",
		}
	end
	return out
end
