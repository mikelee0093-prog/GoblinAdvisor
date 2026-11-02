-- Goblin Advisor: Core
-- Namespace, logging, event dispatch, slash commands and start-up order.
-- The loader passes (addonName, ns) as varargs to every Lua file listed in the .toc.
local addonName, ns = ...

ns.name = addonName
ns.PREFIX = "|cffffd100Goblin Advisor|r:"

local function GetMeta(field)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(addonName, field)
	end
	if GetAddOnMetadata then return GetAddOnMetadata(addonName, field) end
end
ns.version = GetMeta("Version") or "dev"

---------------------------------------------------------------- helpers
ns.colors = {
	gold = "ffd100", green = "33ff66", red = "ff5555", orange = "ff9933",
	grey = "9d9d9d", blue = "66ccff", white = "ffffff",
}

function ns.Color(name, text)
	return "|cff" .. (ns.colors[name] or name) .. tostring(text) .. "|r"
end

-- Some values on this client can be "secret" (unreadable by addons). Treat them as missing.
function ns.Safe(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function Commas(n)
	local s, k = tostring(math.floor(n)), nil
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

-- Coin icons. We ask the client for its own icons (C_CurrencyInfo.GetCoinTextureString) and
-- reuse the texture it returns, so we always match the game. If that helper is missing we use
-- the standard Blizzard paths. Size 0:0 makes the icon scale to the surrounding text.
local DEFAULT_ICONS = {
	g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
	s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
	c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
local coinIcons

local function GetCoinIcons()
	if coinIcons then return coinIcons end
	coinIcons = DEFAULT_ICONS
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		local found = {}
		for key, amount in pairs({ g = 10000, s = 100, c = 1 }) do
			local ok, str = pcall(C_CurrencyInfo.GetCoinTextureString, amount, 0)
			local snippet = ok and type(str) == "string" and str:match("|T.-|t")
			if snippet then found[key] = (snippet:gsub("^(|T[^:]+):%d+:%d+", "%1:0:0")) end
		end
		if found.g and found.s and found.c then coinIcons = found end
	end
	return coinIcons
end

function ns.ResetCoinIcons() coinIcons = nil end

-- copper -> "12,345 [gold icon] 67 [silver icon]" (zero parts hidden, copper only below 1 gold).
-- With full = true all three parts show: "12,345g 67s 89c" (used for character gold).
-- With icons turned off in Settings it falls back to "12,345g 67s". nil -> "n/a".
function ns.FormatMoney(copper, full)
	if type(copper) ~= "number" then return ns.Color("grey", "n/a") end
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper))
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local useIcons = not (ns.db and ns.db.settings and ns.db.settings.coinIcons == false)
	local icons = useIcons and GetCoinIcons() or nil

	local function part(color, value, key)
		if icons then return ns.Color(color, value) .. icons[key] end
		return ns.Color(color, value .. key)
	end

	local out = {}
	if full then
		-- gold amounts of characters: every part below the first non-zero one, copper included
		if g > 0 then out[#out + 1] = part("ffd100", Commas(g), "g") end
		if g > 0 or s > 0 then out[#out + 1] = part("c7c7cf", s, "s") end
		out[#out + 1] = part("eda55f", c, "c")
		return sign .. table.concat(out, " ")
	end
	if g > 0 then out[#out + 1] = part("ffd100", Commas(g), "g") end
	if s > 0 then out[#out + 1] = part("c7c7cf", s, "s") end
	if c > 0 and g == 0 then out[#out + 1] = part("eda55f", c, "c") end
	if #out == 0 then out[1] = part("eda55f", 0, "c") end
	return sign .. table.concat(out, " ")
end

---------------------------------------------------------------- logging
local LOG_MAX = 200
ns.log = {}

function ns.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	print(ns.PREFIX .. " " .. table.concat(parts, " "))
end

function ns.Debug(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local line = table.concat(parts, " ")
	ns.log[#ns.log + 1] = line
	if #ns.log > LOG_MAX then table.remove(ns.log, 1) end
	if ns.db and ns.db.settings and ns.db.settings.debug then
		print(ns.PREFIX .. " |cff9d9d9d[debug]|r " .. line)
	end
end

function ns.Error(where, err)
	ns.Debug("ERROR in " .. tostring(where) .. ": " .. tostring(err))
	ns.errorCount = (ns.errorCount or 0) + 1
	if ns.errorCount <= 3 then
		ns.Print(ns.Color("red", "error in " .. tostring(where)) .. " (" .. tostring(err) .. "). /ga log shows details.")
	end
end

-- Run fn(...) and log instead of throwing, so one bad module cannot break the rest.
function ns.Try(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then ns.Error(where, err) end
	return ok
end

---------------------------------------------------------------- events
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		-- RegisterEvent throws on events this client does not know; log it and carry on.
		local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
		if not ok then ns.Debug("could not register " .. event .. ": " .. tostring(err)) end
	end
	local list = handlers[event]
	list[#list + 1] = fn
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ns.Error(event, err) end
	end
end)

---------------------------------------------------------------- start-up order
ns.On("ADDON_LOADED", function(name)
	if name ~= addonName then return end
	ns.Database.Init()
	ns.Debug("loaded", ns.version)
end)

ns.On("PLAYER_LOGIN", function()
	ns.CharacterManager.Capture("login")
	C_Timer.After(5, function() ns.CharacterManager.Capture("login-late") end)   -- money can load late
	ns.UI.Build()
	local _, build, _, iface = GetBuildInfo()
	ns.Debug("client build", tostring(build), "interface", tostring(iface))
	ns.Print(("v%s loaded. Type %s to open."):format(ns.version, ns.Color("white", "/ga")))
end)

ns.On("PLAYER_LOGOUT", function() ns.CharacterManager.Capture("logout") end)

ns.On("PLAYER_MONEY", function()
	ns.CharacterManager.Capture("money")
	ns.UI.RefreshIfShown()
end)

ns.On("PLAYER_LEVEL_UP", function()
	ns.CharacterManager.Capture("level")
	ns.UI.RefreshIfShown()
end)

-- Skill-line events fire in bursts, so wait a moment and capture once.
local skillPending = false
ns.On("SKILL_LINES_CHANGED", function()
	if skillPending then return end
	skillPending = true
	C_Timer.After(1, function()
		skillPending = false
		ns.CharacterManager.Capture("skills")
		ns.UI.RefreshIfShown()
	end)
end)

-- Profession window events. Recording is debounced inside RecipeManager.
ns.On("TRADE_SKILL_SHOW", function() ns.RecipeManager.QueueScan("window") end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() ns.RecipeManager.QueueScan("list") end)
ns.On("NEW_RECIPE_LEARNED", function(recipeID)
	ns.RecipeManager.RecordSingle(recipeID)
	ns.CharacterManager.Capture("recipe")
	ns.UI.RefreshIfShown()
end)

-- Item names arrive a moment after we ask for them; redraw once when they do.
-- Item info events fire for every item the game loads (hovering, tooltips, other addons),
-- so only the items WE asked for matter.
local namePending = false
ns.On("GET_ITEM_INFO_RECEIVED", function(itemID)
	if not ns.RecipeManager.nameRequested[itemID] then return end
	if namePending then return end
	namePending = true
	C_Timer.After(0.5, function() namePending = false; ns.UI.RefreshIfShown() end)
end)

-- Auction House: read-only price scanning.
ns.On("AUCTION_HOUSE_SHOW", function()
	ns.AuctionScanner.open = true
	if ns.db.settings.autoScan ~= false and ns.RecipeManager.Count() > 0 then
		ns.AuctionScanner.RequestScan("auto")
	end
	ns.UI.RefreshIfShown()
end)
ns.On("AUCTION_HOUSE_CLOSED", function() ns.AuctionScanner.open = false; ns.UI.RefreshIfShown() end)
ns.On("REPLICATE_ITEM_LIST_UPDATE", function() ns.AuctionScanner.Process() end)

-- Gold tracker loot counting (only your own loot messages).
ns.On("CHAT_MSG_LOOT", function(...) ns.GoldTracker.OnLoot(...) end)

-- Owned counts change when bags change; redraw once the burst is over.
local bagPending = false
ns.On("BAG_UPDATE_DELAYED", function()
	if bagPending then return end
	bagPending = true
	C_Timer.After(1, function() bagPending = false; ns.UI.RefreshIfShown() end)
end)

---------------------------------------------------------------- slash commands
local function Help()
	ns.Print("commands:")
	print("  /ga                 open or close the window")
	print("  /ga tab <name>      dashboard, professions, market, gathering, goldtracker, characters, settings")
	print("  /ga demo on|off     show or hide the labelled demo data")
	print("  /ga debug on|off    print debug messages to chat")
	print("  /ga log             show the last debug messages")
	print("  /ga status          show what the addon can and cannot read on this client")
	print("  /ga recipes         show recipe recording status; '/ga recipes clear' forgets recorded recipes")
	print("  /ga find <text>     open the Market tab searching for that text")
	print("  /ga item <item>     open an item's detail view (item id or item link)")
	print("  /ga ledger          open the Ledger (real AH sales and purchases from mail); 'debug' / 'scan' at an open mailbox")
	print("  /ga chars           list tracked characters with saved gold and when it was saved")
	print("  /ga bank            show what the last bank visit recorded")
	print("  /ga scan            request an Auction House scan (open the AH first)")
	print("  /ga scan debug <item>  show raw scan listings for one item (checks per-stack vs per-unit prices)")
	print("  /ga setprice <item> <gold>   set a price yourself (vendor items etc.); item = id or item link")
	print("  /ga clearprice <item>        remove that manual price")
	print("  /ga prices clear    forget all scanned prices and history")
	print("  /ga session start|stop|status|clear   manual gold-per-hour sessions")
	print("  /ga reset window    put the window back in the centre at default size")
end

local function OnOff(arg) return arg == "on" or arg == "1" or arg == "true" end

local function Slash(msg)
	local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	local raw = rest               -- item links are case sensitive, so keep an untouched copy
	rest = rest:lower()
	if cmd == "" then
		ns.UI.Toggle()
	elseif cmd == "tab" then
		if not ns.UI.OpenTab(rest) then ns.Print("unknown tab '" .. rest .. "'. Try /ga help.") end
	elseif cmd == "demo" then
		ns.db.settings.showDemo = OnOff(rest)
		ns.Print("demo data " .. (ns.db.settings.showDemo and "shown" or "hidden"))
		ns.UI.RefreshIfShown()
	elseif cmd == "debug" then
		ns.db.settings.debug = OnOff(rest)
		ns.Print("debug " .. (ns.db.settings.debug and "on" or "off"))
	elseif cmd == "log" then
		local from = math.max(1, #ns.log - 19)
		if #ns.log == 0 then ns.Print("log is empty") end
		for i = from, #ns.log do print("  " .. ns.log[i]) end
	elseif cmd == "status" then
		ns.CharacterManager.PrintStatus()
		ns.RecipeManager.PrintStatus()
		ns.MarketData.PrintStatus()
		ns.AuctionScanner.PrintStatus()
	elseif cmd == "ledger" then
		if rest == "debug" then ns.Ledger.Debug()
		elseif rest == "scan" then
			local n = ns.Ledger.Scan("manual")
			ns.Print(("ledger: %d new record(s). Mails seen: %d, invoices read: %d."):format(n, ns.Ledger.stats.mails, ns.Ledger.stats.invoices))
		else ns.UI.OpenTab("ledger") end
	elseif cmd == "chars" then
		ns.CharacterManager.PrintList()
	elseif cmd == "bank" then
		ns.Print("bank records:")
		ns.Inventory.PrintStatus()
	elseif cmd == "find" then
		ns.UI.market.Find(raw)
	elseif cmd == "item" then
		local id = tonumber(raw:match("|Hitem:(%d+)")) or tonumber(raw:match("^(%d+)"))
		if id then ns.UI.market.Show("item", id) else ns.Print("usage: /ga item <itemID or item link>") end
	elseif cmd == "scan" then
		local sub, arg = rest:match("^(%S*)%s*(.-)$")
		if sub == "debug" then
			local id = tonumber(arg) or tonumber(raw:match("|Hitem:(%d+)"))
			if id then ns.AuctionScanner.Debug(id) else ns.Print("usage: /ga scan debug <itemID or item link>") end
		else
			ns.AuctionScanner.RequestScan("slash")
		end
	elseif cmd == "setprice" or cmd == "clearprice" then
		local id = tonumber(raw:match("|Hitem:(%d+)")) or tonumber(raw:match("^(%d+)"))
		if cmd == "clearprice" then
			if id and ns.MarketData.ClearManual(id) then ns.Print("manual price removed for item " .. id) else ns.Print("usage: /ga clearprice <itemID or item link> (only works for manual prices)") end
		else
			local gold = tonumber(raw:match("([%d%.]+)%s*g?%s*$"))
			if id and gold and gold > 0 and not raw:match("^%d+%s*$") then
				ns.MarketData.SetManual(id, gold * 10000)
				ns.Print(("manual price for %s set to %s"):format(ns.RecipeManager.ItemName(id), ns.FormatMoney(gold * 10000)))
				ns.UI.RefreshIfShown()
			else
				ns.Print("usage: /ga setprice <itemID or item link> <gold>   e.g. /ga setprice 2589 0.5")
			end
		end
	elseif cmd == "prices" then
		if rest == "clear" then
			ns.MarketData.ClearAll()
			ns.Print("scanned prices and history cleared (manual prices kept)")
			ns.UI.RefreshIfShown()
		else
			ns.MarketData.PrintStatus()
		end
	elseif cmd == "session" then
		if rest == "start" then
			local ok, err = ns.GoldTracker.Start()
			ns.Print(ok and "session started" or err)
		elseif rest == "stop" then
			local ok, res = ns.GoldTracker.Stop()
			if ok then
				ns.Print(("session finished: %s, gold change %s, looted items worth about %s"):format(
					ns.GoldTracker.FormatDuration(res.seconds), res.goldChange and ns.FormatMoney(res.goldChange) or "unknown", ns.FormatMoney(res.marketValue)))
			else
				ns.Print(res)
			end
		elseif rest == "clear all" then
			ns.GoldTracker.Clear(); ns.Print("sessions cleared for every character")
		elseif rest == "clear" then
			ns.GoldTracker.Clear(ns.CharacterManager.currentKey); ns.Print("finished sessions cleared for this character (/ga session clear all clears every character)")
		else
			local s = ns.db.activeSession
			if s then
				local snap = ns.GoldTracker.Snapshot(s)
				ns.Print(("running %s, gold change %s, %d items looted"):format(ns.GoldTracker.FormatDuration(snap.seconds), snap.goldChange and ns.FormatMoney(snap.goldChange) or "unknown", snap.items))
			else
				ns.Print("no session running. /ga session start")
			end
		end
		ns.UI.RefreshIfShown()
	elseif cmd == "recipes" then
		if rest == "clear" then
			ns.RecipeManager.Clear()
			ns.Print("recorded recipes cleared")
			ns.UI.RefreshIfShown()
		else
			ns.RecipeManager.PrintStatus()
		end
	elseif cmd == "reset" and rest == "window" then
		ns.UI.ResetWindow()
		ns.Print("window reset")
	else
		Help()
	end
end

SLASH_GOBLINADVISOR1 = "/ga"
SLASH_GOBLINADVISOR2 = "/goblin"
SLASH_GOBLINADVISOR3 = "/goblinadvisor"
SlashCmdList["GOBLINADVISOR"] = function(msg)
	local ok, err = pcall(Slash, msg)
	if not ok then ns.Error("slash", err) end
end
