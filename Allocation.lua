-- Goblin Advisor: material allocation
-- For every material your tracked characters hold: who holds it, and which character should
-- use it. Advice comes only from recorded data: recipes in the profession windows, which
-- recipes each character knows, and scanned or manual prices. Read only: nothing is mailed
-- or moved for you.
-- Other characters' holdings are as of their last logout (bags) or last bank visit.
local _, ns = ...

local AL = {}
ns.Allocation = AL

-- Characters that have a profession, and the ones that also know a given recipe.
local function Crafters(prof, rid)
	local knows, has = {}, {}
	for _, e in ipairs(ns.CharacterManager.List()) do
		local rec = e.rec
		for _, p in ipairs(rec.professions or {}) do
			if p.name == prof then
				has[#has + 1] = e
				if rec.known and rec.known[prof] and rec.known[prof][rid] then knows[#knows + 1] = e end
				break
			end
		end
	end
	return knows, has
end

-- Plan for one item: { action, text, why, who, from } using held counts.
function AL.Plan(itemID, hold)
	local st = ns.MarketData.GetStats(itemID)
	local best = ns.ProfitCalculator.BestUseOf(itemID)
	if best and best.profit > 0 and best.margin and best.margin >= 0.10 then
		local knows, has = Crafters(best.prof, best.id)
		if #knows > 0 then
			-- prefer a character that already holds the most of it, so less has to be mailed
			local pick, pickCount = knows[1], -1
			for _, e in ipairs(knows) do
				local c = 0
				for _, h in ipairs(hold.holders) do if h.key == e.key then c = h.count end end
				if c > pickCount then pick, pickCount = e, c end
			end
			local elsewhere = hold.total - math.max(pickCount, 0)
			return { action = "Craft", who = pick.rec.name or pick.key,
				text = ("Craft %s on %s"):format(best.name, pick.rec.name or pick.key),
				why = ("%s earns about %s profit per craft."):format(best.name, ns.FormatMoney(best.profit)),
				mail = elsewhere > 0 and ("%d are held elsewhere: mail them to %s."):format(elsewhere, pick.rec.name or pick.key) or nil }
		elseif #has > 0 then
			return { action = "Learn", who = has[1].rec.name or has[1].key,
				text = ("%s could craft %s after learning it"):format(has[1].rec.name or has[1].key, best.name),
				why = ("%s is not learned by any tracked character yet; about %s profit per craft."):format(best.name, ns.FormatMoney(best.profit)) }
		end
		-- nobody can craft it: fall through to a sell/hold call
	end
	local action, why = ns.Recommendations.MaterialAction(itemID)
	if action == "Craft" then action, why = "Sell", "no tracked character has the profession for its best recipe" end
	if not action then
		return { action = nil, text = "No price data", why = "Scan the Auction House or use /ga setprice " .. itemID .. " <gold>." }
	end
	return { action = action, text = action, why = why .. (st and st.stale and " (price is stale)" or "") }
end

-- Rows for the Materials view, most valuable first.
function AL.Rows()
	local rows = {}
	for _, id in ipairs(ns.Recommendations.MaterialIDs()) do
		local hold = ns.Inventory.Holdings(id)
		if hold.total > 0 then
			local st = ns.MarketData.GetStats(id)
			local plan = AL.Plan(id, hold)
			rows[#rows + 1] = { id = id, total = hold.total, hold = hold, plan = plan,
				value = st and st.price * hold.total or nil, price = st and st.price or nil }
		end
	end
	table.sort(rows, function(a, b)
		if (a.value or -1) ~= (b.value or -1) then return (a.value or -1) > (b.value or -1) end
		return a.id < b.id
	end)
	return rows
end
