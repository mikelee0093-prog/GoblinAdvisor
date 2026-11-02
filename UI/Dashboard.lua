-- Goblin Advisor: Dashboard page
-- REAL data: this character, tracked characters, price-based recommendations, profession
-- outlook, materials. DEMO data (labelled) only appears when there is no real data for a
-- panel AND demo is switched on with /ga demo on.
local _, ns = ...
local UI = ns.UI

local ROW_H = 150

local function ClassColored(rec)
	local name = rec.class or "Unknown class"
	local color = RAID_CLASS_COLORS and rec.classToken and RAID_CLASS_COLORS[rec.classToken]
	if color and color.colorStr then return "|c" .. color.colorStr .. name .. "|r" end
	return name
end

local function CharacterText()
	local rec = ns.CharacterManager.GetCurrent()
	if not rec then return ns.Color("grey", "No character data yet.") end
	local lines = {}
	lines[#lines + 1] = ns.Color("white", rec.name or "?") .. "-" .. (rec.realm or "?")
	lines[#lines + 1] = ("Level %s %s"):format(tostring(rec.level or "?"), ClassColored(rec))
	local stage, why = ns.Recommendations.Stage()
	if stage then lines[#lines + 1] = ("Stage: %s %s"):format(ns.Color("gold", ns.Recommendations.STAGE_LABEL[stage]), ns.Color("grey", "(" .. why .. ")")) end
	lines[#lines + 1] = "Gold: " .. ns.FormatMoney(rec.gold)
	local delta = ns.CharacterManager.SessionDelta()
	if delta then
		local color = delta > 0 and "green" or (delta < 0 and "red" or "grey")
		lines[#lines + 1] = "Since login: " .. ns.Color(color, (delta > 0 and "+" or "")) .. ns.FormatMoney(delta)
	end
	lines[#lines + 1] = ns.Color("gold", "Professions")
	if ns.CharacterManager.professionsReadable == false then
		lines[#lines + 1] = ns.Color("orange", "Could not read professions on this client (see /ga status).")
	elseif not rec.professions or #rec.professions == 0 then
		lines[#lines + 1] = ns.Color("grey", "None found.")
	else
		for _, p in ipairs(rec.professions) do
			lines[#lines + 1] = ("%s  %d / %d"):format(p.name, p.skill or 0, p.maxSkill or 0)
		end
	end
	return table.concat(lines, "\n")
end

local function AccountText()
	local CM = ns.CharacterManager
	local lines = {}
	local total, n, oldest = CM.GoldSummary()
	lines[#lines + 1] = ("Total gold: %s  %s"):format(ns.FormatMoney(total), ns.Color("grey", ("(%d character%s)"):format(n, n == 1 and "" or "s")))
	local list = CM.List()
	for i = 1, math.min(4, #list) do
		local rec = list[i].rec
		local color = RAID_CLASS_COLORS and rec.classToken and RAID_CLASS_COLORS[rec.classToken]
		local nm = rec.name or list[i].key
		if color and color.colorStr then nm = "|c" .. color.colorStr .. nm .. "|r" end
		lines[#lines + 1] = ("  %s  %s%s"):format(nm,
			rec.gold and ns.FormatMoney(rec.gold) or ns.Color("grey", "-"),
			list[i].key == CM.currentKey and "" or ns.Color("grey", "  " .. ns.MarketData.FormatAge(rec.lastSeen)))
	end
	if #list > 4 then lines[#lines + 1] = ns.Color("grey", ("  +%d more on the Characters tab"):format(#list - 4)) end
	lines[#lines + 1] = ns.Color("grey", "Others show gold from their last logout.")
	local value, priced, unpriced = ns.Recommendations.InventoryValue()
	if priced > 0 then
		lines[#lines + 1] = "Materials on this character: " .. ns.FormatMoney(value)
		lines[#lines + 1] = ns.Color("grey", ("%d item types priced%s"):format(priced, unpriced > 0 and (", " .. unpriced .. " not priced (not counted)") or ""))
	elseif unpriced > 0 then
		lines[#lines + 1] = "Materials owned: " .. ns.Color("orange", "no prices yet")
	else
		lines[#lines + 1] = "Materials owned: " .. ns.Color("grey", "none found, or no recipes recorded yet")
	end
	local s = ns.db.activeSession
	if s then
		local snap = ns.GoldTracker.Snapshot(s)
		lines[#lines + 1] = ""
		lines[#lines + 1] = ns.Color("green", "Session running ") .. ns.GoldTracker.FormatDuration(snap.seconds)
	end
	return table.concat(lines, "\n")
end

local function Real(amount, unit)
	return ns.FormatMoney(amount) .. " " .. ns.Color("grey", unit)
end

local function ActivitiesText()
	local list = ns.Recommendations.Activities()
	if #list == 0 then return nil end
	local lines = {}
	for _, a in ipairs(list) do
		lines[#lines + 1] = ("%s\n   %s  %s"):format(a.text, Real(a.amount, a.unit), ns.Color("grey", "(" .. a.basis .. ")"))
	end
	return table.concat(lines, "\n")
end

local OUTLOOK_HELP = "How much a typical craft earns in each profession: the average profit of its 5 best recipes that have prices, after the 5% AH cut. Higher is better. It looks at every recorded recipe, whether or not you know it."

local function ProfessionText()
	local ranking = ns.Recommendations.ProfessionRanking()
	if #ranking == 0 then return nil end
	local anyScore = false
	for _, r in ipairs(ranking) do if r.score then anyScore = true end end
	if not anyScore then
		-- recipes exist but not enough prices: say so rather than ranking on nothing
		local lines = { ns.Color("orange", "Not enough price data to rank professions yet."),
			ns.Color("grey", "A profession needs at least 3 priced recipes to get a score.") }
		for i = 1, math.min(5, #ranking) do
			local r = ranking[i]
			lines[#lines + 1] = ("%s  %s"):format(r.name, ns.Color("grey", ("(%d of %d recipes priced)"):format(r.priced, r.total)))
		end
		return table.concat(lines, "\n")
	end
	local lines = { ns.Color("grey", OUTLOOK_HELP), "" }
	for i = 1, math.min(7, #ranking) do
		local r = ranking[i]
		if r.score then
			local c = r.score > 0 and "green" or "red"
			lines[#lines + 1] = ("%s  %s %s%s"):format(ns.Color(c, r.name), ns.FormatMoney(r.score), ns.Color("grey", "per craft"), r.mine and ns.Color("gold", "  (your profession)") or "")
			lines[#lines + 1] = "   " .. ns.Color("grey", ("based on %d of %d recipes with prices"):format(r.priced, r.total))
		else
			lines[#lines + 1] = ("%s  %s"):format(r.name, ns.Color("grey", ("no score: only %d of %d recipes priced, needs 3"):format(r.priced, r.total)))
		end
	end
	return table.concat(lines, "\n")
end

local function MaterialsText()
	local rows = {}
	for _, id in ipairs(ns.Recommendations.MaterialIDs()) do
		local owned = ns.GatheringAdvisor.Owned(id)
		local st = owned and owned > 0 and ns.MarketData.GetStats(id)
		if st then rows[#rows + 1] = { id = id, owned = owned, value = st.price * owned } end
	end
	if #rows == 0 then return nil end
	table.sort(rows, function(a, b) if a.value ~= b.value then return a.value > b.value end return a.id < b.id end)
	local lines = {}
	for i = 1, math.min(6, #rows) do
		local r = rows[i]
		local action, why = ns.Recommendations.MaterialAction(r.id)
		local color = ({ Sell = "orange", Hold = "grey", Gather = "blue", Craft = "green" })[action] or "white"
		lines[#lines + 1] = ("%s x%d   %s   %s  %s"):format(ns.RecipeManager.ItemName(r.id), r.owned, ns.FormatMoney(r.value),
			ns.Color(color, action or "?"), ns.Color("grey", why or ""))
	end
	return table.concat(lines, "\n")
end

local function DemoActivities()
	local lines = { ns.Color("orange", "DEMO: sample numbers, not real market data") }
	for _, a in ipairs(ns.Demo.activities) do
		lines[#lines + 1] = ("%s\n   %s per hour (demo)"):format(a.name, ns.FormatMoney(a.perHour))
	end
	return table.concat(lines, "\n")
end

local function DemoProfessions()
	local lines = { ns.Color("orange", "DEMO: sample ratings, not real market data") }
	for _, p in ipairs(ns.Demo.professions) do
		lines[#lines + 1] = ("%s  %s"):format(ns.Color(p.rating == "green" and "green" or (p.rating == "red" and "red" or "orange"), p.name), ns.Color("grey", "(" .. p.note .. ")"))
	end
	return table.concat(lines, "\n")
end

local function DemoMaterials()
	local lines = { ns.Color("orange", "DEMO: sample prices, not real market data") }
	local arrows = { up = ns.Color("green", "rising"), down = ns.Color("red", "falling"), flat = ns.Color("grey", "flat") }
	for _, m in ipairs(ns.Demo.materials) do
		lines[#lines + 1] = ("%s   %s   %s   suggested: %s"):format(m.name, ns.FormatMoney(m.price), arrows[m.trend] or "", m.action)
	end
	return table.concat(lines, "\n")
end

local HINT_RECIPES = "No recipes recorded yet.\nOpen each profession window (default key P) once."
local HINT_PRICES = "No prices yet.\nOpen the Auction House and let it scan (or use /ga scan)."

UI.RegisterPage("dashboard", function(parent)
	local charPanel = UI.Panel(parent, "Current character")
	local acctPanel = UI.Panel(parent, "Account (tracked characters)")
	local actPanel = UI.Panel(parent, "Recommended activities")
	local profPanel = UI.Panel(parent, "Profession outlook")
	local matPanel = UI.Panel(parent, "Materials you hold")

	local function Layout()
		local w = parent:GetWidth()
		local half = math.floor((w - 6) / 2)
		for _, p in ipairs({ charPanel, acctPanel, actPanel, profPanel }) do p:SetWidth(half); p:SetHeight(ROW_H) end
		charPanel:ClearAllPoints(); charPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
		acctPanel:ClearAllPoints(); acctPanel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
		actPanel:ClearAllPoints(); actPanel:SetPoint("TOPLEFT", charPanel, "BOTTOMLEFT", 0, -6)
		profPanel:ClearAllPoints(); profPanel:SetPoint("TOPRIGHT", acctPanel, "BOTTOMRIGHT", 0, -6)
		matPanel:ClearAllPoints()
		matPanel:SetPoint("TOPLEFT", actPanel, "BOTTOMLEFT", 0, -6)
		matPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
	end
	parent:SetScript("OnSizeChanged", Layout)
	Layout()

	local function Fill(panel, title, real, demo, hint)
		if real then
			panel:SetTitle(title)
			panel:SetBody(real)
		elseif ns.db.settings.showDemo then
			panel:SetTitle(title .. " " .. ns.Color("orange", "[DEMO]"))
			panel:SetBody(demo())
		else
			panel:SetTitle(title)
			panel:SetBody(ns.Color("grey", hint))
		end
	end

	local function Refresh()
		charPanel:SetBody(CharacterText())
		acctPanel:SetBody(AccountText())
		local haveRecipes = ns.RecipeManager.Count() > 0
		local hint = haveRecipes and HINT_PRICES or HINT_RECIPES
		Fill(actPanel, "Recommended activities", ActivitiesText(), DemoActivities, hint)
		Fill(profPanel, "Profession outlook", ProfessionText(), DemoProfessions, haveRecipes and HINT_PRICES or HINT_RECIPES)
		Fill(matPanel, "Materials you hold", MaterialsText(), DemoMaterials, "Nothing to show: needs priced materials in your bags or banks.\n" .. hint)
	end

	return { frame = parent, Refresh = Refresh }
end)
