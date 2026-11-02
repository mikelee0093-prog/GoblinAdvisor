-- Goblin Advisor: Characters tab
-- Three views: Characters (everyone you have logged in with, gold, professions, safe delete),
-- Materials (who holds what and who should use it), Import / Export (copy and paste text).
-- Other characters' numbers are whatever they were when you last logged them out.
local _, ns = ...
local UI = ns.UI

local CHAR_COLS = {
	{ key = "name", label = "Character", w = 170 },
	{ key = "level", label = "Lvl", w = 36, align = "RIGHT" },
	{ key = "gold", label = "Gold", w = 160, align = "RIGHT" },
	{ key = "profs", label = "Professions", w = 232 },
	{ key = "seen", label = "Last seen", w = 90 },
}

local MAT_COLS = {
	{ key = "name", label = "Material", w = 160 },
	{ key = "total", label = "Held", w = 48, align = "RIGHT" },
	{ key = "who", label = "Held by", w = 180 },
	{ key = "plan", label = "Plan", w = 210 },
	{ key = "value", label = "Value", w = 100, align = "RIGHT" },
}

local function ClassColored(rec, text)
	local color = RAID_CLASS_COLORS and rec.classToken and RAID_CLASS_COLORS[rec.classToken]
	if color and color.colorStr then return "|c" .. color.colorStr .. text .. "|r" end
	return text
end

local function Age(t)
	if not t then return ns.Color("grey", "unknown") end
	return ns.MarketData.FormatAge(t)
end

local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

---------------------------------------------------------------- rows
local function CharacterRows(select)
	local rows = {}
	for _, e in ipairs(ns.CharacterManager.List()) do
		local rec, key = e.rec, e.key
		local me = key == ns.CharacterManager.currentKey
		local name = ClassColored(rec, rec.name or key) .. (me and ns.Color("gold", "  (you)") or "") .. ns.Color("grey", "-" .. (rec.realm or "?"))
		local line = ns.CharacterManager.ProfessionLine(rec)
		rows[#rows + 1] = {
			cells = { name = name, level = tostring(rec.level or "?"), gold = rec.gold and ns.FormatMoney(rec.gold, true) or ns.Color("grey", "-"),
				profs = line or ns.Color("grey", "none recorded"), seen = me and "now" or Age(rec.lastSeen) },
			sort = { name = rec.name or key, level = rec.level, gold = rec.gold, profs = line, seen = me and math.huge or rec.lastSeen },
			tip = { Plain(rec.name or key) .. "-" .. (rec.realm or "?"), "Click for details.",
				me and "This is the character you are logged in with." or "Gold and professions are as of the last time this character was logged out." },
			onClick = function() select(key) end,
		}
	end
	return rows
end

