-- Goblin Advisor: Market tab
-- List views: Materials (price, trend, what to do) and Crafting profit, with a search box.
-- Click a row to open its detail view inside this tab (Back returns): an item shows its price,
-- history and the recipes that use or make it; a recipe shows every reagent with quality-tier
-- prices and the full profit calculation.
-- Prices come from your own Auction House scans or /ga setprice. Missing prices show as
-- "no data": a profit built on a missing price is never displayed.
local _, ns = ...
local UI = ns.UI

local function Pct(x)
	if x == nil then return ns.Color("grey", "-") end
	local color = x > 0.05 and "green" or (x < -0.05 and "red" or "grey")
	return ns.Color(color, ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))))
end

local ACTION_COLOR = { Sell = "orange", Hold = "grey", Gather = "blue", Craft = "green" }
local HISTORY_LINES = 8

local function SourceLine(st)
	local src = st.source == "manual" and "set by you (/ga setprice)" or "Auction House scan"
	return ("Source: %s, %s%s"):format(src, ns.MarketData.FormatAge(st.updated), st.stale and " - STALE" or "")
end

local function DayLabel(day)
	if date then
		local ok, text = pcall(date, "%b %d", day * ns.MarketData.DAY)
		if ok and type(text) == "string" then return text end
	end
	return "day " .. day
end

local function Money(v) return v and ns.FormatMoney(v) or ns.Color("orange", "no data") end

local function Signed(v)
	if v == nil then return ns.Color("orange", "no data") end
	return ns.Color(v > 0 and "green" or (v < 0 and "red" or "grey"), v > 0 and "+" or "") .. ns.FormatMoney(v)
end

local function Matches(query, ...)
	if query == "" then return true end
	for i = 1, select("#", ...) do
		local text = select(i, ...)
		if type(text) == "string" and text:lower():find(query, 1, true) then return true end
	end
	return false
end

---------------------------------------------------------------- list views
local MATERIAL_COLS = {
	{ key = "name", label = "Material", w = 170 },
	{ key = "price", label = "Price", w = 92, align = "RIGHT" },
	{ key = "avg", label = "Recent avg", w = 92, align = "RIGHT" },
	{ key = "change", label = "Change", w = 60, align = "RIGHT" },
	{ key = "owned", label = "Owned", w = 54, align = "RIGHT" },
	{ key = "value", label = "Value", w = 92, align = "RIGHT" },
	{ key = "action", label = "Action", w = 64 },
}

local PROFIT_COLS = {
	{ key = "name", label = "Recipe", w = 170 },
	{ key = "prof", label = "Profession", w = 90 },
	{ key = "cost", label = "Reagents", w = 92, align = "RIGHT" },
	{ key = "sells", label = "Sells for", w = 92, align = "RIGHT" },
	{ key = "profit", label = "Profit", w = 92, align = "RIGHT" },
	{ key = "margin", label = "Margin", w = 54, align = "RIGHT" },
	{ key = "verdict", label = "vs raw", w = 64 },
}

