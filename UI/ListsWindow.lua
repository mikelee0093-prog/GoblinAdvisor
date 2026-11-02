-- Goblin Advisor: Lists tab
-- Shopping list (what to buy for the crafts you plan) and Watch list (price targets).
-- Both are advice and bookkeeping only: nothing is bought, posted or cancelled for you.
local _, ns = ...
local UI = ns.UI

local PLAN_COLS = {
	{ key = "name", label = "Planned craft", w = 260 },
	{ key = "prof", label = "Profession", w = 110 },
	{ key = "qty", label = "Crafts", w = 60, align = "RIGHT" },
	{ key = "profit", label = "Profit each", w = 120, align = "RIGHT" },
}

local BUY_COLS = {
	{ key = "name", label = "Reagent", w = 220 },
	{ key = "need", label = "Need", w = 54, align = "RIGHT" },
	{ key = "own", label = "Own", w = 54, align = "RIGHT" },
	{ key = "buy", label = "Buy", w = 54, align = "RIGHT" },
	{ key = "unit", label = "Price each", w = 100, align = "RIGHT" },
	{ key = "cost", label = "Cost", w = 110, align = "RIGHT" },
}

local WATCH_COLS = {
	{ key = "name", label = "Item", w = 220 },
	{ key = "price", label = "Price now", w = 100, align = "RIGHT" },
	{ key = "when", label = "Alert when", w = 130 },
	{ key = "target", label = "Target", w = 100, align = "RIGHT" },
	{ key = "status", label = "Status", w = 150 },
}

local function Signed(v)
	if v == nil then return ns.Color("orange", "no data") end
	return ns.Color(v > 0 and "green" or (v < 0 and "red" or "grey"), v > 0 and "+" or "") .. ns.FormatMoney(v, true)
end

