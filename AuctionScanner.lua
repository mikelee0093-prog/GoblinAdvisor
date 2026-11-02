-- Goblin Advisor: AuctionScanner
-- Reads prices from the Auction House. READ ONLY: it never posts, buys, bids or cancels.
-- It uses the client's full-scan call (ReplicateItems), which Blizzard limits to roughly one
-- scan per 15 minutes shared by all addons, so it also picks up scans other addons trigger.
-- Only items our recorded recipes need are kept, so the saved data stays small.
local _, ns = ...

local AS = {}
ns.AuctionScanner = AS

local BATCH = 1500
local COOLDOWN = 15 * 60
local REFRESH_AFTER = 5 * 60   -- re-read unchanged scan data at most this often
local RETRY_AFTER = 60         -- ...or sooner, a couple of times, if many listings lacked item data
local MAX_RETRIES = 2

AS.open = false
AS.scanning = false
AS.lastRequest = nil
AS.lastResult = nil      -- { seen, kept, incomplete, time }
AS.requested = false     -- we asked for a scan and have not processed its data yet
AS.lastTotal = nil       -- listing count at the last processing
AS.lastProcessedAt = nil
AS.retries = 0
AS.processCount = 0

-- Every item a recorded recipe uses or makes, plus anything with a manual price.
function AS.Wanted()
	local want, n = {}, 0
	local function add(id) if id and not want[id] then want[id] = true; n = n + 1 end end
	for _, r in pairs(ns.db.recipes) do
		add(r.out)
		for _, slot in ipairs(r.reagents) do
			for _, id in ipairs(slot.ids) do add(id) end
		end
	end
	for id in pairs(ns.db.market.manual) do add(id) end
	return want, n
end

function AS.RequestScan(reason)
	if not AS.open then
		ns.Print("open the Auction House first, then scan.")
		return false
	end
	if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
		ns.Print("this client has no full-scan call (C_AuctionHouse.ReplicateItems).")
		return false
	end
	local now = ns.MarketData.Now()
	if AS.lastRequest and now - AS.lastRequest < COOLDOWN then
		ns.Print("a scan was requested less than 15 minutes ago; the game may refuse another until then.")
	end
	AS.lastRequest = now
	local ok, err = pcall(C_AuctionHouse.ReplicateItems)
	if not ok then ns.Error("ReplicateItems", err); return false end
	AS.requested = true
	ns.Debug("scan requested", tostring(reason))
	return true
end

-- Called when the client says scan data is ready.
-- That event fires again whenever item data finishes loading (for example while you hover
-- items in the Auction House), so repeats are ignored unless the data really is new:
-- we asked for a scan, the number of listings changed, or enough time has passed.
-- force = true skips that check (used by tests).
function AS.Process(force)
	if AS.scanning or not ns.db then return end
	if not (C_AuctionHouse and C_AuctionHouse.GetNumReplicateItems) then return end
	local okN, total = pcall(C_AuctionHouse.GetNumReplicateItems)
	if not okN or type(total) ~= "number" or total <= 0 then return end

	local now = ns.MarketData.Now()
	if not force then
		local last = AS.lastProcessedAt
		local newData = AS.requested or not last or total ~= AS.lastTotal
		local retry = false
		if not newData and last then
			local r = AS.lastResult
			retry = r and r.incomplete > 0 and AS.retries < MAX_RETRIES and now - last >= RETRY_AFTER
			if not retry and now - last < REFRESH_AFTER then return end
			if retry then AS.retries = AS.retries + 1 end
		end
		if newData then AS.retries = 0 end
	end
	AS.requested = false
	AS.lastTotal = total
	AS.lastProcessedAt = now
	AS.processCount = AS.processCount + 1

	local want, wantN = AS.Wanted()
	if wantN == 0 then
		ns.Print("scan data is ready, but no recipes are recorded yet. Open your profession windows first, then scan again.")
		return
	end

	local perUnit = ns.db.settings.scanPriceIsUnit
	local best, seen, incomplete, i = {}, 0, 0, 0
	AS.scanning = true

	local function finish()
		local kept = 0
		for id, price in pairs(best) do
			if ns.MarketData.RecordPrice(id, price, "ahscan") then kept = kept + 1 end
		end
		ns.db.market.lastScan = ns.MarketData.Now()
		AS.lastResult = { seen = seen, kept = kept, incomplete = incomplete, time = ns.db.market.lastScan }
		AS.scanning = false
		ns.Print(("scan done: %d listings read, prices updated for %d of %d tracked items."):format(seen, kept, wantN))
		if incomplete > 0 and incomplete > seen * 0.2 then
			ns.Print(ns.Color("orange", "many listings had incomplete item data; scan again in a few minutes for better coverage."))
		end
		ns.UI.RefreshIfShown()
	end

	local function step()
		local stop = math.min(i + BATCH - 1, total - 1)
		for j = i, stop do
			-- name, texture, count, quality, usable, level, levelType, minBid, minIncrement,
			-- buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName,
			-- saleStatus, itemID, hasAllInfo
			local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
				pcall(C_AuctionHouse.GetReplicateItemInfo, j)
			if ok then
				seen = seen + 1
				buyout, count, itemID = ns.Safe(buyout), ns.Safe(count), ns.Safe(itemID)
				if type(itemID) ~= "number" then
					incomplete = incomplete + 1
				elseif want[itemID] and type(buyout) == "number" and buyout > 0 then
					local unit = buyout
					if not perUnit then unit = buyout / math.max(tonumber(count) or 1, 1) end
					if not best[itemID] or unit < best[itemID] then best[itemID] = unit end
				end
			end
		end
		i = stop + 1
		if i < total then C_Timer.After(0, step) else finish() end
	end
	step()
end

-- Raw look at one item's listings, to check whether buyout prices are per stack or per unit.
function AS.Debug(itemID)
	if not AS.open then ns.Print("open the Auction House after a scan first."); return end
	local okN, total = pcall(C_AuctionHouse.GetNumReplicateItems)
	if not okN or not total or total == 0 then ns.Print("no scan data loaded yet."); return end
	local shown = 0
	for j = 0, total - 1 do
		local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, id = pcall(C_AuctionHouse.GetReplicateItemInfo, j)
		if ok and id == itemID then
			ns.Print(("listing: stack of %s, buyout %s (%s)"):format(tostring(count), tostring(buyout), ns.FormatMoney(buyout)))
			shown = shown + 1
			if shown >= 5 then break end
		end
	end
	if shown == 0 then ns.Print("no listings for item " .. itemID .. " in the current scan data.") end
	local st = ns.MarketData.GetStats(itemID)
	ns.Print("stored price: " .. (st and ns.FormatMoney(st.price) or "none"))
	ns.Print("If the stored price looks like a whole stack's price, toggle 'scan price is per unit' in Settings the other way and rescan.")
end

function AS.PrintStatus()
	ns.Print("auction scanner:")
	print("  Auction House open: " .. tostring(AS.open))
	print("  full-scan call: " .. ((C_AuctionHouse and C_AuctionHouse.ReplicateItems) and "present" or "MISSING"))
	local r = AS.lastResult
	if r then
		print(("  last scan: %s, %d listings, %d items priced, %d incomplete"):format(ns.MarketData.FormatAge(r.time), r.seen, r.kept, r.incomplete))
	else
		print("  last scan: none this session")
	end
end
