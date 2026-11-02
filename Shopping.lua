-- Goblin Advisor: Shopping list
-- Pick recipes and how many crafts you want; the addon adds up the reagents, subtracts what your
-- characters already hold (bags, banks, Warband bank, as last recorded), and prices what is left
-- from your scans. Missing prices say "no data"; they are never guessed. Advice only.
local _, ns = ...

local S = {}
ns.Shopping = S

local function List() ns.db.shopping = ns.db.shopping or { list = {} }; ns.db.shopping.list = ns.db.shopping.list or {}; return ns.db.shopping.list end

local function Find(rid) for i, e in ipairs(List()) do if e.rid == rid then return e, i end end end

function S.Add(rid, qty)
	qty = math.floor(tonumber(qty) or 1)
	if qty < 1 or not ns.db.recipes[rid] then return false end
	local e = Find(rid)
	if e then e.qty = math.min(9999, e.qty + qty) else List()[#List() + 1] = { rid = rid, qty = math.min(9999, qty) } end
	ns.UI.RefreshIfShown()
	return true
end

function S.SetQty(rid, qty)
	local e, i = Find(rid)
	if not e then return false end
	qty = math.floor(tonumber(qty) or 0)
	if qty < 1 then table.remove(List(), i) else e.qty = math.min(9999, qty) end
	ns.UI.RefreshIfShown()
	return true
end

function S.Remove(rid) return S.SetQty(rid, 0) end
function S.Clear() ns.db.shopping = { list = {} }; ns.UI.RefreshIfShown() end
function S.Qty(rid) local e = Find(rid); return e and e.qty or 0 end

-- Recipes on the list (dropping any that no longer exist), with profit per craft when it can be priced.
function S.Recipes()
	local out = {}
	for _, e in ipairs(List()) do
		local rec = ns.db.recipes[e.rid]
		if rec then
			local ev = ns.ProfitCalculator.Evaluate(e.rid, rec)
			out[#out + 1] = { rid = e.rid, name = rec.name, prof = rec.prof, qty = e.qty, profit = ev and ev.profit or nil }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- What to buy. Reagents that can be made from several quality tiers are one line: anything you
-- hold in any tier counts toward it, and the cheapest priced tier is what the cost uses.
function S.Compute()
	local lines, byKey = {}, {}
	local profit, unpricedRecipes = 0, 0
	for _, r in ipairs(S.Recipes()) do
		local rec = ns.db.recipes[r.rid]
		for _, slot in ipairs(rec.reagents) do
			local key = table.concat(slot.ids, ",")
			local ln = byKey[key]
			if not ln then ln = { ids = slot.ids, need = 0 }; byKey[key] = ln; lines[#lines + 1] = ln end
			ln.need = ln.need + slot.qty * r.qty
		end
		if r.profit then profit = profit + r.profit * r.qty else unpricedRecipes = unpricedRecipes + 1 end
	end
	local total, unpriced = 0, 0
	for _, ln in ipairs(lines) do
		local owned, best = 0, nil
		for _, id in ipairs(ln.ids) do
			owned = owned + (ns.Inventory.Holdings(id).total or 0)
			local st = ns.MarketData.GetStats(id)
			if st and (not best or st.price < best.price) then best = { id = id, price = st.price, stale = st.stale, thin = st.thin } end
		end
		ln.owned, ln.buy = owned, math.max(0, ln.need - owned)
		ln.id = best and best.id or ln.ids[1]
		ln.name = ns.RecipeManager.ItemName(ln.id)
		ln.tiers = #ln.ids
		ln.unit, ln.stale, ln.thin = best and best.price, best and best.stale, best and best.thin
		if ln.buy > 0 then
			if ln.unit then ln.cost = ln.unit * ln.buy; total = total + ln.cost else unpriced = unpriced + 1 end
		end
	end
	table.sort(lines, function(a, b)
		if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
		return a.name < b.name
	end)
	return { lines = lines, total = total, unpriced = unpriced, profit = profit, unpricedRecipes = unpricedRecipes, recipes = #S.Recipes() }
end
