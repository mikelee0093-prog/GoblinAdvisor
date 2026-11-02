-- Goblin Advisor: Ledger tab
-- Real Auction House sales and purchases (from mailbox invoices). Every number here is something
-- that actually happened: nothing is estimated. "vs market" compares your average sale price with
-- today's scanned price so you can see how the listing price held up.
local _, ns = ...
local UI = ns.UI

local ITEM_COLS = {
	{ key = "name", label = "Item", w = 190 },
	{ key = "sold", label = "Sold", w = 44, align = "RIGHT" },
	{ key = "avgSold", label = "Avg sold", w = 100, align = "RIGHT" },
	{ key = "bought", label = "Bought", w = 52, align = "RIGHT" },
	{ key = "avgBought", label = "Avg bought", w = 100, align = "RIGHT" },
	{ key = "net", label = "Net", w = 110, align = "RIGHT" },
	{ key = "vs", label = "vs market", w = 70, align = "RIGHT" },
}

local TX_COLS = {
	{ key = "date", label = "When", w = 110 },
	{ key = "kind", label = "", w = 64 },
	{ key = "name", label = "Item", w = 210 },
	{ key = "qty", label = "Qty", w = 44, align = "RIGHT" },
	{ key = "unit", label = "Per item", w = 100, align = "RIGHT" },
	{ key = "net", label = "Net", w = 120, align = "RIGHT" },
}

local PERIODS = { { label = "7 days", secs = 7 * 86400 }, { label = "30 days", secs = 30 * 86400 }, { label = "All time", secs = nil } }

local function Signed(v)
	if v == nil then return ns.Color("grey", "-") end
	return ns.Color(v > 0 and "green" or (v < 0 and "red" or "grey"), v > 0 and "+" or "") .. ns.FormatMoney(v, true)
end

local function Pct(x)
	if x == nil then return ns.Color("grey", "-") end
	local color = x > 0.05 and "green" or (x < -0.05 and "red" or "grey")
	return ns.Color(color, ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))))
end

local function When(t)
	if date then
		local ok, v = pcall(date, "%b %d %H:%M", t)
		if ok and type(v) == "string" then return v end
	end
	return ns.MarketData.FormatAge(t)
end

local function ItemName(e)
	if e.id then return ns.RecipeManager.ItemName(e.id) end
	return tostring(e.name or "?")
end

