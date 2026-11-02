-- Goblin Advisor: shared widgets
-- UI.Table: a small sortable, pageable table with hover tooltips.
--   cols  = { { key, label, w, align }, ... }
--   rows  = { { cells = { key = "text" }, sort = { key = value }, tip = { "line", ... }, onClick = fn }, ... }
local _, ns = ...
local UI = ns.UI

local ROW_H = 18
local MAX_ROWS = 40

local function ShowTip(row)
	if not (row.tip and GameTooltip) then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:ClearLines()
	for i, line in ipairs(row.tip) do
		if i == 1 then GameTooltip:AddLine(line, 1, 0.82, 0) else GameTooltip:AddLine(line, 1, 1, 1, true) end
	end
	if row.item and row.item.onClick then GameTooltip:AddLine("Click for details", 0.6, 0.6, 0.6) end
	GameTooltip:Show()
end

local function Less(a, b, desc)
	if a == nil and b == nil then return false end
	if a == nil then return false end          -- missing values always sort last
	if b == nil then return true end
	if a == b then return false end
	if desc then return a > b end
	return a < b
end

function UI.Table(parent, cols, opts)
	opts = opts or {}
	local t = { cols = cols, data = {}, page = 1, sortKey = opts.sortKey, desc = opts.desc ~= false }
	local frame = CreateFrame("Frame", nil, parent)
	t.frame = frame

	local totalW, x = 0, 0
	local heads = {}
	for i, c in ipairs(cols) do
		c.x = x
		local b = UI.Button(frame, c.label, c.w, 18, function()
			if t.sortKey == c.key then t.desc = not t.desc else t.sortKey = c.key; t.desc = true end
			t.page = 1
			t:Render()
		end)
		b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
		heads[i] = b
		x = x + c.w + 2
	end
	totalW = x

	t.rows = {}
	for r = 1, MAX_ROWS do
		local row = CreateFrame("Frame", nil, frame)
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22 - (r - 1) * ROW_H)
		row:SetSize(totalW, ROW_H - 1)
		row:EnableMouse(true)
		row.fs = {}
		for i, c in ipairs(cols) do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("LEFT", row, "LEFT", c.x + 3, 0)
			fs:SetWidth(c.w - 6)
			fs:SetJustifyH(c.align or "LEFT")
			if fs.SetWordWrap then fs:SetWordWrap(false) end
			row.fs[i] = fs
		end
		row.hl = row:CreateTexture(nil, "BACKGROUND")
		row.hl:SetAllPoints(row)
		row.hl:SetColorTexture(1, 1, 1, 0.08)
		row.hl:Hide()
		row:SetScript("OnEnter", function()
			if row.item and row.item.onClick then row.hl:Show() end
			ShowTip(row)
		end)
		row:SetScript("OnLeave", function()
			row.hl:Hide()
			if GameTooltip then GameTooltip:Hide() end
		end)
		row:SetScript("OnMouseUp", function()
			local it = row.item
			if it and it.onClick then it.onClick(it) end
		end)
		row:Hide()
		t.rows[r] = row
	end

	t.pager = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	t.pager:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 2)
	t.prev = UI.Button(frame, "<", 22, 18, function() t.page = math.max(1, t.page - 1); t:Render() end)
	t.next = UI.Button(frame, ">", 22, 18, function() t.page = t.page + 1; t:Render() end)
	t.prev:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 0)
	t.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		t.page = math.max(1, t.page + (delta > 0 and -1 or 1))
		t:Render()
	end)

	function t:VisibleRows()
		local h = frame:GetHeight() or 0
		local n = math.floor((h - 44) / ROW_H)
		if n < 3 then n = 8 end
		return math.min(n, MAX_ROWS)
	end

	function t:SetData(rows) self.data = rows or {}; self:Render() end

	function t:Render()
		local data = self.data
		if self.sortKey then
			local key, desc = self.sortKey, self.desc
			table.sort(data, function(a, b)
				local va, vb = a.sort and a.sort[key], b.sort and b.sort[key]
				if va == vb then return (a.sort and a.sort.name or "") < (b.sort and b.sort.name or "") end
				return Less(va, vb, desc)
			end)
		end
		local per = self:VisibleRows()
		local pages = math.max(1, math.ceil(#data / per))
		self.page = math.min(math.max(self.page, 1), pages)
		local first = (self.page - 1) * per
		for r = 1, MAX_ROWS do
			local row, item = self.rows[r], data[first + r]
			if r <= per and item then
				for i, c in ipairs(cols) do row.fs[i]:SetText(item.cells[c.key] or "") end
				row.tip = item.tip
				row.item = item
				row:Show()
			else
				row.tip = nil
				row.item = nil
				row:Hide()
			end
		end
		self.pager:SetText(("%d rows   page %d/%d   (click a heading to sort)"):format(#data, self.page, pages))
	end

	return t
end

-- A text box with grey placeholder text. onChange(text) runs on every edit.
function UI.SearchBox(parent, w, placeholder, onChange)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetSize(w, 22)
	eb:SetAutoFocus(false)
	if eb.SetMaxLetters then eb:SetMaxLetters(40) end
	if eb.SetFontObject and GameFontHighlight then eb:SetFontObject(GameFontHighlight) end
	if eb.SetTextInsets then eb:SetTextInsets(6, 6, 0, 0) end
	UI.Skin(eb, { 0.05, 0.05, 0.07, 1 })
	local hint = eb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("LEFT", eb, "LEFT", 7, 0)
	hint:SetText(placeholder or "")
	local function Sync(self)
		local text = self:GetText() or ""
		if text == "" and not (self.HasFocus and self:HasFocus()) then hint:Show() else hint:Hide() end
		return text
	end
	eb:SetScript("OnTextChanged", function(self) onChange(Sync(self)) end)
	eb:SetScript("OnEditFocusGained", function(self) hint:Hide() end)
	eb:SetScript("OnEditFocusLost", function(self) Sync(self) end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	eb:SetScript("OnEscapePressed", function(self)
		if (self:GetText() or "") ~= "" then self:SetText("") end
		self:ClearFocus()
	end)
	return eb
end


-- A button that needs two clicks. The first click changes its label to confirmLabel and arms it for
-- a few seconds; a second click while armed runs onConfirm. Waiting, or hiding the page, disarms it.
local CONFIRM_SECONDS = 4
function UI.ConfirmButton(parent, label, w, h, confirmLabel, onConfirm)
	local b = UI.Button(parent, label, w, h)
	local armedAt, token = nil, 0
	function b:IsArmed() return armedAt ~= nil and (ns.MarketData.Now() - armedAt) < CONFIRM_SECONDS end
	local function Disarm() armedAt = nil; token = token + 1; b.text:SetText(label) end
	b.Disarm = Disarm
	b:SetScript("OnClick", function()
		if b:IsArmed() then Disarm(); onConfirm(); return end
		armedAt = ns.MarketData.Now()
		token = token + 1
		local mine = token
		b.text:SetText(confirmLabel)
		-- only the label is restored by the timer; whether the button is armed is decided by the clock above
		C_Timer.After(CONFIRM_SECONDS, function() if token == mine then b.text:SetText(label) end end)
	end)
	b:SetScript("OnHide", Disarm)
	return b
end
