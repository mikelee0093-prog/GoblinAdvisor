-- Goblin Advisor: GoldTracker
-- Manual farming sessions: you press start and stop. Two numbers are kept strictly apart:
--   RECORDED gold  = your actual gold at the end minus the start. It includes everything that
--                    happened in between (vendoring, repairs, purchases), so it is real.
--   MARKET value   = what the looted items would sell for at current scanned prices. This is
--                    theoretical: nothing was sold yet, and unpriced items count as zero.
local _, ns = ...

local GT = {}
ns.GoldTracker = GT

local MAX_SESSIONS = 30
local MIN_SECONDS = 60       -- shorter than this and an hourly rate means nothing

---------------------------------------------------------------- loot messages
-- Turn a client format string such as "You receive loot: %sx%d." into a Lua pattern.
local function FormatToPattern(fmt)
	if type(fmt) ~= "string" then return nil end
	local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
	p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
	return "^" .. p .. "$"
end

local patterns
local function BuildPatterns()
	patterns = {}
	-- multiples first: a plain "%s." pattern would otherwise swallow the "x3" part
	for _, name in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
		local p = FormatToPattern(_G[name])
		if p then patterns[#patterns + 1] = { p, true } end
	end
	for _, name in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
		local p = FormatToPattern(_G[name])
		if p then patterns[#patterns + 1] = { p, false } end
	end
end

local function Active() return ns.db and ns.db.activeSession end

-- Chat loot handler. Only YOUR loot is counted (the client's own "You receive" formats).
function GT.OnLoot(text, ...)
	local s = Active()
	if not s then return end
	text = ns.Safe(text)
	if type(text) ~= "string" then return end          -- secret or missing text: skip, never guess
	if not patterns then BuildPatterns() end

	local link, qty
	for _, pat in ipairs(patterns) do
		local a, b = text:match(pat[1])
		if a then link, qty = a, pat[2] and tonumber(b) or 1; break end
	end
	if not link and #patterns == 0 then
		-- No format strings on this client: fall back to checking the sender's GUID.
		local guid = ns.Safe((select(11, ...)))
		local me = UnitGUID and ns.Safe(UnitGUID("player"))
		if guid and me and guid == me then
			link = text
			qty = tonumber(text:match("|h|rx(%d+)")) or 1
		end
	end
	if not link then return end
	local itemID = tonumber(link:match("|Hitem:(%d+)"))
	if not itemID then return end
	s.loot[itemID] = (s.loot[itemID] or 0) + (qty or 1)
	ns.UI.RefreshIfShown()
end

---------------------------------------------------------------- sessions
local function Zone()
	local ok, z = pcall(function() return GetRealZoneText and GetRealZoneText() or GetZoneText() end)
	return ok and ns.Safe(z) or nil
end

function GT.Start()
	if Active() then return false, "a session is already running" end
	local gold = ns.Safe(GetMoney())
	ns.db.activeSession = {
		start = ns.MarketData.Now(),
		startGold = type(gold) == "number" and gold or nil,
		character = ns.CharacterManager.currentKey,
		zone = Zone(),
		loot = {},
	}
	return true
end

-- Numbers for a session (running or finished). Never throws; missing parts come back nil.
function GT.Snapshot(s)
	local snap = { session = s, loot = {}, unpriced = 0 }
	local stop = s.stop or ns.MarketData.Now()
	snap.seconds = math.max(0, stop - s.start)
	local endGold = s.endGold
	if not s.stop then
		local g = ns.Safe(GetMoney())
		endGold = type(g) == "number" and g or nil
	end
	if endGold and s.startGold then snap.goldChange = endGold - s.startGold end

	local value, materials, items = 0, 0, 0
	for id, qty in pairs(s.loot) do
		items = items + qty
		local st = ns.MarketData.GetStats(id)
		if st then value = value + st.price * qty else snap.unpriced = snap.unpriced + qty end
		local classID = ns.GatheringAdvisor.ItemClass(id)
		if classID == 7 then materials = materials + qty end
		snap.loot[#snap.loot + 1] = { id = id, qty = qty, price = st and st.price or nil }
	end
	table.sort(snap.loot, function(a, b)
		local va, vb = (a.price or 0) * a.qty, (b.price or 0) * b.qty
		if va ~= vb then return va > vb end
		return a.id < b.id
	end)
	snap.items, snap.materials, snap.marketValue = items, materials, value
	if snap.seconds >= MIN_SECONDS then
		local hours = snap.seconds / 3600
		if snap.goldChange then snap.recordedPerHour = snap.goldChange / hours end
		if items > 0 then snap.marketPerHour = value / hours end
	end
	return snap
end

function GT.Stop()
	local s = Active()
	if not s then return false, "no session is running" end
	s.stop = ns.MarketData.Now()
	local g = ns.Safe(GetMoney())
	s.endGold = type(g) == "number" and g or nil
	local snap = GT.Snapshot(s)
	s.marketValue, s.unpriced = snap.marketValue, snap.unpriced   -- freeze the valuation at stop time
	local list = ns.db.sessions
	list[#list + 1] = s
	-- keep the newest MAX_SESSIONS finished sessions for each character
	local mine = 0
	for i = #list, 1, -1 do
		if list[i].character == s.character then
			mine = mine + 1
			if mine > MAX_SESSIONS then table.remove(list, i) end
		end
	end
	ns.db.activeSession = nil
	return true, snap
end

-- Finished sessions of one character (oldest first); a nil key means every character.
function GT.List(charKey)
	local out = {}
	for _, s in ipairs(ns.db.sessions) do
		if charKey == nil or s.character == charKey then out[#out + 1] = s end
	end
	return out
end

-- Forget finished sessions: one character's, or (nil key) everything including a running session.
function GT.Clear(charKey)
	if charKey == nil then ns.db.sessions = {}; ns.db.activeSession = nil; return end
	local kept = {}
	for _, s in ipairs(ns.db.sessions) do
		if s.character ~= charKey then kept[#kept + 1] = s end
	end
	ns.db.sessions = kept
end

-- Best finished session by recorded gold per hour (one character's, or all with a nil key).
function GT.Best(charKey)
	local best, bestRate
	for _, s in ipairs(GT.List(charKey)) do
		local snap = GT.Snapshot(s)
		if snap.recordedPerHour and snap.recordedPerHour > 0 and (not bestRate or snap.recordedPerHour > bestRate) then
			best, bestRate = s, snap.recordedPerHour
		end
	end
	return best, bestRate
end

function GT.FormatDuration(seconds)
	seconds = math.floor(seconds or 0)
	return ("%d:%02d:%02d"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end