local function MaterialRows(showUnpriced, query, go)
	local rows = {}
	for _, id in ipairs(ns.Recommendations.MaterialIDs()) do
		local st = ns.MarketData.GetStats(id)
		if st or showUnpriced then
			local name = ns.RecipeManager.ItemName(id)
			if Matches(query, name) then
				local owned = ns.GatheringAdvisor.Owned(id)
				local cells, sort, tip = { name = name }, { name = name }, { name }
				if st then
					local action, why = ns.Recommendations.MaterialAction(id)
					cells.price = ns.FormatMoney(st.price)
					cells.avg = st.avg and ns.FormatMoney(st.avg) or ns.Color("grey", "-")
					cells.change = Pct(st.change)
					cells.value = owned and owned > 0 and ns.FormatMoney(st.price * owned) or ns.Color("grey", "-")
					cells.action = action and ns.Color(ACTION_COLOR[action] or "white", action) or ""
					sort.price, sort.avg, sort.change = st.price, st.avg, st.change
					sort.value = owned and st.price * owned or nil
					sort.action = action
					tip[#tip + 1] = SourceLine(st)
					if st.avg then
						tip[#tip + 1] = ("Recent average = mean of your %d earlier daily scans. Change = current price vs that average."):format(st.samples - 1)
					else
						tip[#tip + 1] = ("Trend needs 3 days of scans; you have %d."):format(st.samples or 0)
					end
					if action then tip[#tip + 1] = ("%s: %s."):format(action, why) end
				else
					cells.price = ns.Color("orange", "no data")
					tip[#tip + 1] = "No price yet. Scan the Auction House, or set one: /ga setprice <item> <gold>."
				end
				cells.owned = owned and tostring(owned) or ns.Color("grey", "-")
				sort.owned = owned
				rows[#rows + 1] = { cells = cells, sort = sort, tip = tip, onClick = function() go("item", id) end }
			end
		end
	end
	return rows
end

local function ProfitRows(showUnpriced, query, go)
	local rows = {}
	for _, e in ipairs(ns.ProfitCalculator.All().list) do
		if (e.profit or showUnpriced) and Matches(query, e.name, e.prof) then
			local cells = { name = e.name, prof = e.prof }
			local sort = { name = e.name, prof = e.prof }
			local tip = { e.name .. "  (" .. e.prof .. ")" }
			if e.profit then
				local c = e.profit > 0 and "green" or "red"
				cells.cost = ns.FormatMoney(e.cost)
				cells.sells = ns.FormatMoney(e.outPrice)
				cells.profit = ns.Color(c, e.profit > 0 and "+" or "") .. ns.FormatMoney(e.profit)
				cells.margin = e.margin and Pct(e.margin) or ns.Color("grey", "-")
				cells.verdict = e.uplift > 0 and ns.Color("green", "craft") or ns.Color("orange", "sell raw")
				sort.cost, sort.sells, sort.profit, sort.margin, sort.verdict = e.cost, e.outPrice, e.profit, e.margin, e.verdict
				tip[#tip + 1] = "Reagents: the cheapest quality of each, added up."
				tip[#tip + 1] = ("Sells for: item price x 95%% (5%% AH cut) x average items made = %s"):format(ns.FormatMoney(e.revenue))
				tip[#tip + 1] = ("Profit = sells for - reagents. Return on spend: %s"):format(e.roi and ("%+d%%"):format(math.floor(e.roi * 100)) or "n/a")
				tip[#tip + 1] = ("vs raw: if you already hold the reagents, selling them instead would net %s, so crafting is %s."):format(ns.FormatMoney(e.rawNet), e.uplift > 0 and "better" or "worse")
				if e.stale then tip[#tip + 1] = "Some prices used are stale (over 3 days old)." end
			else
				cells.profit = ns.Color("orange", "no data")
				tip[#tip + 1] = "Not calculated: " .. (e.reason or "missing prices") .. "."
			end
			rows[#rows + 1] = { cells = cells, sort = sort, tip = tip, onClick = function() go("recipe", e.id) end }
		end
	end
	return rows
end

---------------------------------------------------------------- detail: item
local ITEM_REL_COLS = {
	{ key = "role", label = "", w = 52 },
	{ key = "name", label = "Recipe", w = 190 },
	{ key = "prof", label = "Profession", w = 96 },
	{ key = "profit", label = "Profit", w = 110, align = "RIGHT" },
}

local function ItemDetail(id, go)
	local name = ns.RecipeManager.ItemName(id)
	local st = ns.MarketData.GetStats(id)
	local L = {}
	if st then
		L[#L + 1] = "Price: " .. ns.FormatMoney(st.price)
		L[#L + 1] = ns.Color("grey", SourceLine(st))
		if st.avg then
			L[#L + 1] = ("Recent average: %s  (%s)"):format(ns.FormatMoney(st.avg), Pct(st.change))
		else
			L[#L + 1] = ns.Color("grey", ("Trend needs 3 days of scans; you have %d."):format(st.samples or 0))
		end
		local action, why = ns.Recommendations.MaterialAction(id)
		if action then L[#L + 1] = ("Suggested: %s %s"):format(ns.Color(ACTION_COLOR[action] or "white", action), ns.Color("grey", "- " .. why)) end
	else
		L[#L + 1] = "Price: " .. ns.Color("orange", "no data")
		L[#L + 1] = ns.Color("grey", "Scan the Auction House, or set one yourself:")
		L[#L + 1] = ns.Color("grey", ("/ga setprice %d <gold>"):format(id))
	end
	local owned = ns.GatheringAdvisor.Owned(id)
	if owned then
		L[#L + 1] = ("You hold: %d%s"):format(owned, (st and owned > 0) and ("  (worth " .. ns.FormatMoney(st.price * owned) .. ")") or "")
		L[#L + 1] = ns.Color("grey", "This character, bags and banks.")
	end
	local h = ns.db.market.history[id]
	if h and #h > 0 then
		L[#L + 1] = ""
		L[#L + 1] = ns.Color("gold", "Scan history (newest first)")
		for i = #h, math.max(1, #h - HISTORY_LINES + 1), -1 do
			L[#L + 1] = ("  %s   %s"):format(DayLabel(h[i].d), ns.FormatMoney(h[i].p))
		end
	end
	L[#L + 1] = ""
	L[#L + 1] = ns.Color("grey", "Prices are from your last Auction House scan,")
	L[#L + 1] = ns.Color("grey", "not a live feed. The game allows a scan about every 15 minutes.")

	local all = ns.ProfitCalculator.All()
	local rows = {}
	local function Add(e, role)
		local cells = { role = role == "makes" and ns.Color("green", "makes") or ns.Color("grey", "uses"), name = e.name, prof = e.prof,
			profit = e.profit and Signed(e.profit) or ns.Color("orange", "no data") }
		rows[#rows + 1] = {
			cells = cells,
			sort = { role = role == "makes" and 0 or 1, name = e.name, prof = e.prof, profit = e.profit },
			tip = { e.name, e.profit and "Profit per craft after the 5% AH cut." or ("Not calculated: " .. (e.reason or "missing prices")) },
			onClick = function() go("recipe", e.id) end,
		}
	end
	for _, e in ipairs(all.madeBy[id] or {}) do Add(e, "makes") end
	for _, e in ipairs(all.usedByAll[id] or {}) do Add(e, "uses") end
	return name, table.concat(L, "\n"), rows
end

---------------------------------------------------------------- detail: recipe
local RECIPE_COLS = {
	{ key = "name", label = "Item", w = 200 },
	{ key = "need", label = "Need", w = 56, align = "RIGHT" },
	{ key = "have", label = "Have", w = 52, align = "RIGHT" },
	{ key = "price", label = "Unit price", w = 100, align = "RIGHT" },
	{ key = "cost", label = "Cost", w = 100, align = "RIGHT" },
}

local function RecipeDetail(rid, go)
	local b = ns.ProfitCalculator.Breakdown(rid)
	if not b then return nil end
	local e, rec = b.eval, b.recipe
	local known = ns.ProfessionManager.CurrentKnown(rec.prof)
	local L = {}
	L[#L + 1] = ("%s  %s"):format(rec.prof, known and (known[rid] and ns.Color("green", "(you know this)") or ns.Color("grey", "(not learned)")) or "")
	L[#L + 1] = ""
	if rec.out then
		local per = rec.qmin == rec.qmax and tostring(rec.qmin) or (rec.qmin .. "-" .. rec.qmax)
		L[#L + 1] = ("Makes: %s x%s"):format(ns.RecipeManager.ItemName(rec.out), per)
		L[#L + 1] = ("Item price: %s"):format(b.out and ns.FormatMoney(b.out.price) or ns.Color("orange", "no data"))
		if b.out then L[#L + 1] = ns.Color("grey", SourceLine(b.out)) end
	else
		L[#L + 1] = ns.Color("orange", "No output item recorded (for example an enchant), so it cannot be priced.")
	end
	L[#L + 1] = ""
	L[#L + 1] = ns.Color("gold", "Calculation")
	L[#L + 1] = "Reagents: " .. Money(e.cost)
	L[#L + 1] = "Sells for (after 5% cut): " .. Money(e.revenue)
	L[#L + 1] = "Profit: " .. Signed(e.profit)
	if e.profit then
		L[#L + 1] = ("Margin %s   Return on spend %s"):format(e.margin and Pct(e.margin) or "-", e.roi and ("%+d%%"):format(math.floor(e.roi * 100)) or "-")
		L[#L + 1] = ("If you hold the reagents: selling them raw nets %s, so crafting is %s by %s."):format(
			ns.FormatMoney(e.rawNet), e.uplift > 0 and ns.Color("green", "better") or ns.Color("orange", "worse"), ns.FormatMoney(math.abs(e.uplift)))
		if e.stale then L[#L + 1] = ns.Color("orange", "Some prices used are stale (over 3 days old).") end
	else
		L[#L + 1] = ns.Color("orange", "Not calculated: " .. (e.reason or "missing prices") .. ".")
		if #e.missing > 0 then L[#L + 1] = ns.Color("grey", "Scan the Auction House or use /ga setprice for the reagents marked no data.") end
	end

	local rows = {}
	for _, slot in ipairs(b.slots) do
		local ch = slot.chosen
		local owned = ns.GatheringAdvisor.Owned(ch.id)
		local have = owned and (owned >= slot.qty and tostring(owned) or ns.Color("red", tostring(owned))) or ns.Color("grey", "-")
		local tip = { ns.RecipeManager.ItemName(ch.id) }
		if #slot.tiers > 1 then
			tip[#tip + 1] = "Quality tiers (the cheapest priced one is used):"
			for i, t in ipairs(slot.tiers) do
				tip[#tip + 1] = ("  Tier %d: %s  %s%s"):format(i, ns.RecipeManager.ItemName(t.id), t.price and ns.FormatMoney(t.price) or "no data", t == ch and "  <- used" or "")
			end
		end
		if not slot.priced then tip[#tip + 1] = ("No price. /ga setprice %d <gold>"):format(ch.id) end
		rows[#rows + 1] = {
			cells = { name = ns.RecipeManager.ItemName(ch.id) .. (#slot.tiers > 1 and ns.Color("grey", ("  (%d tiers)"):format(#slot.tiers)) or ""),
				need = tostring(slot.qty), have = have, price = Money(ch.price), cost = slot.lineCost and ns.FormatMoney(slot.lineCost) or ns.Color("orange", "no data") },
			sort = { name = ns.RecipeManager.ItemName(ch.id), need = slot.qty, have = owned, price = ch.price, cost = slot.lineCost },
			tip = tip,
			onClick = function() go("item", ch.id) end,
		}
	end
	return rec.name, table.concat(L, "\n"), rows
end

---------------------------------------------------------------- the page
UI.RegisterPage("market", function(parent)
	local state = { view = "materials", showUnpriced = false, query = "", detail = nil, history = {} }
	local debug = {}

	-- list controls
	local matBtn = UI.Button(parent, "Materials", 90, 22, function() state.view = "materials"; UI.RefreshIfShown() end)
	local profitBtn = UI.Button(parent, "Crafting profit", 110, 22, function() state.view = "profit"; UI.RefreshIfShown() end)
	local unpricedBtn = UI.Button(parent, "Unpriced: hidden", 118, 22, function() state.showUnpriced = not state.showUnpriced; UI.RefreshIfShown() end)
	local search = UI.SearchBox(parent, 170, "Search items or recipes...", function(text)
		local q = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		if q ~= state.query then
			state.query = q
			if state.detail then state.detail, state.history = nil, {} end   -- typing means "back to the list"
			UI.RefreshIfShown()
		end
	end)
	local scanBtn = UI.Button(parent, "Scan AH", 80, 22, function() ns.AuctionScanner.RequestScan("button") end)
	matBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	profitBtn:SetPoint("LEFT", matBtn, "RIGHT", 4, 0)
	unpricedBtn:SetPoint("LEFT", profitBtn, "RIGHT", 10, 0)
	search:SetPoint("LEFT", unpricedBtn, "RIGHT", 10, 0)
	scanBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

	local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -28)
	info:SetJustifyH("LEFT")

	local matTable = UI.Table(parent, MATERIAL_COLS, { sortKey = "value" })
	local profitTable = UI.Table(parent, PROFIT_COLS, { sortKey = "profit" })
	for _, t in ipairs({ matTable, profitTable }) do
		t.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -46)
		t.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	end

	-- detail view
	local detail = CreateFrame("Frame", nil, parent)
	detail:SetAllPoints(parent)
	detail:Hide()
	local backBtn = UI.Button(detail, "< Back", 70, 22, function() UI.market.Back() end)
	backBtn:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, 0)
	local homeBtn = UI.Button(detail, "Market home", 96, 22, function() UI.market.Home() end)
	homeBtn:SetPoint("LEFT", backBtn, "RIGHT", 4, 0)
	local title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", homeBtn, "RIGHT", 12, 0)
	local facts = UI.Panel(detail, "Details")
	facts:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -30)
	facts:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 0, 0)
	facts:SetWidth(300)
	local relTables = { item = UI.Table(detail, ITEM_REL_COLS, { sortKey = "role", desc = false }),
		recipe = UI.Table(detail, RECIPE_COLS, { sortKey = "name", desc = false }) }
	for _, t in pairs(relTables) do
		t.frame:SetPoint("TOPLEFT", detail, "TOPLEFT", 306, -30)
		t.frame:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 0)
		t.frame:Hide()
	end

	-- navigation ------------------------------------------------------
	local function Go(kind, id)
		if state.detail then table.insert(state.history, state.detail) end
		state.detail = { kind = kind, id = id }
		UI.OpenTab("market")
	end

	UI.market = {
		Show = Go,
		Back = function()
			state.detail = table.remove(state.history)
			UI.RefreshIfShown()
		end,
		Home = function()
			state.detail, state.history = nil, {}
			state.query = ""
			search:SetText("")
			UI.RefreshIfShown()
		end,
		Find = function(text)
			state.detail, state.history = nil, {}
			search:SetText(text or "")
			state.query = (text or ""):lower()
			UI.OpenTab("market")
		end,
		Debug = debug,
	}

	UI.tabHome.market = function() UI.market.Home() end

	local function Refresh()
		local d = state.detail
		local name, factsText, rows
		if d then
			if d.kind == "item" then name, factsText, rows = ItemDetail(d.id, Go)
			else name, factsText, rows = RecipeDetail(d.id, Go) end
			if not name then state.detail, state.history, d = nil, {}, nil end   -- recipe no longer exists
		end

		for _, w in ipairs({ matBtn, profitBtn, unpricedBtn, search, info }) do
			if d then w:Hide() else w:Show() end
		end
		debug.mode, debug.id, debug.query = d and d.kind or "list", d and d.id, state.query
		debug.depth = #state.history

		if d then
			matTable.frame:Hide(); profitTable.frame:Hide()
			detail:Show()
			title:SetText(name)
			facts:SetTitle(d.kind == "item" and "Item" or "Recipe")
			facts:SetBody(factsText)
			for kind, t in pairs(relTables) do
				if kind == d.kind then t.frame:Show() else t.frame:Hide() end
			end
			relTables[d.kind]:SetData(rows)
			debug.facts, debug.relData = factsText, relTables[d.kind].data
			return
		end
		detail:Hide()
		debug.facts, debug.relData = nil, nil

		local md, as = ns.MarketData, ns.AuctionScanner
		local lastScan = ns.db.market.lastScan
		local line = ("%d items priced  |  last scan: %s"):format(md.PriceCount(), lastScan and md.FormatAge(lastScan) or "never")
		if ns.RecipeManager.Count() == 0 then
			line = line .. ns.Color("orange", "  |  no recipes recorded yet: open your profession windows first")
		elseif not as.open then
			line = line .. ns.Color("grey", "  |  open the Auction House to scan")
		end
		info:SetText(line)

		matBtn:SetActive(state.view == "materials")
		profitBtn:SetActive(state.view == "profit")
		-- while searching, unpriced items are included so you can find one to price
		local showUnpriced = state.showUnpriced or state.query ~= ""
		unpricedBtn.text:SetText((state.showUnpriced and "Unpriced: shown") or "Unpriced: hidden")
		if state.view == "materials" then
			profitTable.frame:Hide(); matTable.frame:Show()
			local data = MaterialRows(showUnpriced, state.query, Go)
			matTable:SetData(data)
			debug.listRows = #data
		else
			matTable.frame:Hide(); profitTable.frame:Show()
			local data = ProfitRows(showUnpriced, state.query, Go)
			profitTable:SetData(data)
			debug.listRows = #data
		end
	end

	return { frame = parent, Refresh = Refresh }
end)