local function MaterialRowsFor(go)
	local rows = {}
	for _, r in ipairs(ns.Allocation.Rows()) do
		local who = {}
		for _, h in ipairs(r.hold.holders) do who[#who + 1] = ("%s %d"):format(h.label, h.count) end
		local planColor = ({ Craft = "green", Learn = "gold", Sell = "orange", Hold = "grey", Gather = "blue" })[r.plan.action] or "grey"
		local name = ns.RecipeManager.ItemName(r.id)
		local tip = { name, "Held by:" }
		for _, h in ipairs(r.hold.holders) do
			tip[#tip + 1] = ("  %s: %d (%s)"):format(h.label, h.count, h.key == ns.CharacterManager.currentKey and "now" or ("as of " .. Plain(Age(h.t))))
		end
		tip[#tip + 1] = r.plan.why
		if r.plan.mail then tip[#tip + 1] = r.plan.mail end
		tip[#tip + 1] = "Click for the item details."
		rows[#rows + 1] = {
			cells = { name = name, total = tostring(r.total), who = table.concat(who, ", "),
				plan = ns.Color(planColor, r.plan.text) .. (r.plan.mail and ns.Color("grey", "  *") or ""),
				value = r.value and ns.FormatMoney(r.value) or ns.Color("orange", "no data") },
			sort = { name = name, total = r.total, who = table.concat(who, ", "), plan = r.plan.text, value = r.value },
			tip = tip,
			onClick = function() go("item", r.id) end,
		}
	end
	return rows
end

---------------------------------------------------------------- page
UI.RegisterPage("characters", function(parent)
	local state = { view = "chars", selected = nil, preview = nil }

	local charBtn = UI.Button(parent, "Characters", 100, 22, function() state.view = "chars"; UI.RefreshIfShown() end)
	local matBtn = UI.Button(parent, "Materials", 100, 22, function() state.view = "materials"; UI.RefreshIfShown() end)
	local xferBtn = UI.Button(parent, "Import / Export", 120, 22, function() state.view = "transfer"; UI.RefreshIfShown() end)
	charBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	matBtn:SetPoint("LEFT", charBtn, "RIGHT", 4, 0)
	xferBtn:SetPoint("LEFT", matBtn, "RIGHT", 4, 0)

	local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -28)
	info:SetJustifyH("LEFT")

	-- characters view
	local deleteBtn
	local function Select(key)
		if state.selected ~= key and deleteBtn then deleteBtn.Disarm() end   -- never carry a pending delete to another character
		state.selected = key
		UI.RefreshIfShown()
	end
	local charTable = UI.Table(parent, CHAR_COLS, { sortKey = "gold" })
	charTable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -46)
	charTable.frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -46)
	charTable.frame:SetHeight(190)
	local detail = UI.Panel(parent, "Selected character")
	detail:SetPoint("TOPLEFT", charTable.frame, "BOTTOMLEFT", 0, -6)
	detail:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	detail:SetWidth(370)
	local owners = UI.Panel(parent, "Professions across your characters")
	owners:SetPoint("TOPLEFT", detail, "TOPRIGHT", 6, 0)
	owners:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	deleteBtn = UI.ConfirmButton(detail, "Delete character", 130, 20, "Click again to delete", function()
		local key = state.selected
		local ok, err = ns.CharacterManager.Delete(key)
		if ok then ns.Print("removed " .. key .. " from the character list") else ns.Print(err) end
		state.selected = nil
		UI.RefreshIfShown()
	end)
	deleteBtn:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 10, 8)

	-- materials view
	local matTable = UI.Table(parent, MAT_COLS, { sortKey = "value" })
	matTable.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -46)
	matTable.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	-- transfer view
	local xfer = UI.Panel(parent, "Import / Export")
	xfer:SetAllPoints(parent)
	xfer:ClearAllPoints()
	xfer:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -46)
	xfer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	xfer:SetBody("")
	local function TextBox(w)
		local eb = CreateFrame("EditBox", nil, xfer)
		eb:SetSize(w, 22)
		eb:SetAutoFocus(false)
		if eb.SetMaxLetters then eb:SetMaxLetters(0) end
		if eb.SetFontObject and GameFontHighlight then eb:SetFontObject(GameFontHighlight) end
		if eb.SetTextInsets then eb:SetTextInsets(6, 6, 0, 0) end
		UI.Skin(eb, { 0.05, 0.05, 0.07, 1 })
		eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
		eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
		return eb
	end
	local function Label(text, anchor, dy)
		local fs = xfer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, dy or -8)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		return fs
	end
	local intro = xfer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	intro:SetPoint("TOPLEFT", xfer, "TOPLEFT", 10, -30)
	intro:SetWidth(700)
	intro:SetJustifyH("LEFT")
	intro:SetText("Moves your manual prices and character summaries (name, class, level, gold, professions) between accounts as one line of text. Nothing is sent over the internet.\nScanned prices, recipes, bank and session data are not included.")
	local exportBtn = UI.Button(xfer, "Create export text", 140, 22, function()
		local text, counts = ns.Transfer.Build()
		state.exportText = text
		state.exportInfo = ("%d manual prices and %d characters. Click the box, press Ctrl+A then Ctrl+C."):format(counts.manual, counts.characters)
		UI.RefreshIfShown()
	end)
	exportBtn:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
	local exportBox = TextBox(700)
	exportBox:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -6)
	exportBox:SetScript("OnEditFocusGained", function(self) if self.HighlightText then self:HighlightText() end end)
	local exportInfo = Label("", exportBox, -4)
	local importLabel = Label("Paste export text from another account here:", exportInfo, -18)
	local importBox = TextBox(700)
	importBox:SetPoint("TOPLEFT", importLabel, "BOTTOMLEFT", 0, -6)
	local importInfo = Label("", importBox, -6)
	importInfo:SetWidth(700)
	local applyBtn = UI.ConfirmButton(xfer, "Apply import", 130, 22, "Click again to apply", function()
		local ok, err = ns.Transfer.Apply(state.preview)
		if ok then ns.Print("import applied: " .. ns.Transfer.Summary(state.preview)) else ns.Print(err) end
		state.preview = nil
		importBox:SetText("")
		UI.RefreshIfShown()
	end)
	applyBtn:SetPoint("TOPLEFT", importInfo, "BOTTOMLEFT", 0, -10)
	importBox:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		applyBtn.Disarm()
		state.preview = text:gsub("%s", "") ~= "" and ns.Transfer.Preview(text) or nil
		UI.RefreshIfShown()
	end)

	local widgets = {
		chars = { charTable.frame, detail, owners },
		materials = { matTable.frame },
		transfer = { xfer },
	}

	local function Go(kind, id) UI.market.Show(kind, id) end

	local function Refresh()
		for view, list in pairs(widgets) do
			for _, w in ipairs(list) do if view == state.view then w:Show() else w:Hide() end end
		end
		charBtn:SetActive(state.view == "chars")
		matBtn:SetActive(state.view == "materials")
		xferBtn:SetActive(state.view == "transfer")

		local total, n, oldest = ns.CharacterManager.GoldSummary()
		if state.view == "chars" then
			info:SetText(("Total gold: %s across %d tracked character%s.  %s"):format(ns.FormatMoney(total, true), n, n == 1 and "" or "s",
				ns.Color("grey", "Other characters show their gold from their last logout" .. (oldest and (", oldest " .. Plain(Age(oldest))) or "") .. ".")))
			charTable:SetData(CharacterRows(Select))

			local sel = state.selected and ns.db.characters[state.selected]
			if state.selected and not sel then state.selected = nil end
			local me = state.selected == ns.CharacterManager.currentKey
			if sel then
				local L = { ClassColored(sel, sel.name or state.selected) .. "-" .. (sel.realm or "?"),
					("Level %s %s"):format(tostring(sel.level or "?"), sel.class or "?"),
					"Gold: " .. (sel.gold and ns.FormatMoney(sel.gold, true) or "unknown"),
					"Last seen: " .. (me and "now" or Plain(Age(sel.lastSeen))), "" }
				L[#L + 1] = ns.Color("gold", "Professions")
				for _, p in ipairs(sel.professions or {}) do L[#L + 1] = ("  %s  %d / %d"):format(p.name, p.skill or 0, p.maxSkill or 0) end
				if not sel.professions or #sel.professions == 0 then L[#L + 1] = ns.Color("grey", "  none recorded") end
				local mine = #ns.GoldTracker.List(state.selected)
				L[#L + 1] = ""
				L[#L + 1] = ("Finished gold sessions: %d.  Bank record: %s."):format(mine, sel.bank and Plain(Age(sel.bank.t)) or "none")
				if me then L[#L + 1] = ns.Color("grey", "You are logged in as this character, so it cannot be deleted.") end
				detail:SetTitle("Selected character")
				detail:SetBody(table.concat(L, "\n"))
				if me then deleteBtn:Hide() else deleteBtn:Show() end
			else
				detail:SetTitle("Selected character")
				detail:SetBody(ns.Color("grey", "Click a character above to see details or remove it from the list.\nDeleting only removes the saved copy; the character itself is not touched, and logging in with it adds it back."))
				deleteBtn:Hide()
			end

			local map, names = ns.CharacterManager.ProfessionOwners(), {}
			for prof in pairs(map) do names[#names + 1] = prof end
			table.sort(names)
			local L = {}
			for _, prof in ipairs(names) do L[#L + 1] = ("%s  %s"):format(ns.Color("white", prof), ns.Color("grey", table.concat(map[prof], ", "))) end
			if #L == 0 then L[1] = ns.Color("grey", "No professions recorded yet.") end
			owners:SetBody(table.concat(L, "\n"))
		elseif state.view == "materials" then
			info:SetText(ns.Color("grey", "Materials held by your characters and who should use them. * means some must be mailed first. Other characters' bags are as of their last logout."))
			local rows = MaterialRowsFor(Go)
			matTable:SetData(rows)
		else
			info:SetText("")
			exportBox:SetText(state.exportText or "")
			exportInfo:SetText(ns.Color("grey", state.exportInfo or "Press the button to create text you can paste into another account."))
			local pv = state.preview
			if not pv then
				importInfo:SetText(ns.Color("grey", "Nothing pasted yet."))
				applyBtn:Hide()
			elseif not pv.ok then
				importInfo:SetText(ns.Color("red", pv.err))
				applyBtn:Hide()
			else
				importInfo:SetText("Ready: " .. ns.Transfer.Summary(pv) .. "\n" .. ns.Color("grey", "Newer data wins. The character you are logged in with is never changed."))
				local changes = pv.newManual + pv.updatedManual + pv.newChars + pv.updatedChars
				if changes > 0 then applyBtn:Show() else applyBtn:Hide() end
			end
		end
	end

	UI.tabHome.characters = function() state.view = "chars" end
	UI.characters = { Debug = state, Select = Select }
	return { frame = parent, Refresh = Refresh }
end)
