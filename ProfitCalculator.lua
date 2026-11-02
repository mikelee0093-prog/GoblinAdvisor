-- Goblin Advisor: ProfitCalculator
-- Crafting profit from recorded recipes and current prices. Whenever a price is missing the
-- affected numbers are nil with a reason: a partial sum is never shown as a real profit.
local _, ns = ...

local PC = {}
ns.ProfitCalculator = PC

local AH_CUT = 0.05          -- the Auction House keeps 5% of the sale price
PC.AH_CUT = AH_CUT
local TOP_N = 5              -- profession score = average profit of its best N priced recipes
local MIN_PRICED = 3         -- fewer priced recipes than this and a profession gets no score

local cache = { key = nil }

local function CheapestTier(ids)
	local best, bestId, stale
	for _, id in ipairs(ids) do
		local p = ns.MarketData.GetPrice(id)
		if p and (not best or p.price < best) then
			best, bestId = p.price, id
			stale = p.updated and (ns.MarketData.Now() - p.updated) > ns.MarketData.STALE_DAYS * ns.MarketData.DAY
		end
	end
	return best, bestId, stale
end

-- Work out one recipe. Always returns a table; check e.profit before using money fields.
--   cost       total reagent cost (cheapest quality tier per slot) or nil if any price is missing
--   revenue    expected sale after the AH cut, for the average number of items made
--   profit     revenue - cost             margin  profit / revenue        roi  profit / cost
--   rawNet     what the reagents would fetch if sold instead (after the cut)
--   uplift     revenue - rawNet: how much better crafting is than selling the reagents you hold
--   reason     plain-language why a number is missing
function PC.Evaluate(rid, rec)
	rec = rec or ns.db.recipes[rid]
	if not rec then return nil end
	local e = { id = rid, name = rec.name, prof = rec.prof, recipe = rec, missing = {}, stale = false }

	local cost, complete = 0, #rec.reagents > 0
	for _, slot in ipairs(rec.reagents) do
		local price, _, stale = CheapestTier(slot.ids)
		if price then
			cost = cost + price * slot.qty
			if stale then e.stale = true end
		else
			complete = false
			e.missing[#e.missing + 1] = slot.ids[1]
		end
	end
	e.partialCost = cost
	if complete then e.cost = cost end

	if rec.out then
		local o = ns.MarketData.GetPrice(rec.out)
		if o then
			e.outPrice = o.price
			if o.updated and (ns.MarketData.Now() - o.updated) > ns.MarketData.STALE_DAYS * ns.MarketData.DAY then e.stale = true end
		end
	end

	if #rec.reagents == 0 then
		e.reason = "no reagents recorded"
	elseif not complete then
		e.reason = ("no price for %d reagent%s"):format(#e.missing, #e.missing == 1 and "" or "s")
	elseif not rec.out then
		e.reason = "no output item (for example an enchant), so it cannot be priced"
	elseif not e.outPrice then
		e.reason = "no price for the crafted item"
	else
		local avgQty = ((rec.qmin or 1) + (rec.qmax or 1)) / 2
		e.revenue = e.outPrice * (1 - AH_CUT) * avgQty
		e.profit = e.revenue - e.cost
		e.margin = e.revenue > 0 and e.profit / e.revenue or nil
		e.roi = e.cost > 0 and e.profit / e.cost or nil
		e.rawNet = e.cost * (1 - AH_CUT)
		e.uplift = e.revenue - e.rawNet
		e.verdict = e.uplift > 0 and "craft" or "sell raw"
	end
	return e
end

-- Evaluate everything once per change of prices or recipes.
function PC.All()
	local key = ns.MarketData.revision .. ":" .. ns.RecipeManager.revision
	if cache.key == key then return cache end
	local list, byProf, usedBy = {}, {}, {}
	local usedByAll, madeBy = {}, {}      -- every recipe, priced or not
	for rid, rec in pairs(ns.db.recipes) do
		local e = PC.Evaluate(rid, rec)
		list[#list + 1] = e
		if rec.out then
			madeBy[rec.out] = madeBy[rec.out] or {}
			table.insert(madeBy[rec.out], e)
		end
		local seen = {}
		for _, slot in ipairs(rec.reagents) do
			for _, id in ipairs(slot.ids) do
				if not seen[id] then
					seen[id] = true
					usedByAll[id] = usedByAll[id] or {}
					table.insert(usedByAll[id], e)
				end
			end
		end
		local p = byProf[rec.prof]
		if not p then p = { total = 0, priced = {}, name = rec.prof }; byProf[rec.prof] = p end
		p.total = p.total + 1
		if e.profit then
			p.priced[#p.priced + 1] = e
			for _, slot in ipairs(rec.reagents) do
				for _, id in ipairs(slot.ids) do
					usedBy[id] = usedBy[id] or {}
					table.insert(usedBy[id], e)
				end
			end
		end
	end
	for _, p in pairs(byProf) do
		table.sort(p.priced, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.id < b.id end)
		if #p.priced >= MIN_PRICED then
			local sum, k = 0, math.min(TOP_N, #p.priced)
			for i = 1, k do sum = sum + p.priced[i].profit end
			p.score = sum / k
		end
		p.coverage = p.total > 0 and #p.priced / p.total or 0
	end
	cache = { key = key, list = list, byProf = byProf, usedBy = usedBy, usedByAll = usedByAll, madeBy = madeBy }
	return cache
end

-- { total, priced = {evals best first}, score (nil if too few priced), coverage 0..1 } or nil
function PC.Profession(profName)
	return PC.All().byProf[profName]
end

-- Best priced recipe that uses this reagent (any quality tier), or nil.
function PC.BestUseOf(itemID)
	local list = PC.All().usedBy[itemID]
	if not list then return nil end
	local best
	for _, e in ipairs(list) do
		if not best or e.profit > best.profit then best = e end
	end
	return best
end

-- Every priced recipe, best profit first. Optionally limited to one profession.
function PC.Top(n, profName)
	local out = {}
	local src = PC.All()
	local list = profName and src.byProf[profName] and src.byProf[profName].priced or nil
	if not list then
		list = {}
		for _, p in pairs(src.byProf) do for _, e in ipairs(p.priced) do list[#list + 1] = e end end
		table.sort(list, function(a, b) if a.profit ~= b.profit then return a.profit > b.profit end return a.id < b.id end)
	end
	for i = 1, math.min(n, #list) do out[i] = list[i] end
	return out
end

function PC.PricedCount()
	local n = 0
	for _, p in pairs(PC.All().byProf) do n = n + #p.priced end
	return n
end

-- Everything the detail view needs for one recipe: the evaluation plus, for each reagent slot,
-- every quality tier with its price and which one the calculation uses (the cheapest priced).
function PC.Breakdown(rid)
	local rec = ns.db.recipes[rid]
	if not rec then return nil end
	local slots = {}
	for _, slot in ipairs(rec.reagents) do
		local tiers, best = {}, nil
		for _, id in ipairs(slot.ids) do
			local st = ns.MarketData.GetStats(id)
			local t = { id = id, price = st and st.price, stale = st and st.stale }
			tiers[#tiers + 1] = t
			if st and (not best or st.price < best.price) then best = t end
		end
		slots[#slots + 1] = {
			qty = slot.qty, tiers = tiers, chosen = best or tiers[1], priced = best ~= nil,
			lineCost = best and best.price * slot.qty or nil,
		}
	end
	return {
		eval = PC.Evaluate(rid, rec), recipe = rec, slots = slots,
		out = rec.out and ns.MarketData.GetStats(rec.out) or nil,
	}
end
