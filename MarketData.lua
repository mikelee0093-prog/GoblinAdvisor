-- Goblin Advisor: MarketData
-- Price-provider layer plus price history. Providers are asked in order and the first one
-- with a price wins. Nothing here ever invents a price: no provider -> nil -> "no data".
--
-- A provider is a table:
--   id, name
--   kind                   "manual" | "live" (scanned in game) | "addon" | "imported"
--   IsAvailable()          optional, -> boolean
--   GetPrice(itemID)       -> copper, updatedUnixTime   (nil when it has no price)
local _, ns = ...

local MD = {}
ns.MarketData = MD

local providers, order = {}, {}
local HISTORY_DAYS = 30        -- one sample per day, newest last
local DAY = 86400
local TREND_LIMIT = 0.05       -- +-5% against the recent average counts as up / down
local STALE_DAYS = 3

MD.revision = 0                -- bumps whenever a price changes, so caches know to rebuild
MD.DAY = DAY
MD.STALE_DAYS = STALE_DAYS

function MD.Now() return (GetServerTime and GetServerTime()) or (time and time()) or 0 end

---------------------------------------------------------------- providers
function MD.Register(provider)
	if type(provider) ~= "table" or not provider.id or not provider.GetPrice then
		ns.Debug("MarketData.Register: invalid provider")
		return false
	end
	if not providers[provider.id] then order[#order + 1] = provider.id end
	providers[provider.id] = provider
	ns.Debug("market provider registered:", provider.id)
	return true
end

-- Returns { price = copper, source = id, updated = unixTime, kind = kind } or nil.
function MD.GetPrice(itemID)
	for _, id in ipairs(order) do
		local p = providers[id]
		if p.IsAvailable == nil or p.IsAvailable() then
			local ok, price, updated = pcall(p.GetPrice, itemID)
			if ok and type(price) == "number" and price > 0 then
				return { price = price, source = p.id, updated = updated, kind = p.kind }
			end
		end
	end
	return nil
end

function MD.Count() return #order end

-- Built-in providers. Manual prices win over scanned ones: the player knows best (vendor
-- prices, special deals). Both read the SavedVariables lazily, so load order does not matter.
MD.Register({
	id = "manual", name = "Manual prices (/ga setprice)", kind = "manual",
	IsAvailable = function() return ns.db ~= nil end,
	GetPrice = function(itemID)
		local m = ns.db.market.manual[itemID]
		return m and m.price, m and m.t
	end,
})
MD.Register({
	id = "ahscan", name = "Auction House scan", kind = "live",
	IsAvailable = function() return ns.db ~= nil end,
	GetPrice = function(itemID)
		local p = ns.db.market.prices[itemID]
		return p and p.price, p and p.t
	end,
})

---------------------------------------------------------------- writing prices
function MD.RecordPrice(itemID, copper, source, info)
	local m = ns.db and ns.db.market
	if not m or type(itemID) ~= "number" or type(copper) ~= "number" or copper <= 0 then return false end
	copper = math.floor(copper)
	local now = MD.Now()
	local rec = { price = copper, t = now, src = source }
	if type(info) == "table" then rec.low, rec.units, rec.n, rec.thin = info.low, info.units, info.listings, info.thin or nil end
	m.prices[itemID] = rec

	local h = m.history[itemID]
	if not h then h = {}; m.history[itemID] = h end
	local day = math.floor(now / DAY)
	local last = h[#h]
	if last and last.d == day then
		last.p = copper                       -- newest scan of the day replaces the earlier one
	else
		h[#h + 1] = { d = day, p = copper }
		while #h > HISTORY_DAYS do table.remove(h, 1) end
	end
	MD.revision = MD.revision + 1
	return true
end

function MD.SetManual(itemID, copper)
	if type(itemID) ~= "number" or type(copper) ~= "number" or copper <= 0 then return false end
	ns.db.market.manual[itemID] = { price = math.floor(copper), t = MD.Now() }
	MD.revision = MD.revision + 1
	return true
end

function MD.ClearManual(itemID)
	if ns.db.market.manual[itemID] then
		ns.db.market.manual[itemID] = nil
		MD.revision = MD.revision + 1
		return true
	end
	return false
end

function MD.ClearAll()
	ns.db.market.prices, ns.db.market.history = {}, {}
	ns.db.market.lastScan = nil
	MD.revision = MD.revision + 1
end

---------------------------------------------------------------- reading prices
-- Everything the UI needs to know about one item's price.
--   price, source, kind, updated, ageDays, stale
--   avg, samples, change, trend   (only for scanned prices with enough history)
function MD.GetStats(itemID)
	local p = MD.GetPrice(itemID)
	if not p then return nil end
	local s = { price = p.price, source = p.source, kind = p.kind, updated = p.updated }
	if p.updated then
		s.ageDays = (MD.Now() - p.updated) / DAY
		s.stale = s.ageDays > STALE_DAYS
	end
	if p.source == "ahscan" then
		local raw = ns.db.market.prices[itemID]
		if raw and raw.low then s.low, s.units, s.listings, s.thin = raw.low, raw.units, raw.n, raw.thin or false end
		local h = ns.db.market.history[itemID]
		if h and #h >= 3 then
			-- "recent average" = every sample before the newest one
			local sum = 0
			for i = 1, #h - 1 do sum = sum + h[i].p end
			s.avg = sum / (#h - 1)
			s.samples = #h
			s.change = (p.price - s.avg) / s.avg
			s.trend = s.change > TREND_LIMIT and "up" or (s.change < -TREND_LIMIT and "down" or "flat")
		else
			s.samples = h and #h or 0
		end
	end
	return s
end

function MD.PriceCount()
	local n = 0
	for _ in pairs(ns.db.market.prices) do n = n + 1 end
	return n
end

function MD.FormatAge(t)
	if not t then return "unknown age" end
	local mins = math.max(0, (MD.Now() - t) / 60)
	if mins < 90 then return math.floor(mins + 0.5) .. " min ago" end
	if mins < 60 * 48 then return math.floor(mins / 60 + 0.5) .. " h ago" end
	return math.floor(mins / 1440 + 0.5) .. " days ago"
end

function MD.PrintStatus()
	ns.Print("market data:")
	for _, id in ipairs(order) do
		local p = providers[id]
		local avail = (p.IsAvailable == nil or p.IsAvailable()) and "available" or "unavailable"
		print(("  %s (%s): %s"):format(p.name or p.id, tostring(p.kind), avail))
	end
	if ns.db then
		local nManual = 0
		for _ in pairs(ns.db.market.manual) do nManual = nManual + 1 end
		print(("  scanned prices stored: %d   manual prices: %d"):format(MD.PriceCount(), nManual))
		print("  last scan: " .. (ns.db.market.lastScan and MD.FormatAge(ns.db.market.lastScan) or "never"))
	end
end
