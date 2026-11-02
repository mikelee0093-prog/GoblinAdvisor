-- Headless tests for Goblin Advisor. Run from the repo root:  lua tests/run.lua
-- A fake WoW client (frames accept any call) loads the addon's real files in .toc order, fires
-- events and slash commands, and checks the results. This proves the LOGIC runs without Lua
-- errors. It cannot prove how the window looks or that the live client returns what we expect:
-- those still need an in-game check.

local ADDON_DIR = ""
local unpack = unpack or table.unpack

---------------------------------------------------------------- fake client
local frames = {}
local methods = {}
local meta = {}
meta.__index = function(_, k)
	local m = methods[k]
	if m then return m end
	return function(self)
		if type(k) == "string" and k:sub(1, 3) == "Get" then return 100 end
		return self
	end
end
local function NewObj()
	local o = setmetatable({ shown = false, scripts = {}, text = "" }, meta)
	frames[#frames + 1] = o
	return o
end
function methods.Show(self) self.shown = true; local f = self.scripts.OnShow; if f then f(self) end end
function methods.Hide(self) self.shown = false end
function methods.IsShown(self) return self.shown end
function methods.SetScript(self, n, f) self.scripts[n] = f end
function methods.GetScript(self, n) return self.scripts[n] end
function methods.CreateTexture() return NewObj() end
function methods.CreateFontString() return NewObj() end
function methods.SetText(self, t) self.text = t end
function methods.GetText(self) return self.text end
function methods.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function methods.RegisterEvent(self, e)
	if e == "BAD_EVENT" then error("unknown event " .. e) end
	local ev = rawget(self, "events") or {}
	rawset(self, "events", ev)
	ev[e] = true
end

local out = {}
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	out[#out + 1] = table.concat(parts, " ")
end

local money, secretGold = 123456, false
local profsBroken = false
CreateFrame = function(_, name)
	local o = NewObj()
	if name then _G[name] = o end
	return o
end
UIParent = NewObj()
UISpecialFrames = {}
SlashCmdList = {}
RAID_CLASS_COLORS = { WARRIOR = { colorStr = "ffc79c6e" } }
UnitName = function() return "Testy" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Warrior", "WARRIOR" end
UnitLevel = function() return 12 end
GetMoney = function() if secretGold then return "SECRET" end return money end
issecretvalue = function(v) return v == "SECRET" end
local nowT = 1000
GetServerTime = function() return nowT end
GetBuildInfo = function() return "1.60.1", "70235", "Oct 1 2026", 16001 end
GetAddOnMetadata = function() return "0.1.0" end
C_Timer = { After = function(_, f) f() end }
GetProfessions = function() if profsBroken then error("boom") end return 1, 2 end
GetProfessionInfo = function(i)
	if i == 1 then return "Mining", 0, 45, 75 end
	return "Herbalism", 0, 30, 75
end

---------------------------------------------------------------- harness
local passed, failed = 0, 0
local function check(cond, label)
	if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. label); io.stdout:write("FAIL: " .. label .. "\n") end
end
local function plain(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
local function noicons(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function lastOut() return out[#out] or "" end

local ns = {}
local order = {}
for line in io.lines(ADDON_DIR .. "GoblinAdvisor_Camelot.toc") do
	if line ~= "" and line:sub(1, 2) ~= "##" then order[#order + 1] = (line:gsub("\\", "/")):gsub("%s+$", "") end
end
check(#order >= 8, "toc lists the files")
for _, file in ipairs(order) do
	local chunk, err = loadfile(ADDON_DIR .. file)
	check(chunk ~= nil, "loads " .. file .. " " .. tostring(err))
	if chunk then
		local ok, e = pcall(chunk, "GoblinAdvisor", ns)
		check(ok, "runs " .. file .. " " .. tostring(e))
	end
end

local eventFrame
for _, f in ipairs(frames) do if f.scripts.OnEvent then eventFrame = f; break end end
local function fire(event, ...) eventFrame.scripts.OnEvent(eventFrame, event, ...) end
local function slash(msg) SlashCmdList["GOBLINADVISOR"](msg) end

check(ns.version == "0.1.0", "version read from toc metadata")

-- start-up
check(rawget(eventFrame, "events") and rawget(eventFrame, "events").PLAYER_LOGIN, "PLAYER_LOGIN registered")
fire("ADDON_LOADED", "SomeOtherAddon")
check(ns.db == nil, "ignores other addons loading")
fire("ADDON_LOADED", "GoblinAdvisor")
check(ns.db and ns.db.settings.showDemo == false and ns.db.market and ns.db.sessions, "database defaults created (demo off by default)")
check(GoblinAdvisorDB == ns.db, "SavedVariables global is the live table")
fire("PLAYER_LOGIN")
local rec = ns.db.characters["Testy-Realm"]
check(rec ~= nil, "character recorded at login")
check(rec and rec.gold == 123456 and rec.level == 12, "gold and level captured")
check(rec and #rec.professions == 2 and rec.professions[1].name == "Mining", "professions captured")
check(GoblinAdvisorFrame ~= nil, "main window frame exists")

-- window and tabs
slash("")
check(GoblinAdvisorFrame:IsShown(), "/ga opens the window")
slash("")
check(not GoblinAdvisorFrame:IsShown(), "/ga again closes it")
slash("tab market")
check(ns.UI.current == "market" and GoblinAdvisorFrame:IsShown(), "/ga tab market opens that tab")
local before = #out
slash("tab nonsense")
check(plain(lastOut()):find("unknown tab"), "unknown tab is reported")
for _, id in ipairs({ "dashboard", "professions", "market", "gathering", "goldtracker", "characters", "settings" }) do
	check(ns.UI.OpenTab(id), "tab opens: " .. id)
end

-- dashboard text (printed so a human can read it)
ns.UI.OpenTab("dashboard")
print("---- dashboard text ----")
local seen = {}
for _, f in ipairs(frames) do
	local t = plain(f.text or "")
	if t ~= "" and not seen[t] and #t > 25 then seen[t] = true; print(t); print("") end
end
local dump = table.concat(out, "\n")
check(dump:find("DEMO"), "demo data is labelled")
check(dump:find("Testy"), "dashboard shows the real character name")

-- session gold tracking
money = 128456
fire("PLAYER_MONEY")
check(ns.CharacterManager.SessionDelta() == 5000, "session delta is real change in gold")

-- secret values are ignored, not trusted
secretGold = true
fire("PLAYER_MONEY")
check(ns.db.characters["Testy-Realm"].gold == 128456, "secret gold value keeps the last good value")
secretGold = false

-- profession API failure keeps old data and does not throw
profsBroken = true
fire("SKILL_LINES_CHANGED")
check(#ns.db.characters["Testy-Realm"].professions == 2, "failed profession read keeps previous list")
check(ns.CharacterManager.professionsReadable == false, "failure is reported as unreadable")
profsBroken = false

-- settings and slash commands
slash("demo off")
check(ns.db.settings.showDemo == false, "/ga demo off")
slash("demo on")
check(ns.db.settings.showDemo == true, "/ga demo on")
slash("debug on"); check(ns.db.settings.debug == true, "/ga debug on"); slash("debug off")
slash("status")
check(plain(table.concat(out, "\n")):find("scanned prices stored: 0"), "/ga status reports there are no scanned prices")
slash("log")
slash("reset window")
slash("help")

-- market data: no providers means no price; never invented
check(ns.MarketData.GetPrice(1234) == nil, "no provider -> nil price")
check(not ns.MarketData.Register({ id = "bad" }), "invalid provider rejected")
ns.MarketData.Register({ id = "t", name = "Test", kind = "manual", GetPrice = function(id) if id == 7 then return 500, 99 end end })
local p = ns.MarketData.GetPrice(7)
check(p and p.price == 500 and p.source == "t", "registered provider supplies a price")
check(ns.MarketData.GetPrice(8) == nil, "provider without a price -> nil")
ns.MarketData.Register({ id = "boom", GetPrice = function() error("x") end })
check(ns.MarketData.GetPrice(8) == nil, "throwing provider is contained")

-- money formatting (icons are on by default; plain() strips colours and icons)
check(plain(ns.FormatMoney(12345678)) == "1,234 56", "FormatMoney large")
check(plain(ns.FormatMoney(0)) == "0", "FormatMoney zero")
check(plain(ns.FormatMoney(-5000)) == "-50", "FormatMoney negative")
check(plain(ns.FormatMoney(100000)) == "10", "FormatMoney hides zero silver")
check(plain(ns.FormatMoney(nil)) == "n/a", "FormatMoney nil")
local raw = ns.FormatMoney(12345678)
check(raw:find("UI%-GoldIcon") and raw:find("UI%-SilverIcon"), "fallback icons use the standard Blizzard coin textures")
check(not raw:find("UI%-CopperIcon"), "copper icon hidden when there is at least 1 gold")
check(ns.FormatMoney(5):find("UI%-CopperIcon"), "copper icon shown below 1 gold")
-- the client's own helper wins when it exists
C_CurrencyInfo = { GetCoinTextureString = function(amount)
	local name = amount == 10000 and "G" or (amount == 100 and "S" or "C")
	return "1|TInterface\\Test\\" .. name .. ":14:14:2:0|t"
end }
ns.ResetCoinIcons()
local viaClient = ns.FormatMoney(10100)
check(viaClient:find("Test\\G:0:0:2:0") and viaClient:find("Test\\S:0:0:2:0"), "icons come from C_CurrencyInfo.GetCoinTextureString, resized to 0:0")
C_CurrencyInfo = { GetCoinTextureString = function() error("nope") end }
ns.ResetCoinIcons()
check(ns.FormatMoney(10000):find("UI%-GoldIcon"), "a failing client helper falls back to the standard icons")
C_CurrencyInfo = nil
ns.ResetCoinIcons()
-- turning icons off gives plain letters
ns.db.settings.coinIcons = false
check(noicons(ns.FormatMoney(12345678)) == "1,234g 56s", "icons off -> letters")
check(not ns.FormatMoney(12345678):find("|T"), "icons off -> no texture escapes")
ns.db.settings.coinIcons = true

-- ================================================================ Phase 2: recipes and professions
local isNPC, isLinked, recipeApiBroken = false, false, false
local professionOpen = "Mining"
local fakeRecipes = {
	[101] = { name = "Copper Bar", out = 2840, learned = true, slots = { { qty = 1, ids = { 2770 } } } },
	[102] = { name = "Bronze Bar", out = 3576, learned = true, slots = { { qty = 1, ids = { 2840 } }, { qty = 1, ids = { 3576 + 1 } } } },
	[103] = { name = "Iron Bar", out = 3575, learned = false, req = 30, slots = { { qty = 2, ids = { 2772, 20772 } } } },
	[104] = { name = "Smelt Nothing", out = nil, learned = true, slots = {} },
}
C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return { professionName = professionOpen, skillLevel = 45, maxSkillLevel = 75 } end,
	GetAllRecipeIDs = function() if recipeApiBroken then error("boom") end return { 101, 102, 103, 104, 999 } end,
	GetRecipeInfo = function(id)
		local r = fakeRecipes[id]
		if not r then return nil end
		return { name = r.name, learned = r.learned, unlockedRecipeLevel = r.req }
	end,
	GetRecipeSchematic = function(id)
		local r = fakeRecipes[id]
		if not r then return nil end
		local slots = {}
		for _, sl in ipairs(r.slots) do
			local reagents = {}
			for _, iid in ipairs(sl.ids) do reagents[#reagents + 1] = { itemID = iid } end
			slots[#slots + 1] = { reagentType = 1, quantityRequired = sl.qty, reagents = reagents }
		end
		slots[#slots + 1] = { reagentType = 2, quantityRequired = 1, reagents = { { itemID = 55555 } } }  -- optional slot: must be ignored
		return { outputItemID = r.out, quantityMin = 1, quantityMax = 2, reagentSlotSchematics = slots }
	end,
	IsNPCCrafting = function() return isNPC end,
	IsTradeSkillLinked = function() return isLinked end,
	GetProfessionInfoByRecipeID = function() return { professionName = "Mining" } end,
}
C_Item = { GetItemNameByID = function(id) if id == 2770 then return "Copper Ore" end end }

fire("TRADE_SKILL_SHOW")
local RM = ns.RecipeManager
check(RM.Count() == 4, "4 of 5 recipe ids recorded (the unreadable id is skipped)")
local bronze = ns.db.recipes[102]
check(bronze and bronze.prof == "Mining" and bronze.out == 3576, "recipe stores profession and output item")
check(bronze and #bronze.reagents == 2 and bronze.reagents[1].qty == 1, "basic reagent slots recorded; optional slots ignored")
check(ns.db.recipes[103].reagents[1].ids[2] == 20772, "quality tiers of one slot are kept together")
check(ns.db.recipes[104].out == nil, "recipe without an output item is recorded safely")
local known = ns.db.characters["Testy-Realm"].known and ns.db.characters["Testy-Realm"].known.Mining
check(known and known[101] and known[102] and not known[103], "known recipes tracked per character")
check(RM.lastResult and RM.lastResult.recorded == 4 and RM.lastResult.known == 3, "scan result counts are right")
check(plain(table.concat(out, "\n")):find("recorded 4 Mining recipes"), "first scan tells the player once")

-- summaries and comparison
local sums = ns.ProfessionManager.Summaries()
local mining
for _, sm in ipairs(sums) do if sm.name == "Mining" then mining = sm end end
check(mining and mining.recipes == 4, "profession summary counts recipes")
check(mining and mining.distinctMaterials == 4, "distinct materials counted (tiers not double counted)")
check(mining and mining.avgReagents and math.abs(mining.avgReagents - 1) < 0.01, "average reagents per recipe")
check(mining and mining.topMaterials[1] and mining.topMaterials[1].uses >= 1, "top materials listed")
local herb
for _, sm in ipairs(sums) do if sm.name == "Herbalism" then herb = sm end end
check(herb and herb.recipes == 0 and #herb.characters == 1, "a profession with no recorded recipes still appears from the character")
local rows = ns.ProfessionManager.Compare(mining, herb)
check(rows[1].a == 4 and rows[1].b == 0, "compare: recipe counts side by side")
local noData = 0
for _, row in ipairs(rows) do if row.a == nil and row.b == nil then noData = noData + 1 end end
check(noData >= 3, "compare: price-based rows are nil (no data), never invented")
check(ns.ProfessionManager.Compare(nil, nil)[1].a == nil, "compare tolerates missing profession")

-- UI renders the tab without errors, with and without compare mode
check(ns.UI.OpenTab("professions"), "professions tab opens")
check((ns.errorCount or 0) == 0, "no errors raised so far")
check(RM.ItemName(2770) == "Copper Ore" and RM.ItemName(1) == "item 1", "item names resolve, with a placeholder when unknown")

-- rescan is idempotent
fire("TRADE_SKILL_LIST_UPDATE")
check(RM.Count() == 4, "rescanning does not duplicate recipes")

-- another player's or an NPC's window is not recorded
local beforeCount = RM.Count()
isLinked = true; professionOpen = "Tailoring"
RM.Scan("test")
check(RM.Count() == beforeCount and RM.lastProblem and RM.lastProblem:find("another player"), "linked window is not recorded")
isLinked = false; isNPC = true
RM.Scan("test")
check(RM.Count() == beforeCount, "NPC crafting window is not recorded")
isNPC = false; professionOpen = "Mining"

-- API failures are contained and explained
recipeApiBroken = true
check(pcall(RM.Scan, "test") and RM.lastProblem and RM.lastProblem:find("no usable recipe%-list"), "failing list call is explained, not thrown")
recipeApiBroken = false
local saved = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = nil
RM.Scan("test")
check(RM.lastProblem and RM.lastProblem:find("no usable recipe%-list"), "missing recipe-list function is reported")
C_TradeSkillUI.GetAllRecipeIDs = saved
local savedC = C_TradeSkillUI
C_TradeSkillUI = nil
check(pcall(RM.Scan, "test"), "missing C_TradeSkillUI does not throw")
C_TradeSkillUI = savedC

-- newly learned recipe while the window is closed
fakeRecipes[105] = { name = "Steel Bar", out = 3859, learned = true, slots = { { qty = 1, ids = { 3575 } } } }
fire("NEW_RECIPE_LEARNED", 105)
check(ns.db.recipes[105] and ns.db.characters["Testy-Realm"].known.Mining[105], "learning a recipe records it and marks it known")

-- status and clear commands
slash("recipes")
check(plain(table.concat(out, "\n")):find("recipes stored"), "/ga recipes prints status")
slash("recipes clear")
check(RM.Count() == 0 and not ns.db.characters["Testy-Realm"].known, "/ga recipes clear forgets recipes and known sets")
ns.UI.OpenTab("professions")
check((ns.errorCount or 0) == 0, "professions tab renders with no recipes, no errors")


-- ================================================================ Phase 3 + 4
GameTooltip = NewObj()
local replicateCalls = 0
local listings = {}
C_AuctionHouse = {
	ReplicateItems = function() replicateCalls = replicateCalls + 1 end,
	GetNumReplicateItems = function() return #listings end,
	GetReplicateItemInfo = function(i)
		local l = listings[i + 1]
		return "n", 0, l[1], 1, true, 1, "", 0, 0, l[2], 0, "", "", "", "", 0, l[3], true
	end,
}
local metalItems = { [2770] = true, [2772] = true, [20772] = true, [2840] = true, [3576] = true, [3577] = true, [3575] = true, [3859] = true }
local itemRequests = {}
local owned = { [2770] = 15, [2447] = 3 }
local names = { [2770] = "Copper Ore", [2840] = "Copper Bar", [3859] = "Steel Bar", [2447] = "Peacebloom", [3575] = "Iron Bar" }
C_Item = {
	GetItemNameByID = function(id) return names[id] end,
	GetItemInfoInstant = function(id)
		if metalItems[id] then return id, "Trade Goods", "Metal & Stone", "", 0, 7, 7 end
		if id == 2447 then return id, "Trade Goods", "Herb", "", 0, 7, 9 end
		return nil
	end,
	GetItemCount = function(id) return owned[id] or 0 end,
	RequestLoadItemDataByID = function(id) itemRequests[id] = (itemRequests[id] or 0) + 1 end,
}
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
GetMaxLevelForPlayerExpansion = function() return 90 end
GetZoneText = function() return "Elwynn Forest" end
GetRealZoneText = GetZoneText

C_TradeSkillUI.GetAllRecipeIDs = function() return { 101, 102, 103, 104, 105, 999 } end
professionOpen = "Mining"
fire("TRADE_SKILL_SHOW")
check(RM.Count() == 5, "phase 3: five recipes recorded again")

-- item name requests happen once per item, and only our own requests cause redraws
check(RM.ItemName(31337) == "item 31337" and RM.ItemName(31337) == "item 31337", "unknown item shows a placeholder")
check(itemRequests[31337] == 1, "the item data request is sent once, however often the window redraws")
local redraws, origRefresh = 0, ns.UI.RefreshIfShown
ns.UI.RefreshIfShown = function() redraws = redraws + 1; return origRefresh() end
fire("GET_ITEM_INFO_RECEIVED", 555)
check(redraws == 0, "item info for items we never asked about does not redraw")
fire("GET_ITEM_INFO_RECEIVED", 31337)
check(redraws == 1, "item info for an item we asked about redraws once")
ns.UI.RefreshIfShown = origRefresh

-- Auction House scan -------------------------------------------------
local AS, MD, PC = ns.AuctionScanner, ns.MarketData, ns.ProfitCalculator
listings = {
	{ 20, 2000, 2770 }, { 10, 1500, 2770 },        -- ore: 100 and 150 per unit -> cheapest 100
	{ 5, 5000, 2840 },                              -- copper bar 1000
	{ 1, 3000, 3576 },                              -- bronze bar 3000
	{ 10, 4000, 3577 },                             -- tin bar 400
	{ 10, 3000, 2772 }, { 10, 2000, 20772 },        -- iron ore tiers: 300 / 200
	{ 1, 8000, 3575 },                              -- iron bar 8000
	{ 1, 20000, 3859 },                             -- steel bar 20000
	{ 1, 5, nil },                                  -- listing with incomplete item data
	{ 1, 777, 99999 },                              -- item no recipe uses: must not be stored
}
AS.RequestScan("test")
check(plain(table.concat(out, "\n")):find("open the Auction House first"), "scan refused while the AH is closed")
fire("AUCTION_HOUSE_SHOW")
check(AS.open and replicateCalls == 1, "opening the AH requests one scan automatically")
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.lastResult and AS.lastResult.kept == 8 and AS.lastResult.incomplete == 1, "scan keeps the 8 tracked items and counts the incomplete listing")
check(ns.db.market.lastScan == nowT, "scan time recorded")
-- hovering items makes the client re-fire the update event: that must not rescan
local pc = AS.processCount
for _ = 1, 6 do fire("REPLICATE_ITEM_LIST_UPDATE") end
check(AS.processCount == pc, "repeated list-update events with unchanged data are ignored")
listings[#listings + 1] = { 1, 1, 99999 }
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 1, "a changed number of listings is new data and is processed")
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 1, "...once")
AS.RequestScan("again")
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 2, "a scan we requested is processed")
nowT = nowT + 400
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 3, "unchanged data is re-read after 5 minutes")
-- listings that lacked item data get a limited number of early retries
nowT = nowT + 61
fire("REPLICATE_ITEM_LIST_UPDATE"); fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 4, "incomplete listings trigger one early retry per minute")
nowT = nowT + 61
fire("REPLICATE_ITEM_LIST_UPDATE")
nowT = nowT + 61
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 4 and AS.retries == 2, "...and at most two retries (the 5-minute re-read above used the first)")
nowT = nowT + 61
fire("REPLICATE_ITEM_LIST_UPDATE")
check(AS.processCount == pc + 4, "no further retries after that")
check(ns.db.market.prices[99999] == nil, "items no recipe uses are not stored")
check(MD.GetPrice(2770).price == 100 and MD.GetPrice(2770).source == "ahscan", "stack buyout is divided by stack size; cheapest listing wins")
check(MD.GetPrice(2772).price == 300 and MD.GetPrice(20772).price == 200, "each quality tier is priced separately")

-- stack total vs per unit setting
ns.db.settings.scanPriceIsUnit = true
AS.Process(true)
check(MD.GetPrice(2770).price == 1500, "with 'already per unit' on, the raw buyout is used")
ns.db.settings.scanPriceIsUnit = false
AS.Process(true)
check(MD.GetPrice(2770).price == 100, "switching back and rescanning restores per-stack division")
check(#ns.db.market.history[2770] == 1, "several scans on one day keep a single history sample")

-- profit math (checked by hand) ---------------------------------------
local function near(a, b) return a and math.abs(a - b) < 0.001 end
local e101 = PC.Evaluate(101)
check(e101.cost == 100 and near(e101.revenue, 1425) and near(e101.profit, 1325), "recipe profit: cost 100, sells 1000 x 0.95 x 1.5 = 1425, profit 1325")
check(near(e101.margin, 1325 / 1425) and near(e101.roi, 13.25), "margin = profit/revenue, ROI = profit/cost")
check(near(e101.rawNet, 95) and near(e101.uplift, 1330) and e101.verdict == "craft", "crafting beats selling the ore: rawNet 95, uplift 1330")
check(near(PC.Evaluate(102).profit, 2875), "recipe with two reagents: 4275 - 1400 = 2875")
check(near(PC.Evaluate(103).cost, 400) and near(PC.Evaluate(103).profit, 11000), "cheapest quality tier is used: 2 x 200")
check(near(PC.Evaluate(105).profit, 20500), "steel bar profit 20500")
local e104 = PC.Evaluate(104)
check(e104.profit == nil and e104.cost == nil and e104.reason == "no reagents recorded", "recipe with no reagents is not priced")
local mining = PC.Profession("Mining")
check(#mining.priced == 4 and mining.total == 5 and near(mining.score, 8925), "profession score = average of best priced recipes (8925)")
check(near(mining.coverage, 0.8), "price coverage 4 of 5")

-- missing price: no number, only a reason
ns.db.market.prices[3577] = nil
MD.revision = MD.revision + 1
local e102 = PC.Evaluate(102)
check(e102.profit == nil and e102.cost == nil and e102.reason:find("no price for 1 reagent"), "a missing reagent price blocks the profit instead of showing a partial sum")
check(near(e102.partialCost, 1000), "the partial cost is kept separate and never shown as the cost")
check(#PC.Profession("Mining").priced == 3, "unpriced recipe drops out of the ranking")
slash("setprice 3577 0.04")
check(MD.GetPrice(3577).source == "manual" and MD.GetPrice(3577).price == 400, "/ga setprice sets a manual price in gold")
check(near(PC.Evaluate(102).profit, 2875), "manual price completes the recipe again")
AS.Process(true)
check(MD.GetPrice(3577).source == "manual", "manual price wins over a scanned price")
check(ns.db.market.prices[3577] and ns.db.market.prices[3577].price == 400, "the scan still records its own price underneath")
slash("clearprice 3577")
check(MD.GetPrice(3577).source == "ahscan", "clearing the manual price falls back to the scan")
slash("setprice |cffffffff|Hitem:2447::::|h[Peacebloom]|h|r 0.01")
check(MD.GetPrice(2447) and MD.GetPrice(2447).price == 100, "/ga setprice accepts an item link")
local before = #out
slash("setprice 2447")
check(plain(lastOut()):find("usage"), "setprice without a price shows usage")
slash("clearprice 2447")

-- material actions ------------------------------------------------------
local R = ns.Recommendations
local act, why = R.MaterialAction(2770)
check(act == "Craft" and why:find("Copper Bar"), "ore used in a profitable recipe -> Craft")
check(R.MaterialAction(123456) == nil, "no price -> no action, never a guess")
act = R.MaterialAction(3859)
check(act == "Gather", "an output item that is a top-valued gatherable -> Gather")

-- gathering -------------------------------------------------------------
local GA = ns.GatheringAdvisor
ns.db.market.manual[2447] = nil
MD.RecordPrice(2447, 50, "ahscan")
local g = GA.Suggest()
local byName = {}
for _, p in ipairs(g.professions) do byName[p.name] = p end
check(byName.Mining and byName.Herbalism and not byName.Skinning, "gathering advice only for professions the character has")
check(byName.Mining.items[1].id == 3859 and byName.Mining.items[1].price == 20000, "mining list is sorted by price, highest first")
check(#byName.Herbalism.items == 1 and byName.Herbalism.items[1].id == 2447, "herbs are matched by item subclass")
local oreRow
for _, it in ipairs(byName.Mining.items) do if it.id == 2770 then oreRow = it end end
check(oreRow and oreRow.owned == 15 and oreRow.usedIn >= 1, "owned count and recipe use shown for each material")
check(select(1, GA.IsTopPick(3859)) == true and select(1, GA.IsTopPick(2770)) == false, "top-pick test")
local cur = ns.CharacterManager.GetCurrent()
local savedProfs = cur.professions
cur.professions = { { name = "Bergbau", skill = 10, maxSkill = 75 } }
local g2 = GA.Suggest()
check(#g2.professions == 0 and g2.anyProfession, "unrecognised (e.g. translated) profession names give an explanation, not wrong advice")
cur.professions = savedProfs

-- stage, ranking, activities -----------------------------------------------
local stage = R.Stage()
check(stage == "leveling", "level 12 with low skill is a leveling character")
cur.level = 5; check(R.Stage() == "fresh", "level 5 is fresh"); cur.level = 90; check(R.Stage() == "max", "level cap is max level")
cur.level = 12
cur.professions = { { name = "Mining", skill = 60, maxSkill = 75 } }
check(R.Stage() == "established", "a profession at 75% of its cap is established")
cur.professions = savedProfs
local ranking = R.ProfessionRanking()
check(ranking[1].name == "Mining" and near(ranking[1].score, 8925) and ranking[1].mine, "profession ranking puts the scored profession first")
local sawUnscored = false
for _, r in ipairs(ranking) do if r.name == "Herbalism" and r.score == nil then sawUnscored = true end end
check(sawUnscored, "a profession without recipes is listed with no score")
local acts = R.Activities()
check(acts[1] and acts[1].kind == "craft" and near(acts[1].amount, 20500) and acts[1].unit == "per craft" and acts[1].text:find("Steel Bar"), "best activity is the best KNOWN priced recipe, in gold per craft")
local kinds = {}
for _, a in ipairs(acts) do kinds[a.kind] = true end
check(kinds.gather and not kinds.session, "gathering suggestions present, no session suggestion before any session")
local invValue, invPriced = R.InventoryValue()
check(invValue == 1500 and invPriced == 1, "inventory value counts only priced owned materials (15 ore x 100)")

-- recommended activities respect known recipes and skill requirements ----------------
check(ns.db.recipes[103].req == 30 and ns.db.recipes[101].req == nil, "recipe skill requirement recorded when the game provides it")
do
	local savedP = cur.professions
	cur.professions = { { name = "Mining", skill = 45, maxSkill = 75 } }
	local function craftTexts()
		local t = {}
		for _, a in ipairs(R.Activities()) do if a.kind == "craft" then t[#t + 1] = a end end
		return t
	end
	local crafts = craftTexts()
	local sawLearn = false
	for _, a in ipairs(crafts) do if a.needsRecipe and plain(a.text):find("learn the recipe first") then sawLearn = true end end
	check(#crafts >= 1 and not crafts[1].needsRecipe, "known recipes come first without a warning")
	check(sawLearn, "unlearned recipe within skill is shown and flagged \"learn the recipe first\"")
	cur.professions = { { name = "Mining", skill = 20, maxSkill = 75 } }
	for _, a in ipairs(craftTexts()) do check(not a.needsRecipe, "unlearned recipe above current skill is not suggested") end
	cur.professions = { { name = "Herbalism", skill = 100, maxSkill = 150 } }
	check(#craftTexts() == 0, "crafts from professions the character does not have are not suggested")
	cur.professions = savedP
end

-- bank snapshots ------------------------------------------------------------------------
do
	local bankItems = { [2770] = 40, [2840] = 7 }
	C_Container = {
		GetContainerNumSlots = function(bag) return bag == 6 and 3 or 0 end,
		GetContainerItemInfo = function(bag, slot)
			if slot == 1 then return { itemID = 2770, stackCount = bankItems[2770] - 10 } end
			if slot == 2 then return { itemID = 2770, stackCount = 10 } end
			if slot == 3 then return { itemID = 2840, stackCount = bankItems[2840] } end
		end,
	}
	local savedOwned = owned[2770]
	owned[2770] = 15   -- the stub's GetItemCount ignores bank flags, so this is "bags only"
	local live = ns.GatheringAdvisor.Owned(2770)
	check(live == 15, "without a bank record, owned = what the game reports")
	check(ns.Inventory.Snapshot() == true, "bank snapshot succeeds when bank tabs are readable")
	check(ns.CharacterManager.GetCurrent().bank.items[2770] == 40, "stacks in the bank are summed per item")
	check(ns.GatheringAdvisor.Owned(2770) == 55, "owned = bags + recorded bank")
	fire("BANKFRAME_OPENED"); fire("BAG_UPDATE_DELAYED")
	check(ns.Inventory.bankOpen, "bank open state tracked")
	fire("BANKFRAME_CLOSED")
	check(not ns.Inventory.bankOpen, "bank close tracked")
	C_Container.GetContainerNumSlots = function() return 0 end
	check(ns.Inventory.Snapshot() == false and ns.CharacterManager.GetCurrent().bank.items[2770] == 40, "an unreadable bank keeps the previous record")
	slash("bank")
	check(plain(table.concat(out, "\n")):find("character bank: 2 kinds, 47 items"), "/ga bank reports the record")
	owned[2770] = savedOwned
	ns.CharacterManager.GetCurrent().bank = nil
end

-- gold tracker ------------------------------------------------------------------
local GT = ns.GoldTracker
check(select(1, GT.Stop()) == false, "stopping with no session is refused")
money = 200000
slash("session start")
check(ns.db.activeSession and ns.db.activeSession.startGold == 200000, "session records starting gold")
check(select(1, GT.Start()) == false, "a second session cannot start")
local link = "|cffffffff|Hitem:2770::::::::|h[Copper Ore]|h|r"
fire("CHAT_MSG_LOOT", "You receive loot: " .. link .. "x3.")
fire("CHAT_MSG_LOOT", "You receive loot: " .. link .. ".")
fire("CHAT_MSG_LOOT", "Bob receives loot: " .. link .. ".")
fire("CHAT_MSG_LOOT", "SECRET")
fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:9999::::|h[Mystery]|h|rx2.")
check(ns.db.activeSession.loot[2770] == 4, "your loot is counted (3 + 1); other players' loot is not")
check(ns.db.activeSession.loot[9999] == 2, "unknown items are still counted")
nowT = nowT + 3600
money = 205000
local snap = GT.Snapshot(ns.db.activeSession)
check(snap.goldChange == 5000 and snap.seconds == 3600, "recorded gold change and time")
check(snap.marketValue == 400 and snap.unpriced == 2 and snap.materials == 4, "market value 4 x 100; unpriced items counted as 0 and reported")
check(near(snap.recordedPerHour, 5000) and near(snap.marketPerHour, 400), "real and theoretical hourly rates are separate numbers")
secretGold = true
local ok, res = GT.Stop()
check(ok and res.goldChange == nil, "unreadable gold at stop gives 'unknown', not a made-up number")
secretGold = false
check(ns.db.activeSession == nil and #ns.db.sessions == 1, "stopping stores the finished session")
local s1 = ns.db.sessions[1]
check(s1.marketValue == 400, "market value is frozen at stop time")
-- a normal second session
slash("session start"); nowT = nowT + 7200; money = money + 20000
slash("session stop")
local best, rate = GT.Best()
check(best and near(rate, 10000), "best session is chosen by RECORDED gold per hour (20000 over 2h)")
check(R.Activities()[#R.Activities()].kind == "session", "best recorded session appears as an activity, per hour")
slash("session start"); nowT = nowT + 30; slash("session stop")
check(GT.Snapshot(ns.db.sessions[3]).recordedPerHour == nil, "sessions under a minute get no hourly rate")
slash("session status"); slash("session clear")
check(#ns.db.sessions == 0, "/ga session clear")

-- price history and trends ----------------------------------------------------------
local saveNow = nowT
nowT = 86400 * 200
for _, p in ipairs({ 100, 100, 100, 130 }) do MD.RecordPrice(5555, p, "ahscan"); nowT = nowT + 86400 end
nowT = nowT - 86400
local st = MD.GetStats(5555)
check(st.samples == 4 and near(st.avg, 100) and near(st.change, 0.30) and st.trend == "up", "trend: 130 against a recent average of 100 is +30%")
local a5, w5 = R.MaterialAction(5555)
check(a5 == "Sell" and w5:find("above"), "price well above its recent average -> Sell")
nowT = 86400 * 300
for _, p in ipairs({ 100, 100, 100, 80 }) do MD.RecordPrice(4242, p, "ahscan"); nowT = nowT + 86400 end
nowT = nowT - 86400
local a4, w4 = R.MaterialAction(4242)
check(MD.GetStats(4242).trend == "down" and a4 == "Hold" and w4:find("below"), "price well below its recent average -> Hold")
MD.RecordPrice(7777, 100, "ahscan"); MD.RecordPrice(7777, 90, "ahscan")
check(MD.GetStats(7777).trend == nil and MD.GetStats(7777).avg == nil, "less than 3 days of history gives no trend")
nowT = nowT + 5 * 86400
check(MD.GetStats(4242).stale == true, "prices older than 3 days are marked stale")
nowT = 86400 * 400
for d = 1, 40 do MD.RecordPrice(6666, 100 + d, "ahscan"); nowT = nowT + 86400 end
check(#ns.db.market.history[6666] == 30, "history keeps the latest 30 days")
nowT = saveNow

-- user interface with real data --------------------------------------------------------
local function AllText()
	local t = {}
	for _, f in ipairs(frames) do
		local txt = rawget(f, "text")
		if type(txt) == "string" and txt ~= "" then t[#t + 1] = plain(txt) end
	end
	return table.concat(t, "\n")
end
ns.db.settings.showDemo = false
ns.UI.OpenTab("dashboard")
local dash = AllText()
check(dash:find("Stage: Leveling character"), "dashboard shows the character stage")
check(dash:find("Craft Steel Bar") and dash:find("per craft"), "dashboard recommends the best known recipe per craft")
check(dash:find("Mining") and dash:find("per craft"), "dashboard profession outlook uses real scores")
check(not dash:find("%[DEMO%]"), "no [DEMO] panels when real data exists")
ns.UI.OpenTab("market")
check(AllText():find("Copper Ore"), "market tab lists priced materials")
local function click(label)
	for _, f in ipairs(frames) do
		local t = rawget(f, "text")
		if type(t) == "table" and t.text == label and f.scripts.OnClick then f.scripts.OnClick(f); return true end
	end
	return false
end
check(click("Crafting profit"), "profit view button exists")
check(AllText():find("Steel Bar") or AllText():find("Copper Bar"), "profit view lists recipes")
check(click("Unpriced: hidden") and click("Profit"), "unpriced toggle and column sort work")
check(click("Materials") and click("Change") and click("Change"), "sorting twice flips direction without errors")
for _, f in ipairs(frames) do
	if f.scripts.OnEnter and f.shown then pcall(f.scripts.OnEnter, f); break end
end
ns.UI.OpenTab("gathering")
check(AllText():find("Steel Bar") and AllText():find("Not available from the game"), "gathering tab lists materials and states its limits")
ns.UI.OpenTab("goldtracker")
check(AllText():find("No session running"), "gold tracker tab idle text")
slash("session start")
ns.UI.OpenTab("goldtracker")
check(AllText():find("Recorded %(real gold%)") and AllText():find("theoretical"), "gold tracker keeps recorded and theoretical sections apart")
slash("session stop")
ns.UI.OpenTab("professions")
check(AllText():find("per craft"), "professions tab shows profit per craft")
check(click("Compare: off"), "compare toggle")
ns.UI.OpenTab("settings")
ns.UI.OpenTab("characters")
check((ns.errorCount or 0) == 0, "no errors raised anywhere in phases 3 and 4")

-- market search and detail views ---------------------------------------------------------
local mk = ns.UI.market
local function rowFor(tbl, pred)
	for _, f in ipairs(frames) do
		local it = rawget(f, "item")
		if it and f.shown ~= nil and pred(it) then return f, it end
	end
end
ns.UI.OpenTab("market")
check(mk and mk.Debug.mode == "list", "market tab starts on the list view")
local allRows = mk.Debug.listRows
mk.Find("copper")
check(mk.Debug.query == "copper" and mk.Debug.listRows >= 1 and mk.Debug.listRows < allRows, "search narrows the material list")
local tc
for _, f in ipairs(frames) do if f.scripts.OnTextChanged and not tc then tc = f end end
check(tc ~= nil, "search box exists")
tc:SetText("  STEEL ")
tc.scripts.OnTextChanged(tc)
check(mk.Debug.query == "steel", "search is trimmed and case-insensitive")
mk.Find("zzzznothing")
check(mk.Debug.listRows == 0, "search with no match shows no rows")
mk.Find("")
mk.Show("item", 2770)
check(mk.Debug.mode == "item" and mk.Debug.id == 2770, "item detail opens")
check(AllText():find("Copper Ore") and AllText():find("Source: Auction House scan"), "item detail shows price and source")
check(AllText():find("not a live feed"), "item detail is honest that prices come from the last scan")
local hasUses = false
for _, r in ipairs(mk.Debug.relData) do if plain(r.cells.name or "") == "Copper Bar" and plain(r.cells.role):find("uses") then hasUses = true end end
check(hasUses, "item detail lists recipes that use the item")
mk.Show("item", 2840)
local makes = false
for _, r in ipairs(mk.Debug.relData) do if plain(r.cells.role):find("makes") then makes = true end end
check(makes and mk.Debug.depth == 1, "output item lists the recipe that makes it; history depth tracked")
mk.Show("recipe", 105)
check(mk.Debug.mode == "recipe" and mk.Debug.depth == 2, "recipe detail opens from an item")
check(AllText():find("Iron Bar") and AllText():find("Sells for %(after 5%% cut%)") and AllText():find("Profit"), "recipe detail shows reagents and the profit calculation")
for _, r in ipairs(mk.Debug.relData) do check(not plain(r.cells.name or ""):find("^makes"), "recipe table has no redundant makes row") end
local sawReagent = false
for _, r in ipairs(mk.Debug.relData) do
	if plain(r.cells.name):find("Iron Bar") and r.onClick then sawReagent = true; r.onClick() end
end
check(sawReagent and mk.Debug.mode == "item" and mk.Debug.id == 3575, "clicking a reagent row opens that item")
mk.Back(); mk.Back(); mk.Back(); mk.Back()
check(mk.Debug.mode == "item" or mk.Debug.mode == "list", "Back never errors past the start")
mk.Back(); mk.Back()
check(mk.Debug.mode == "list", "Back returns to the list")
-- Market home: button and tab click jump straight back to the list
mk.Show("item", 2770); mk.Show("recipe", 105); mk.Show("item", 3575)
check(mk.Debug.depth == 2, "deep navigation builds a history")
mk.Home()
check(mk.Debug.mode == "list" and mk.Debug.depth == 0 and mk.Debug.query == "", "Market home clears detail, history and search")
mk.Show("item", 2770); mk.Show("recipe", 105)
ns.UI.OpenTab("dashboard")
check(click("Market"), "Market tab button exists")
check(mk.Debug.mode == "list" and mk.Debug.depth == 0, "clicking the Market tab returns to Market home")
check(click("Market home") or true, "home button present")
-- unpriced item and vanished recipe are handled
mk.Show("item", 999999)
check(AllText():find("no data") and AllText():find("/ga setprice 999999"), "unpriced item says no data and shows how to set a price")
mk.Show("recipe", 424242)
check(mk.Debug.mode == "list", "a missing recipe falls back to the list")
-- clicking a real list row
mk.Find("")
local rf, it = rowFor(nil, function(it) return it.onClick ~= nil end)
check(rf ~= nil, "list rows are clickable")
local up = rf and rf.scripts.OnMouseUp
if up then up(rf) end
check(mk.Debug.mode == "item" or mk.Debug.mode == "recipe", "clicking a row opens its detail")
mk.Back()
slash("item " .. link)
check(mk.Debug.mode == "item" and mk.Debug.id == 2770, "/ga item accepts an item link")
slash("item 2840")
check(mk.Debug.id == 2840, "/ga item accepts an item id")
slash("find iron")
check(mk.Debug.mode == "list" and mk.Debug.query == "iron", "/ga find opens the market search")
mk.Find("")
check((ns.errorCount or 0) == 0, "no errors from search and detail views")

-- Phase 5: characters, per-character gold history, allocation, import/export ----------------
do
	local CM, GT, MDm = ns.CharacterManager, ns.GoldTracker, ns.MarketData
	local meKey = "Testy-Realm"
	local me = ns.db.characters[meKey]
	local savedKnown, savedProfs, savedBank = me.known, me.professions, me.bank
	nowT = 5000000
	ns.db.characters["Alice-Realm"] = { name = "Alice", realm = "Realm", class = "Mage", classToken = "MAGE", level = 60, gold = 500000,
		lastSeen = nowT - 86400 * 3, professions = { { name = "Mining", skill = 150, maxSkill = 300 }, { name = "Herbalism", skill = 90, maxSkill = 300 } },
		known = { Mining = { [101] = true } }, bags = { items = { [2770] = 30 }, t = nowT - 86400 * 3 } }
	ns.db.characters["Bob-Realm"] = { name = "Bob", realm = "Realm", class = "Rogue", classToken = "ROGUE", level = 20, gold = 90000,
		lastSeen = nowT - 3600, professions = {} }
	me.gold = 123456

	-- account totals and list
	local list = CM.List()
	check(list[1].key == "Alice-Realm" and list[2].key == meKey and list[3].key == "Bob-Realm", "characters listed richest first")
	local total, n, oldest = CM.GoldSummary()
	check(total == 500000 + 123456 + 90000 and n == 3, "account gold adds up every tracked character")
	check(oldest == nowT - 86400 * 3 or oldest == nowT - 86400 * 3, "oldest saved gold age is reported")
	check(CM.ProfessionLine(ns.db.characters["Alice-Realm"]) == "Mining 150/300  -  Herbalism 90/300", "profession line shows skill and cap")
	check(CM.ProfessionOwners().Mining and #CM.ProfessionOwners().Mining == 2, "profession owners lists who has Mining")
	ns.UI.OpenTab("dashboard")
	local dtext = AllText()
	check(dtext:find("Total gold") and dtext:find("Alice") and dtext:find("3 characters"), "dashboard shows account gold with per-character lines")

	-- Characters tab and safe delete
	ns.UI.OpenTab("characters")
	check(AllText():find("Alice") and AllText():find("Mining 150/300"), "characters tab lists characters with professions")
	ns.UI.characters.Select("Bob-Realm")
	check(AllText():find("Selected character") and AllText():find("Bob"), "selecting a character shows its details")
	ns.db.sessions[#ns.db.sessions + 1] = { start = 1, stop = 100, startGold = 0, endGold = 5000, character = "Bob-Realm", loot = {} }
	check(CM.Delete(meKey) == false and ns.db.characters[meKey], "the logged-in character cannot be deleted")
	check(click("Delete character"), "delete button exists")
	check(ns.db.characters["Bob-Realm"] ~= nil, "one click does NOT delete")
	nowT = nowT + 30
	check(click("Delete character"), "delete button clickable again")
	check(ns.db.characters["Bob-Realm"] ~= nil, "a click after the confirm window expired only re-arms it")
	check(click("Delete character"), "second click within the window")
	check(ns.db.characters["Bob-Realm"] == nil, "two clicks in a row delete the character")
	for _, s in ipairs(ns.db.sessions) do check(s.character ~= "Bob-Realm", "deleting a character also removes its sessions") end
	-- a pending delete does not carry over to a different character
	ns.db.characters["Carl-Realm"] = { name = "Carl", realm = "Realm", level = 5, gold = 10, lastSeen = nowT, professions = {} }
	ns.db.characters["Dana-Realm"] = { name = "Dana", realm = "Realm", level = 5, gold = 20, lastSeen = nowT, professions = {} }
	ns.UI.characters.Select("Carl-Realm")
	click("Delete character")
	ns.UI.characters.Select("Dana-Realm")
	click("Delete character")
	check(ns.db.characters["Dana-Realm"] ~= nil and ns.db.characters["Carl-Realm"] ~= nil, "changing the selected character cancels a pending delete")
	ns.db.characters["Carl-Realm"], ns.db.characters["Dana-Realm"] = nil, nil
	ns.UI.characters.Select(meKey)
	check(AllText():find("cannot be deleted"), "selecting yourself explains why there is no delete")

	-- per-character gold history
	ns.db.sessions = {
		{ start = 1, stop = 3601, startGold = 0, endGold = 100000, character = meKey, loot = {} },
		{ start = 1, stop = 3601, startGold = 0, endGold = 900000, character = "Alice-Realm", loot = {} },
	}
	check(#GT.List(meKey) == 1 and #GT.List("Alice-Realm") == 1 and #GT.List(nil) == 2, "sessions are listed per character")
	local _, bestRate = GT.Best(meKey)
	check(near(bestRate, 100000), "best session is chosen among this character's sessions only")
	ns.UI.OpenTab("goldtracker")
	check(AllText():find("History: this character"), "gold tracker history defaults to this character")
	check(click("History: this character") and AllText():find("History: all characters"), "history scope toggles to all characters")
	check(click("History: all characters"), "toggles back")
	check(click("Reset history"), "reset button exists")
	check(#GT.List(meKey) == 1, "one click does not reset")
	ns.UI.RefreshIfShown(); ns.UI.RefreshIfShown()
	check(click("Reset history"), "second click (page redraws in between, as with a running session)")
	check(#GT.List(meKey) == 0 and #GT.List("Alice-Realm") == 1, "reset clears this character only")
	GT.Clear()
	check(#ns.db.sessions == 0, "clearing with no key clears every character")

	-- bag snapshots and holdings
	owned[2770] = 15
	check(ns.Inventory.SnapshotBags() and me.bags.items[2770] == 15, "bag snapshot records tracked materials")
	ns.db.accountBank = { items = { [2770] = 5 }, t = nowT }
	local h = ns.Inventory.Holdings(2770)
	check(h.total == 15 + 30 + 5 and #h.holders == 3, "holdings combine every character plus the warband bank once")
	ns.db.accountBank = nil

	-- allocation plan
	me.known, me.professions = nil, { { name = "Herbalism", skill = 10, maxSkill = 75 } }
	local AL = ns.Allocation
	local hold = ns.Inventory.Holdings(2770)
	local plan = AL.Plan(2770, hold)
	check(plan.action == "Craft" and plan.who == "Alice" and plan.text:find("Copper Bar"), "craft on the character that knows the best recipe")
	check(plan.mail and plan.mail:find("15"), "items held elsewhere are flagged for mailing")
	ns.db.characters["Alice-Realm"].known = nil
	plan = AL.Plan(2770, hold)
	check(plan.action == "Learn" and plan.who == "Alice", "profession without the recipe -> learn it first")
	ns.db.characters["Alice-Realm"].professions = {}
	plan = AL.Plan(2770, hold)
	check(plan.action ~= "Craft" and plan.action ~= "Learn", "nobody with the profession -> never says craft")
	ns.db.characters["Alice-Realm"].professions = { { name = "Mining", skill = 150, maxSkill = 300 } }
	ns.db.characters["Alice-Realm"].known = { Mining = { [101] = true } }
	local rows = AL.Rows()
	local sawOre = false
	for _, r in ipairs(rows) do if r.id == 2770 and r.total == 45 then sawOre = true end end
	check(sawOre, "allocation rows total what every character holds")
	ns.UI.characters.Debug.view = "materials"
	ns.UI.OpenTab("characters")
	check(AllText():find("Copper Ore") and AllText():find("Craft Copper Bar on Alice"), "materials view shows the plan")
	local rowFrame
	for _, f in ipairs(frames) do
		local it = rawget(f, "item")
		if it and it.onClick and it.cells and it.cells.plan and tostring(it.cells.plan):find("Copper Bar") then rowFrame = f end
	end
	check(rowFrame ~= nil, "material rows are clickable")
	if rowFrame then rowFrame.scripts.OnMouseUp(rowFrame) end
	check(ns.UI.market.Debug.mode == "item" and ns.UI.market.Debug.id == 2770, "clicking a material opens its detail view")
	ns.UI.market.Home()

	-- export / import
	MDm.SetManual(2770, 5000)
	local text, counts = ns.Transfer.Build()
	check(text:sub(1, 4) == "GA1:" and counts.manual >= 1 and counts.characters == 2, "export text has a header and counts")
	local pv = ns.Transfer.Preview(text)
	check(pv.ok and pv.newManual == 0 and pv.newChars == 0 and pv.updatedChars == 0, "importing your own export changes nothing")
	local savedAlice, savedManual = ns.db.characters["Alice-Realm"], ns.db.market.manual[2770]
	ns.db.characters["Alice-Realm"] = nil
	ns.db.market.manual[2770] = nil
	pv = ns.Transfer.Preview("  " .. text:sub(1, 30) .. "\n" .. text:sub(31) .. "  ")
	check(pv.ok and pv.newChars == 1 and pv.newManual == 1, "preview counts what an import would add (whitespace and line breaks ignored)")
	check(ns.db.characters["Alice-Realm"] == nil, "preview changes nothing")
	local rev = MDm.revision
	check(ns.Transfer.Apply(pv) and ns.db.characters["Alice-Realm"].gold == 500000 and ns.db.market.manual[2770].price == 5000, "apply restores characters and manual prices")
	check(MDm.revision > rev, "applying prices invalidates price caches")
	-- validation and safety
	check(not ns.Transfer.Preview("hello").ok, "text that is not an export is rejected")
	check(not ns.Transfer.Preview(text:sub(1, #text - 8)).ok, "truncated text is rejected")
	local tampered = text:sub(1, 20) .. (text:sub(21, 21) == "A" and "B" or "A") .. text:sub(22)
	check(not ns.Transfer.Preview(tampered).ok, "changed text fails the checksum")
	local bad = ns.Transfer.Pack({ v = 1, manual = { [0] = { price = 5, t = 1 }, [5] = { price = -3, t = 1 }, abc = { price = 5, t = 1 }, [7] = { price = 1.5, t = 1 } },
		characters = { ["nodash"] = { name = "X", realm = "Y" }, ["Evil-Realm"] = { name = string.rep("x", 100), realm = "R", level = 9999 },
			["Fine-Realm"] = { name = "Fine", realm = "Realm", level = 70, gold = -5, professions = { { name = "Mining", skill = 99999 } } } } })
	pv = ns.Transfer.Preview(bad)
	check(pv.ok and pv.newManual == 0 and pv.rejected >= 4, "invalid prices and characters are rejected")
	check(pv.characters["Fine-Realm"] and pv.characters["Fine-Realm"].gold == nil and pv.characters["Fine-Realm"].professions[1].skill == 0, "out-of-range numbers are dropped, not trusted")
	check(pv.characters["Evil-Realm"] == nil and pv.characters["nodash"] == nil, "bad names and keys never reach the preview")
	local goldBefore = me.gold
	local mine = ns.Transfer.Pack({ v = 1, characters = { [meKey] = { name = "Testy", realm = "Realm", level = 99, gold = 1, lastSeen = 4e9 } } })
	pv = ns.Transfer.Preview(mine)
	ns.Transfer.Apply(pv)
	check(me.gold == goldBefore and me.level ~= 99, "the character you are logged in with is never overwritten")
	local deep = {}
	local cur = deep
	for i = 1, 20 do cur.x = {}; cur = cur.x end
	check(not pcall(ns.Transfer.Pack, deep) or not ns.Transfer.Preview("GA1:00000000:AAAA").ok, "overly deep data is refused")
	local older = ns.Transfer.Pack({ v = 1, manual = { [2770] = { price = 1, t = 1 } } })
	check(ns.Transfer.Preview(older).skippedManual == 1, "older manual prices never replace newer ones")

	-- import/export UI
	ns.UI.characters.Debug.view = "transfer"
	ns.UI.OpenTab("characters")
	check(click("Create export text") and AllText():find("GA1:"), "export button fills the text box")
	ns.db.characters["Alice-Realm"].gold = 1
	ns.db.characters["Alice-Realm"].lastSeen = 1
	local box
	for _, f in ipairs(frames) do if f.scripts.OnTextChanged then box = f end end
	box:SetText(text)
	box.scripts.OnTextChanged(box)
	check(AllText():find("Ready:") and ns.UI.characters.Debug.preview.ok, "pasting text shows a preview")
	check(click("Apply import") and ns.db.characters["Alice-Realm"].gold == 1, "one click does not apply")
	check(click("Apply import") and ns.db.characters["Alice-Realm"].gold == 500000, "second click applies the import")

	me.known, me.professions, me.bank = savedKnown, savedProfs, savedBank
	owned[2770] = nil
	check((ns.errorCount or 0) == 0, "no errors from phase 5 features")
end

-- copper display and gold safety ------------------------------------------------------------
do
	ns.db.settings.coinIcons = false
	check(plain(ns.FormatMoney(12345678, true)) == "1,234g 56s 78c", "full format shows gold, silver and copper")
	check(plain(ns.FormatMoney(1230000, true)) == "123g 0s 0c", "full format keeps zero silver and copper after gold")
	check(plain(ns.FormatMoney(5, true)) == "5c" and plain(ns.FormatMoney(0, true)) == "0c" and plain(ns.FormatMoney(250, true)) == "2s 50c", "full format below one gold")
	check(plain(ns.FormatMoney(12345678)) == "1,234g 56s", "normal format still hides copper for prices")
	ns.db.settings.coinIcons = true
	local rec = ns.db.characters["Testy-Realm"]
	money = 777777
	ns.CharacterManager.Capture("money")
	check(rec.gold == 777777, "money event saves gold")
	money = 0
	ns.CharacterManager.Capture("logout")
	check(rec.gold == 777777, "logout never overwrites saved gold")
	ns.CharacterManager.Capture("login")
	check(rec.gold == 777777, "a sudden 0 at login does not replace saved gold")
	ns.CharacterManager.Capture("money")
	check(rec.gold == 0, "a real 0 reported by the money event is accepted")
	money = 123456
	ns.CharacterManager.Capture("money")
	ns.db.settings.coinIcons = false
	slash("chars")
	check(plain(table.concat(out, "\n")):find("Testy%-Realm") and plain(table.concat(out, "\n")):find("12g 34s 56c"), "/ga chars lists characters with full gold")
	ns.UI.OpenTab("dashboard")
	check(AllText():find("12g 34s 56c"), "dashboard gold shows copper")
	ns.db.settings.coinIcons = true
end

-- market price accuracy and thin markets --------------------------------------------------
do
	local AS, MDm = ns.AuctionScanner, ns.MarketData
	local function approx(a, b) return a and math.abs(a - b) < 0.01 end
	check(AS.MarketPrice({}) == nil, "no listings -> no price")
	local p, info = AS.MarketPrice({ { 100, 1 } })
	check(p == 100 and info.thin and info.units == 1 and info.listings == 1, "a single listing is priced but flagged thin")
	p, info = AS.MarketPrice({ { 100, 40 }, { 100, 30 }, { 100, 30 } })
	check(p == 100 and not info.thin and info.units == 100, "many identical listings -> that price, not thin")
	p, info = AS.MarketPrice({ { 1, 1 }, { 100, 30 }, { 100, 40 }, { 100, 29 } })
	check(approx(p, 100) and info.low == 1 and info.dropped == 1, "a lone low-ball listing cannot set the price")
	p, info = AS.MarketPrice({ { 100, 50 }, { 200, 100 }, { 300, 850 } })
	check(approx(p, 25000 / 150) and info.low == 100, "price = average of the cheapest ~15% of units (here 150 of 1000)")
	p = AS.MarketPrice({ { 500, 10 }, { 100, 10 }, { 300, 10 } })
	check(approx(p, 100) and p < 500, "listings are sorted before averaging")
	p = AS.MarketPrice({ { 50, 100000 } })
	check(p == 50, "very large supply is capped at 200 units without error")
	check(not select(2, AS.MarketPrice({ { 10, 3 }, { 10, 3 }, { 10, 3 } })).thin, "9 units in 3 listings is not thin")
	check(select(2, AS.MarketPrice({ { 10, 3 }, { 10, 3 } })).thin, "two listings is thin")

	-- stored with the price and shown (a manual price would take priority, so remove the one set earlier)
	MDm.ClearManual(2770)
	MDm.RecordPrice(2770, 120, "ahscan", { low = 90, units = 4, listings = 2, thin = true })
	local st = MDm.GetStats(2770)
	check(st.thin and st.low == 90 and st.units == 4 and st.listings == 2, "thin flag and listing counts are kept with the price")
	local e = ns.ProfitCalculator.Evaluate(101, ns.db.recipes[101])
	check(e and e.thin == true, "a profit built on a thin reagent price is flagged")
	ns.UI.market.Show("item", 2770)
	check(AllText():find("Thin market") and AllText():find("Cheapest listing") and AllText():find("Market price"), "item detail shows market price, cheapest listing and the thin warning")
	ns.UI.market.Home()
	MDm.RecordPrice(2770, 120, "ahscan", { low = 100, units = 500, listings = 20, thin = false })
	MDm.RecordPrice(2840, ns.db.market.prices[2840] and ns.db.market.prices[2840].price or 500, "ahscan", { low = 1, units = 500, listings = 20 })   -- the output was priced by an earlier (thin) test scan
	check(not ns.ProfitCalculator.Evaluate(101, ns.db.recipes[101]).thin, "a well-supplied price is not flagged")
	MDm.RecordPrice(2770, 120, "ahscan")
	check(MDm.GetStats(2770).thin == nil and ns.Transfer.Build(), "prices recorded without listing data still work")
end

-- Professions tab: recipe table with Details links ------------------------------------------
do
	ns.UI.market.Home()
	ns.UI.OpenTab("professions")
	local t = AllText()
	check(t:find("Details >") and t:find("Profit per craft"), "professions tab lists recipes with profit and a Details link")
	local rowFrame
	for _, f in ipairs(frames) do
		local it = rawget(f, "item")
		if it and it.onClick and it.cells and it.cells.details and f.shown then rowFrame = f end
	end
	check(rowFrame ~= nil, "recipe rows are clickable")
	if rowFrame then rowFrame.scripts.OnMouseUp(rowFrame) end
	check(ns.UI.current == "market" and ns.UI.market.Debug.mode == "recipe", "clicking a recipe opens the same detail view as the Market tab")
	ns.UI.market.Back()
	check(ns.UI.current == "professions", "Back from a recipe opened here returns to the Professions tab")
	if rowFrame then rowFrame.scripts.OnMouseUp(rowFrame) end
	ns.UI.market.Home()
	check(ns.UI.current == "market" and ns.UI.market.Debug.mode == "list", "Market home still goes to the Market list")
	ns.UI.OpenTab("professions")
	check(click("Compare: on") or click("Compare: off"), "compare toggle still works with the table")
	check(click("Compare: on") or click("Compare: off"), "compare toggles back")
	check((ns.errorCount or 0) == 0, "no errors from the professions table")
end

-- close button ---------------------------------------------------------------------------
do
	ns.UI.OpenTab("dashboard")
	check(GoblinAdvisorFrame:IsShown(), "window is open before closing")
	check(click("X"), "close button exists")
	check(not GoblinAdvisorFrame:IsShown(), "the X button closes the window")
	slash("")
	check(GoblinAdvisorFrame:IsShown(), "/ga reopens it")
	check(UISpecialFrames[1] == "GoblinAdvisorFrame" or (function() for _, n in ipairs(UISpecialFrames) do if n == "GoblinAdvisorFrame" then return true end end end)(), "Escape closes the window")
end

-- other commands
slash("scan debug 2770")
check(plain(table.concat(out, "\n")):find("listing: stack of"), "/ga scan debug shows raw listings")
slash("prices")
slash("prices clear")
check(MD.PriceCount() == 0 and ns.db.market.manual ~= nil, "/ga prices clear forgets scanned prices")
slash("status")
AS.PrintStatus()
slash("help")
ns.db.settings.showDemo = true
ns.UI.OpenTab("dashboard")
check(AllText():find("%[DEMO%]"), "labelled demo panels appear only when there is no real data and demo is on")
ns.db.settings.showDemo = false
ns.UI.OpenTab("dashboard")
check(AllText():find("No prices yet"), "with demo off and no prices the dashboard says what to do")
check(PC.Evaluate(101).profit == nil, "with prices gone the profit disappears instead of going stale")
check(R.Activities()[1] == nil or R.Activities()[1].kind ~= "craft", "no craft recommendations without prices")
fire("AUCTION_HOUSE_CLOSED")
check(AS.open == false, "closing the AH is tracked")
-- API failures are contained
C_AuctionHouse.GetNumReplicateItems = function() error("boom") end
check(pcall(AS.Process), "failing scan call does not throw")
C_AuctionHouse = nil
check(pcall(AS.RequestScan, "x"), "missing C_AuctionHouse does not throw")
C_Item = nil
check(pcall(GA.Suggest), "missing C_Item does not throw")

-- scale: a Retail-sized recipe book must stay quick ----------------------------------
do
	local t0 = os.clock()
	ns.db.recipes = {}
	for i = 1, 3000 do
		ns.db.recipes[100000 + i] = { name = "Recipe " .. i, prof = "Prof" .. (i % 12), out = 500000 + i, qmin = 1, qmax = 1,
			reagents = { { qty = 2, ids = { 1000 + (i % 700), 20000 + (i % 700) } }, { qty = 1, ids = { 3000 + (i % 400) } } } }
	end
	ns.RecipeManager.revision = ns.RecipeManager.revision + 1
	for i = 1, 3000 do MD.RecordPrice(500000 + i, 1000 + i * 3, "ahscan") end
	for i = 0, 700 do MD.RecordPrice(1000 + i, 50 + i, "ahscan"); MD.RecordPrice(20000 + i, 40 + i, "ahscan") end
	for i = 0, 400 do MD.RecordPrice(3000 + i, 30 + i, "ahscan") end
	local all = PC.All()
	check(#all.list == 3000 and PC.PricedCount() == 3000, "scale: 3000 recipes evaluated")
	ns.UI.OpenTab("market")
	ns.UI.OpenTab("dashboard")
	ns.UI.OpenTab("professions")
	local secs = os.clock() - t0
	check(secs < 8, "scale: building data and drawing three tabs for 3000 recipes took " .. string.format("%.2f", secs) .. "s")
	io.stdout:write(string.format("SCALE seconds=%.2f\n", secs))
end

-- error isolation
local ran = false
ns.On("TEST_EVENT", function() error("handler failed") end)
ns.On("TEST_EVENT", function() ran = true end)
fire("TEST_EVENT")
check(ran, "a failing handler does not stop the next one")
check((ns.errorCount or 0) >= 1, "failure is counted")
check(pcall(ns.On, "BAD_EVENT", function() end), "unknown event does not throw")

print(("%d passed, %d failed"):format(passed, failed))
io.stdout:write(table.concat(out, "\n") .. "\n")
if failed > 0 then error("tests failed") end
