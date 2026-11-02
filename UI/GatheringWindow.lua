-- Goblin Advisor: Gathering tab
-- Which materials are worth collecting, ranked by their current scanned price, for the
-- gathering professions this character has. Advice only; nothing is automated.
local _, ns = ...
local UI = ns.UI

local COLS = {
	{ key = "prof", label = "Profession", w = 84 },
	{ key = "name", label = "Material", w = 170 },
	{ key = "price", label = "Price", w = 92, align = "RIGHT" },
	{ key = "avg", label = "Recent avg", w = 92, align = "RIGHT" },
	{ key = "change", label = "Change", w = 60, align = "RIGHT" },
	{ key = "owned", label = "Owned", w = 54, align = "RIGHT" },
	{ key = "usedIn", label = "In recipes", w = 70, align = "RIGHT" },
}

local function Pct(x)
	if x == nil then return ns.Color("grey", "-") end
	local color = x > 0.05 and "green" or (x < -0.05 and "red" or "grey")
	return ns.Color(color, ("%+d%%"):format(math.floor(x * 100 + (x >= 0 and 0.5 or -0.5))))
end

UI.RegisterPage("gathering", function(parent)
	local note = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, 0)
	note:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, 0)
	note:SetJustifyH("LEFT")
	note:SetJustifyV("TOP")
	note:SetSpacing(2)

	local tbl = UI.Table(parent, COLS, { sortKey = "price" })
	tbl.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -62)
	tbl.frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local function Refresh()
		local g = ns.GatheringAdvisor.Suggest()
		local lines = {}
		local zone = GetZoneText and ns.Safe(GetZoneText())
		if #g.professions == 0 then
			if not g.character then
				lines[1] = ns.Color("grey", "No character data yet.")
			elseif g.anyProfession then
				lines[1] = ns.Color("orange", "This character has no Mining, Herbalism or Skinning.")
				lines[2] = ns.Color("grey", "(Profession names are matched in English; on another language client this may miss.)")
			else
				lines[1] = ns.Color("orange", "This character has no professions yet.")
				lines[2] = ns.Color("grey", "Mining, Herbalism and Skinning cost nothing to start and are the usual first gold earners.")
			end
		else
			local empty = true
			for _, p in ipairs(g.professions) do if #p.items > 0 then empty = false end end
			lines[1] = "Ranked by current scanned price. " .. (empty and ns.Color("orange", "No priced gatherable materials yet: scan the Auction House after opening your profession windows.") or "")
		end
		lines[#lines + 1] = ns.Color("grey", "Not available from the game, so not shown: zone spawns, required skill, demand and competition." .. (zone and ("  You are in " .. zone .. ".") or ""))
		note:SetText(table.concat(lines, "\n"))

		local rows = {}
		for _, p in ipairs(g.professions) do
			for _, it in ipairs(p.items) do
				local name = ns.RecipeManager.ItemName(it.id)
				rows[#rows + 1] = {
					cells = {
						prof = p.name, name = name, price = ns.FormatMoney(it.price),
						avg = it.avg and ns.FormatMoney(it.avg) or ns.Color("grey", "-"),
						change = Pct(it.change), owned = it.owned and tostring(it.owned) or ns.Color("grey", "-"),
						usedIn = it.usedIn > 0 and tostring(it.usedIn) or ns.Color("grey", "0"),
					},
					sort = { name = name, prof = p.name, price = it.price, avg = it.avg, change = it.change, owned = it.owned, usedIn = it.usedIn },
					tip = { name, "Price is the lowest Auction House listing at your last scan" .. (it.stale and " (STALE: over 3 days old)." or "."),
						("Used in %d recipes you have recorded with a complete price."):format(it.usedIn) },
				}
			end
		end
		tbl:SetData(rows)
	end

	return { frame = parent, Refresh = Refresh }
end)