UI.RegisterPage("ledger", function(parent)
	local state = { view = "items", period = 2, allChars = false }

	local itemsBtn = UI.Button(parent, "By item", 80, 22, function() state.view = "items"; UI.RefreshIfShown() end)
	local txBtn = UI.Button(parent, "Transactions", 100, 22, function() state.view = "tx"; UI.RefreshIfShown() end)
	local periodBtn = UI.Button(parent, "", 90, 22, function() state.period = state.period % #PERIODS + 1; UI.RefreshIfShown() end)
	local scopeBtn = UI.Button(parent, "", 140, 22, function() state.allChars = not state.allChars; UI.RefreshIfShown() end)
	local csvBtn = UI.Button(parent, "Copy as CSV", 100, 22, function() state.csv = true; UI.RefreshIfShown() end)
	local clearBtn = UI.ConfirmButton(parent, "Clear ledger", 100, 22, "Click again to clear", function()
		ns.Ledger.Clear()
		ns.Print("ledger cleared")
		UI.RefreshIfShown()
	end)
	itemsBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	txBtn:SetPoint("LEFT", itemsBtn, "RIGHT", 4, 0)
	periodBtn:SetPoint("LEFT", txBtn, "RIGHT", 12, 0)
	scopeBtn:SetPoint("LEFT", periodBtn, "RIGHT", 4, 0)
	clearBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
	csvBtn:SetPoint("RIGHT", clearBtn, "LEFT", -4, 0)

	local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -28)
	info:SetJustifyH("LEFT")
	info:SetWidth(720)

	local itemTable = UI.Table(parent, ITEM_COLS, { sortKey = "net" })
	local txTable = UI.Table(parent, TX_COLS, { sortKey = "when" })
	for _, t in ipairs({ itemTable, txTable }) do
		t.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -64)
		t.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	end

	-- CSV box (a multi-line box in a scroll frame so long lists can be selected and copied)
	local csv = UI.Panel(parent, "Copy as CSV")
	csv:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28)
	csv:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	csv:SetBody("")
	local scroll = CreateFrame("ScrollFrame", "GoblinAdvisorCSVScroll", csv, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", csv, "TOPLEFT", 10, -52)
	scroll:SetPoint("BOTTOMRIGHT", csv, "BOTTOMRIGHT", -30, 10)
	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetWidth(660)
	if box.SetMaxLetters then box:SetMaxLetters(0) end
	if box.SetFontObject and GameFontHighlightSmall then box:SetFontObject(GameFontHighlightSmall) end
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
	scroll:SetScrollChild(box)
	local csvHint = csv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	csvHint:SetPoint("TOPLEFT", csv, "TOPLEFT", 10, -30)
	csvHint:SetText(ns.Color("grey", "Click in the box, press Ctrl+A then Ctrl+C, and paste into a spreadsheet. Amounts are in gold."))
	local closeCsv = UI.Button(csv, "Close", 70, 20, function() state.csv = false; UI.RefreshIfShown() end)
	closeCsv:SetPoint("TOPRIGHT", csv, "TOPRIGHT", -8, -6)

	local function Opts()
		return { since = PERIODS[state.period].secs, char = (not state.allChars) and ns.CharacterManager.currentKey or nil }
	end

	local function Refresh()
		local opts = Opts()
		local sum = ns.Ledger.Summary(opts)
		itemsBtn:SetActive(state.view == "items")
		txBtn:SetActive(state.view == "tx")
		periodBtn.text:SetText(PERIODS[state.period].label)
		scopeBtn.text:SetText(state.allChars and "All characters" or "This character")

		if state.csv then
			info:Hide(); itemTable.frame:Hide(); txTable.frame:Hide(); csv:Show()
			box:SetText(ns.Ledger.CSV(opts))
			return
		end
		csv:Hide(); info:Show()

		local L = {}
		local st = ns.Ledger.stats
		if st.noApi then
			L[1] = ns.Color("orange", "This client has no mail invoice call, so sales cannot be read.")
		elseif #sum.entries == 0 then
			L[1] = ns.Color("orange", "Nothing recorded for this selection yet.")
			L[2] = ns.Color("grey", "Records start from now: open your mailbox after you sell or buy at the Auction House. The game gives no past history. Mail is only read, never taken.")
		else
			L[1] = ("Sold %s (AH cut %s)   Bought %s   Net cash flow %s"):format(ns.FormatMoney(sum.sold, true), ns.FormatMoney(sum.fees, true),
				ns.FormatMoney(sum.bought, true), Signed(sum.net))
			L[2] = ns.Color("grey", ("Net sales: crafted items %s   raw materials %s   other %s   (%d records)"):format(
				ns.FormatMoney(sum.byClass.crafted, true), ns.FormatMoney(sum.byClass.material, true), ns.FormatMoney(sum.byClass.other, true), #sum.entries))
		end
		info:SetText(table.concat(L, "\n"))

		if state.view == "items" then
			txTable.frame:Hide(); itemTable.frame:Show()
			local rows = {}
			for _, it in ipairs(sum.items) do
				local nm = it.id and ns.RecipeManager.ItemName(it.id) or tostring(it.name)
				local go = it.id and function() UI.market.Show("item", it.id) end or nil
				rows[#rows + 1] = {
					cells = { name = nm, sold = it.soldQty > 0 and tostring(it.soldQty) or ns.Color("grey", "-"),
						avgSold = it.avgSold and ns.FormatMoney(it.avgSold, true) or ns.Color("grey", "-"),
						bought = it.boughtQty > 0 and tostring(it.boughtQty) or ns.Color("grey", "-"),
						avgBought = it.avgBought and ns.FormatMoney(it.avgBought, true) or ns.Color("grey", "-"),
						net = Signed(it.net), vs = Pct(it.vsMarket) },
					sort = { name = nm, sold = it.soldQty, avgSold = it.avgSold, bought = it.boughtQty, avgBought = it.avgBought, net = it.net, vs = it.vsMarket },
					tip = { nm, it.class == "crafted" and "A crafted item." or (it.class == "material" and "A crafting material." or "Other item."),
						"Avg sold = what buyers paid per item, before the 5% cut.",
						it.market and ("Market price now: " .. ns.FormatMoney(it.market)) or "No current market price for comparison.",
						it.id and "Click for the item details." or "Not matched to a known item (the mail only gives the name)." },
					onClick = go,
				}
			end
			itemTable:SetData(rows)
		else
			itemTable.frame:Hide(); txTable.frame:Show()
			local rows = {}
			local list = sum.entries
			for i = #list, 1, -1 do
				local e = list[i]
				local isSale = e.kind == "sale"
				local net = isSale and (e.gross - e.fee) or -e.gross
				rows[#rows + 1] = {
					cells = { date = When(e.t), kind = isSale and ns.Color("green", "sold") or ns.Color("orange", "bought"), name = ItemName(e),
						qty = tostring(e.qty), unit = ns.FormatMoney(e.gross / e.qty, true), net = Signed(net) },
					sort = { when = e.t, date = e.t, kind = e.kind, name = ItemName(e), qty = e.qty, unit = e.gross / e.qty, net = net },
					tip = { ItemName(e), isSale and ("Sale price " .. ns.FormatMoney(e.gross) .. ", AH cut " .. ns.FormatMoney(e.fee)) or ("Paid " .. ns.FormatMoney(e.gross)),
						e.char and ("Character: " .. e.char) or "" },
					onClick = e.id and function() UI.market.Show("item", e.id) end or nil,
				}
			end
			txTable:SetData(rows)
		end
	end

	UI.tabHome.ledger = function() state.csv = false end
	UI.ledger = { Debug = state }
	return { frame = parent, Refresh = Refresh }
end)
