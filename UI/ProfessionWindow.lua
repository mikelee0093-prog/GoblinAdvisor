-- Goblin Advisor: Professions tab
-- Left: every profession we know about. Right: details for the selected one, or two side by
-- side in compare mode. All numbers are counted from recorded recipes; anything that needs
-- prices says "no data" until Phase 3.
local _, ns = ...
local UI = ns.UI

local PAGE = 8          -- recipes per page
local MAX_BUTTONS = 14
local LIST_W = 176

local function Skill(s)
	local c = ns.CharacterManager.GetCurrent()
	if not c then return nil end
	for _, p in ipairs(c.professions or {}) do
		if p.name == s.name then return p end
	end
end

local function ReagentText(rec)
	local parts = {}
	for _, slot in ipairs(rec.reagents) do
		parts[#parts + 1] = slot.qty .. "x " .. ns.RecipeManager.ItemName(slot.ids[1])
	end
	if #parts == 0 then return ns.Color("grey", "no reagents recorded") end
	return table.concat(parts, ", ")
end

-- Text for one profession panel.
local function Describe(s, page)
	if not s then return ns.Color("grey", "Pick a profession on the left.") end
	local L = {}
	local mine = Skill(s)
	if mine then
		L[#L + 1] = ("Your skill: %s / %s"):format(ns.Color("white", mine.skill or 0), mine.maxSkill or 0)
	else
		L[#L + 1] = ns.Color("grey", "Current character does not have this profession.")
	end
	for _, c in ipairs(s.characters) do
		if not (mine and c.key == ns.CharacterManager.currentKey) then
			L[#L + 1] = ns.Color("grey", ("%s: %s / %s"):format(c.name or "?", c.skill or 0, c.maxSkill or 0))
		end
	end
	if s.recipes == 0 then
		L[#L + 1] = ""
		L[#L + 1] = ns.Color("orange", "No recipes recorded yet.")
		L[#L + 1] = ns.Color("grey", "Open this profession's window in game (default key: P) and wait a moment.")
		return table.concat(L, "\n")
	end

	local known = ns.ProfessionManager.CurrentKnown(s.name)
	local knownCount = 0
	for _ in pairs(known or {}) do knownCount = knownCount + 1 end
	L[#L + 1] = ("Recipes recorded: %s%s"):format(ns.Color("white", s.recipes),
		known and ("  (you know " .. knownCount .. ")") or "")
	L[#L + 1] = ("Materials: %d distinct, %.1f per recipe"):format(s.distinctMaterials, s.avgReagents or 0)
	local pp = ns.ProfitCalculator.Profession(s.name)
	if pp and pp.score then
		L[#L + 1] = ("Profit, best %d recipes avg: %s per craft  %s"):format(math.min(5, #pp.priced), ns.FormatMoney(pp.score),
			ns.Color("grey", ("(%d of %d priced)"):format(#pp.priced, pp.total)))
	else
		L[#L + 1] = "Profit: " .. ns.Color("orange", "no data") .. ns.Color("grey", pp and (" (" .. #pp.priced .. " of " .. pp.total .. " recipes priced; scan the Auction House)") or " (scan the Auction House)")
	end
	L[#L + 1] = ""
	L[#L + 1] = ns.Color("gold", "Most used materials")
	for _, m in ipairs(s.topMaterials) do
		L[#L + 1] = ("  %s  %s"):format(ns.RecipeManager.ItemName(m.id), ns.Color("grey", "(" .. m.uses .. " recipes)"))
	end

	local recipes = ns.ProfessionManager.Recipes(s.name, known)
	local pages = math.max(1, math.ceil(#recipes / PAGE))
	page = math.min(math.max(page, 1), pages)
	L[#L + 1] = ""
	L[#L + 1] = ns.Color("gold", ("Recipes  page %d/%d"):format(page, pages)) .. ns.Color("grey", "   * = you know it")
	for i = (page - 1) * PAGE + 1, math.min(#recipes, page * PAGE) do
		local r = recipes[i]
		local e = ns.ProfitCalculator.Evaluate(r.id, r.rec)
		local profit = e and e.profit and (" -> " .. ns.Color(e.profit > 0 and "green" or "red", (e.profit > 0 and "+" or "") .. ns.FormatMoney(e.profit))) or ""
		L[#L + 1] = ("%s%s: %s%s"):format(r.known and ns.Color("green", "* ") or "  ", r.rec.name, ReagentText(r.rec), profit)
	end
	return table.concat(L, "\n")
end

local function CompareText(a, b)
	local L = { ns.Color("gold", "Side by side") }
	local function V(v, note, money)
		if v == nil then return ns.Color("orange", "no data") .. (note and ns.Color("grey", " (" .. note .. ")") or "") end
		if money then return ns.FormatMoney(v) end
		return ns.Color("white", v)
	end
	for _, row in ipairs(ns.ProfessionManager.Compare(a, b)) do
		L[#L + 1] = ("%s:  %s  |  %s"):format(row.label, V(row.a, row.note, row.money), V(row.b, row.note, row.money))
	end
	return table.concat(L, "\n")
end

UI.RegisterPage("professions", function(parent)
	local state = { a = nil, b = nil, compare = false, page = 1, list = {} }

	local left = UI.Panel(parent, "Professions")
	left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
	left:SetWidth(LIST_W)

	local panelA = UI.Panel(parent, "")
	local panelB = UI.Panel(parent, "")
	local cmp = UI.Panel(parent, "Compare")

	local buttons = {}
	for i = 1, MAX_BUTTONS do
		local b = UI.Button(left, "", LIST_W - 16, 20, function()
			local s = state.list[i]
			if not s then return end
			if state.compare and state.a and s.name ~= state.a then state.b = s.name else state.a = s.name end
			state.page = 1
			UI.RefreshIfShown()
		end)
		b:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -28 - (i - 1) * 22)
		buttons[i] = b
	end

	local toggle = UI.Button(parent, "Compare: off", 110, 22, function()
		state.compare = not state.compare
		if not state.compare then state.b = nil end
		UI.RefreshIfShown()
	end)
	local prev = UI.Button(parent, "< Page", 70, 22, function() state.page = math.max(1, state.page - 1); UI.RefreshIfShown() end)
	local nxt = UI.Button(parent, "Page >", 70, 22, function() state.page = state.page + 1; UI.RefreshIfShown() end)
	local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetJustifyH("LEFT")

	local function Layout()
		local x = LIST_W + 6
		toggle:ClearAllPoints(); toggle:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
		prev:ClearAllPoints(); prev:SetPoint("LEFT", toggle, "RIGHT", 8, 0)
		nxt:ClearAllPoints(); nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		note:ClearAllPoints(); note:SetPoint("LEFT", nxt, "RIGHT", 10, 0)

		panelA:ClearAllPoints(); panelB:ClearAllPoints(); cmp:ClearAllPoints()
		local top = -28
		if state.compare and state.b then
			local w = parent:GetWidth() - x
			local half = math.floor((w - 6) / 2)
			local cmpH = 150
			panelA:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
			panelA:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, cmpH + 6)
			panelA:SetWidth(half)
			panelB:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top)
			panelB:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, cmpH + 6)
			panelB:SetWidth(half)
			cmp:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
			cmp:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
			cmp:SetHeight(cmpH)
			panelB:Show(); cmp:Show()
		else
			panelA:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
			panelA:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
			panelB:Hide(); cmp:Hide()
		end
	end
	parent:SetScript("OnSizeChanged", Layout)

	local function Find(list, name)
		for _, s in ipairs(list) do if s.name == name then return s end end
	end

	local function Refresh()
		local list = ns.ProfessionManager.Summaries()
		state.list = list

		-- Default selection: the first profession the current character has, else the first one.
		if not (state.a and Find(list, state.a)) then
			state.a = nil
			local cur = ns.CharacterManager.GetCurrent()
			local first = cur and cur.professions and cur.professions[1]
			if first and Find(list, first.name) then state.a = first.name end
			state.a = state.a or (list[1] and list[1].name)
		end
		if state.b and not Find(list, state.b) then state.b = nil end

		for i, b in ipairs(buttons) do
			local s = list[i]
			if s then
				b.text:SetText(("%s  %s"):format(s.name, ns.Color("grey", "(" .. s.recipes .. ")")))
				b:SetActive(s.name == state.a or s.name == state.b)
				b:Show()
			else
				b:Hide()
			end
		end
		left:SetBody(#list == 0 and ns.Color("grey", "\n\nNo professions yet.\nLearn one, or open a profession window.") or "")

		toggle.text:SetText(state.compare and "Compare: on" or "Compare: off")
		toggle:SetActive(state.compare)
		note:SetText(state.compare and (state.b and "" or "Click a second profession to compare.") or "")
		Layout()

		local sa, sb = Find(list, state.a), Find(list, state.b)
		panelA:SetTitle(sa and sa.name or "Profession")
		panelA:SetBody(Describe(sa, state.page))
		if state.compare and sb then
			panelB:SetTitle(sb.name)
			panelB:SetBody(Describe(sb, state.page))
			cmp:SetTitle(("Compare: %s  vs  %s"):format(sa and sa.name or "?", sb.name))
			cmp:SetBody(CompareText(sa, sb))
		end
	end

	return { frame = parent, Refresh = Refresh }
end)