UI.RegisterPage("lists", function(parent)
	local state = { view = "shopping", sel = nil, itemText = "", goldText = "", dir = "below", selWatch = nil }

	local shopBtn = UI.Button(parent, "Shopping list", 100, 22, function() state.view = "shopping"; UI.RefreshIfShown() end)
	local watchBtn = UI.Button(parent, "Watch list", 90, 22, function() state.view = "watch"; UI.RefreshIfShown() end)
	shopBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	watchBtn:SetPoint("LEFT", shopBtn, "RIGHT", 4, 0)

	local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetJustifyH("LEFT")
	info:SetJustifyV("TOP")
	info:SetWidth(720)

	---------------------------------------------------------------- shopping
	local clearBtn = UI.ConfirmButton(parent, "Clear list", 80, 22, "Click again to clear", function() ns.Shopping.Clear() end)
	clearBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	local removeBtn = UI.Button(parent, "Remove", 64, 22, function()
		if state.sel then ns.Shopping.Remove(state.sel); state.sel = nil end
	end)
	removeBtn:SetPoint("RIGHT", clearBtn, "LEFT", -12, 0)
	local plus10 = UI.Button(parent, "+10", 36, 22, function() if state.sel then ns.Shopping.Add(state.sel, 10) end end)
	plus10:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
	local plus1 = UI.Button(parent, "+1", 30, 22, function() if state.sel then ns.Shopping.Add(state.sel, 1) end end)
	plus1:SetPoint("RIGHT", plus10, "LEFT", -4, 0)
	local minus1 = UI.Button(parent, "-1", 30, 22, function() if state.sel then ns.Shopping.SetQty(state.sel, ns.Shopping.Qty(state.sel) - 1) end end)
	minus1:SetPoint("RIGHT", plus1, "LEFT", -4, 0)
	local shopWidgets = { clearBtn, removeBtn, plus10, plus1, minus1 }

	local planTable = UI.Table(parent, PLAN_COLS, { sortKey = "name", desc = false })
	local buyTable = UI.Table(parent, BUY_COLS, { sortKey = "buyorder", desc = false })
	planTable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -64)
	planTable.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -64)
	planTable.frame:SetHeight(150)
	buyTable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -224)
	buyTable.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	---------------------------------------------------------------- watch
	local itemBox = UI.SearchBox(parent, 170, "Item id or exact name", function(t) state.itemText = t end)
	itemBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28)
	local goldBox = UI.SearchBox(parent, 90, "Target (gold)", function(t) state.goldText = t end)
	goldBox:SetPoint("LEFT", itemBox, "RIGHT", 4, 0)
	local dirBtn = UI.Button(parent, "", 130, 22, function() state.dir = state.dir == "below" and "above" or "below"; UI.RefreshIfShown() end)
	dirBtn:SetPoint("LEFT", goldBox, "RIGHT", 4, 0)
	local addBtn = UI.Button(parent, "Add / update", 90, 22, function()
		local id, target = ns.Watch.Resolve(state.itemText), ns.Watch.ParseGold(state.goldText)
		if not id then ns.Print("watch: type an item id (or the exact name of an item the addon knows), e.g. 2770."); return end
		if not target then ns.Print("watch: type the target price in gold, e.g. 12.5."); return end
		ns.Watch.Add(id, target, state.dir)
		state.selWatch = id
	end)
	addBtn:SetPoint("LEFT", dirBtn, "RIGHT", 4, 0)
	local unwatchBtn = UI.ConfirmButton(parent, "Stop watching", 100, 22, "Click again to remove", function()
		local id = state.selWatch or ns.Watch.Resolve(state.itemText)
		if id then ns.Watch.Remove(id); state.selWatch = nil end
	end)
	unwatchBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	local watchWidgets = { itemBox, goldBox, dirBtn, addBtn, unwatchBtn }

	local watchTable = UI.Table(parent, WATCH_COLS, { sortKey = "status", desc = false })
	watchTable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -78)
	watchTable.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local function Show(list, on) for _, w in ipairs(list) do if on then w:Show() else w:Hide() end end end

	local function RefreshShopping()
		local plan = ns.Shopping.Recipes()
		local c = ns.Shopping.Compute()
		local L = {}
		if #plan == 0 then
			L[1] = ns.Color("orange", "Your shopping list is empty.")
			L[2] = ns.Color("grey", "Open a recipe in the Market or Professions tab and click \"Add to shopping list\", or use /ga shop add <recipeID> <crafts>.")
		else
			L[1] = ("%d recipe(s).  To buy: %s%s"):format(#plan, ns.FormatMoney(c.total, true),
				c.unpriced > 0 and ns.Color("orange", ("  (+%d reagent(s) with no price)"):format(c.unpriced)) or "")
			L[2] = ns.Color("grey", "Own = what your characters held when last recorded (bags, bank, Warband bank), any quality tier. Prices are the cheapest scanned tier.")
			if state.sel then
				L[3] = ("Selected: %s x%d. Use -1 / +1 / +10 / Remove."):format(ns.db.recipes[state.sel] and ns.db.recipes[state.sel].name or "?", ns.Shopping.Qty(state.sel))
			else
				L[3] = ns.Color("grey", "Click a planned craft to change its count.")
			end
		end
		info:SetText(table.concat(L, "\n"))

		local rows = {}
		for _, r in ipairs(plan) do
			rows[#rows + 1] = {
				cells = { name = (r.rid == state.sel and ns.Color("gold", "> ") or "") .. r.name, prof = r.prof or "", qty = tostring(r.qty), profit = Signed(r.profit) },
				sort = { name = r.name },
				tip = { r.name, "Click to select, then use -1 / +1 / +10 / Remove.", "Profit each = market profit per craft, from scanned prices." },
				onClick = function() state.sel = r.rid; UI.RefreshIfShown() end,
			}
		end
		planTable:SetData(rows)

		local brows = {}
		for i, ln in ipairs(c.lines) do
			local need = ln.buy > 0
			brows[#brows + 1] = {
				cells = { name = ln.name .. (ln.tiers > 1 and ns.Color("grey", ("  (%d tiers)"):format(ln.tiers)) or ""),
					need = tostring(ln.need), own = tostring(ln.owned),
					buy = need and ns.Color("gold", tostring(ln.buy)) or ns.Color("green", "0"),
					unit = ln.unit and ns.FormatMoney(ln.unit, true) or ns.Color("orange", "no data"),
					cost = need and (ln.cost and ns.FormatMoney(ln.cost, true) or ns.Color("orange", "no data")) or ns.Color("grey", "-") },
				sort = { buyorder = i, name = ln.name },
				tip = { ln.name, ln.stale and ns.Color("orange", "Price is stale (over 3 days old).") or "", ln.thin and ns.Color("orange", "Thin market: few listings.") or "",
					"Click for the item details." },
				onClick = function() UI.market.Show("item", ln.id) end,
			}
		end
		buyTable:SetData(brows)
	end

	local function RefreshWatch()
		local list = ns.Watch.List()
		local hits = 0
		for _, w in ipairs(list) do if w.status == "hit" then hits = hits + 1 end end
		dirBtn.text:SetText(state.dir == "below" and "Alert: falls to" or "Alert: rises to")
		local L = {}
		if #list == 0 then
			L[1] = ns.Color("orange", "Nothing on your watch list.")
			L[2] = ns.Color("grey", "Type an item id and a target price, then Add. After each Auction House scan a chat message tells you when a target is reached. Needs a scan: watched items are included in it.")
		else
			L[1] = ("%d item(s) watched, %d at target."):format(#list, hits)
			L[2] = ns.Color("grey", "Click a row to load it into the boxes above. \"Falls to\" = a buying chance, \"rises to\" = a selling chance. Stale prices never alert.")
		end
		info:SetText(table.concat(L, "\n"))
		local rows = {}
		for _, w in ipairs(list) do
			local status = w.status == "hit" and ns.Color("green", "Target reached") or (w.status == "waiting" and ns.Color("grey", "Waiting") or ns.Color("orange", "No data: scan the AH"))
			if w.stale and w.status ~= "nodata" then status = status .. ns.Color("orange", " (stale)") end
			rows[#rows + 1] = {
				cells = { name = (w.id == state.selWatch and ns.Color("gold", "> ") or "") .. w.name,
					price = w.price and ns.FormatMoney(w.price, true) or ns.Color("orange", "no data"),
					when = w.dir == "below" and "falls to" or "rises to", target = ns.FormatMoney(w.target, true), status = status },
				sort = { name = w.name, status = w.status == "hit" and 0 or (w.status == "waiting" and 1 or 2), price = w.price, target = w.target },
				tip = { w.name, w.avg and ("Recent average: " .. ns.FormatMoney(w.avg)) or "No price history yet.", w.thin and ns.Color("orange", "Thin market: few listings.") or "" },
				onClick = function()
					state.selWatch = w.id
					state.dir = w.dir
					itemBox:SetText(tostring(w.id)); goldBox:SetText(tostring(w.target / 10000))
					UI.RefreshIfShown()
				end,
			}
		end
		watchTable:SetData(rows)
	end

	local function Refresh()
		local shopping = state.view == "shopping"
		shopBtn:SetActive(shopping); watchBtn:SetActive(not shopping)
		Show(shopWidgets, shopping); Show(watchWidgets, not shopping)
		if shopping then
			watchTable.frame:Hide(); planTable.frame:Show(); buyTable.frame:Show()
			info:ClearAllPoints(); info:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -28)
			RefreshShopping()
		else
			planTable.frame:Hide(); buyTable.frame:Hide(); watchTable.frame:Show()
			info:ClearAllPoints(); info:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -56)
			RefreshWatch()
		end
	end

	UI.tabHome.lists = function() end
	UI.lists = { Debug = state, SetView = function(v) state.view = v; UI.RefreshIfShown() end }
	return { frame = parent, Refresh = Refresh }
end)
