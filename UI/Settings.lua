-- Goblin Advisor: Settings page
local _, ns = ...
local UI = ns.UI

UI.RegisterPage("settings", function(parent)
	local panel = UI.Panel(parent, "Settings")
	panel:SetAllPoints(parent)
	panel:SetBody("")

	local demo = UI.Checkbox(panel, "Show labelled DEMO data where there is no real data",
		function() return ns.db.settings.showDemo end,
		function(v) ns.db.settings.showDemo = v and true or false; UI.RefreshIfShown() end)
	demo:SetPoint("TOPLEFT", 14, -34)

	local debug = UI.Checkbox(panel, "Print debug messages to chat",
		function() return ns.db.settings.debug end,
		function(v) ns.db.settings.debug = v and true or false end)
	debug:SetPoint("TOPLEFT", demo, "BOTTOMLEFT", 0, -8)

	local icons = UI.Checkbox(panel, "Show coin icons next to gold values",
		function() return ns.db.settings.coinIcons ~= false end,
		function(v) ns.db.settings.coinIcons = v and true or false; UI.RefreshIfShown() end)
	icons:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 0, -8)

	local auto = UI.Checkbox(panel, "Request an Auction House scan when I open it (read only)",
		function() return ns.db.settings.autoScan ~= false end,
		function(v) ns.db.settings.autoScan = v and true or false end)
	auto:SetPoint("TOPLEFT", icons, "BOTTOMLEFT", 0, -8)

	local unit = UI.Checkbox(panel, "Scan buyout prices are already per unit (leave off unless /ga scan debug says so)",
		function() return ns.db.settings.scanPriceIsUnit == true end,
		function(v) ns.db.settings.scanPriceIsUnit = v and true or false end)
	unit:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -8)

	local reset = UI.Button(panel, "Reset window position", 160, 22, function() UI.ResetWindow() end)
	reset:SetPoint("TOPLEFT", unit, "BOTTOMLEFT", 0, -16)

	local info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", reset, "BOTTOMLEFT", 0, -20)
	info:SetJustifyH("LEFT")
	info:SetText(ns.Color("grey", "Slash commands: /ga help\nData is stored in GoblinAdvisorDB (account-wide SavedVariables)."))

	return { frame = panel, Refresh = function() demo:Refresh(); debug:Refresh(); icons:Refresh(); auto:Refresh(); unit:Refresh() end }
end)
