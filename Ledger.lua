-- Goblin Advisor: Ledger
-- A record of what you ACTUALLY sold and bought at the Auction House, read from the invoices in
-- your mailbox. Real numbers only: nothing here is estimated. It starts empty (the game gives
-- addons no past history) and fills in whenever you open your mailbox.
-- Read only: it looks at the mail list; it never takes money or items, or sends anything.
-- UNVERIFIED in game: the invoice call (GetInboxInvoiceInfo) is not documented in docs/api, so
-- its return order follows Retail. Run /ga ledger debug at an open mailbox to check what it sees.
local _, ns = ...

local LG = {}
ns.Ledger = LG

local MAX_ENTRIES = 3000
local DUP_WINDOW = 120            -- seconds: the same invoice seen again within this window is the same mail
local DAY = 86400

LG.stats = { scans = 0, mails = 0, invoices = 0, recorded = 0, lastScan = nil, noApi = false }

---------------------------------------------------------------- item names
-- Invoices give an item NAME, not an id. Map names of items we know about back to ids.
-- Several quality tiers share one name, so those stay unmatched rather than guessed.
local nameCache = { key = nil, map = nil }
local function NameMap()
	local key = tostring(ns.RecipeManager.revision)
	if nameCache.key == key and nameCache.map then return nameCache.map end
	local map = {}
	local function add(id)
		if not (C_Item and C_Item.GetItemNameByID) then return end
		local ok, name = pcall(C_Item.GetItemNameByID, id)
		name = ok and ns.Safe(name)
		if type(name) == "string" and name ~= "" then
			local k = name:lower()
			if map[k] == nil then map[k] = id elseif map[k] ~= id then map[k] = false end
		end
	end
	for _, id in ipairs(ns.Recommendations.MaterialIDs()) do add(id) end
	for _, rec in pairs(ns.db.recipes) do if rec.out then add(rec.out) end end
	nameCache = { key = key, map = map }
	return map
end

function LG.ItemID(name)
	if type(name) ~= "string" then return nil end
	return NameMap()[name:lower()] or nil
end

---------------------------------------------------------------- reading the mailbox
local function Invoice(i)
	-- invoiceType, itemName, playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin, count
	local r = { pcall(GetInboxInvoiceInfo, i) }
	if not r[1] then return nil end
	local invoiceType = ns.Safe(r[2])
	if invoiceType ~= "seller" and invoiceType ~= "buyer" then return nil, invoiceType end
	return {
		type = invoiceType, name = ns.Safe(r[3]),
		bid = tonumber(ns.Safe(r[5])) or 0, buyout = tonumber(ns.Safe(r[6])) or 0,
		deposit = tonumber(ns.Safe(r[7])) or 0, fee = tonumber(ns.Safe(r[8])) or 0,
		count = tonumber(ns.Safe(r[12])) or 1,
	}
end

local function DaysLeft(i)
	local r = { pcall(GetInboxHeaderInfo, i) }
	if not r[1] then return nil end
	return tonumber(ns.Safe(r[8]))      -- sender, subject, money, CODAmount, daysLeft follow the two icons
end

-- Have we recorded this exact invoice already? Mails carry no id, so compare its figures and
-- when it expires (which does not change while it sits in the box).
local function SeenBefore(sig, expires)
	local seen = ns.db.ledger.seen
	for _, s in ipairs(seen) do
		if s.sig == sig and math.abs(s.exp - expires) <= DUP_WINDOW then return true end
	end
	return false
end

local function Remember(sig, expires)
	local seen = ns.db.ledger.seen
	seen[#seen + 1] = { sig = sig, exp = expires }
	local cutoff = ns.MarketData.Now() - DAY
	local kept = {}
	for _, s in ipairs(seen) do if s.exp >= cutoff then kept[#kept + 1] = s end end   -- gone from the box by now
	ns.db.ledger.seen = kept
end

-- Unsold auctions come back as mail with no invoice: "Auction expired: <item>" or
-- "Auction cancelled: <item>". Match the subject against the client's own subject strings
-- (so other languages work too). UNVERIFIED in game; /ga ledger debug lists what it sees.
local function SubjectPattern(fmt)
	if type(fmt) ~= "string" or not fmt:find("%%s") then return nil end
	local esc = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%s", "(.+)")
	return "^" .. esc .. "$"
end

local function UnsoldMail(i)
	local r = { pcall(GetInboxHeaderInfo, i) }
	if not r[1] then return nil end
	local subject = ns.Safe(r[5])
	if type(subject) ~= "string" then return nil end
	for kind, global in pairs({ expired = AUCTION_EXPIRED_MAIL_SUBJECT, cancelled = AUCTION_REMOVED_MAIL_SUBJECT }) do
		local pat = SubjectPattern(global)
		local name = pat and subject:match(pat)
		if name then
			local qty, id = 1, nil
			if GetInboxItem then
				local it = { pcall(GetInboxItem, i, 1) }
				if it[1] then
					id = tonumber(ns.Safe(it[3]))     -- name, itemID, texture, count (UNVERIFIED order)
					qty = tonumber(ns.Safe(it[5])) or 1
				end
			end
			return { kind = kind, name = name, id = id, qty = math.max(1, qty) }
		end
	end
	return nil
end

-- Read the open mailbox. Returns how many new records were added.
function LG.Scan(reason)
	if not (GetInboxNumItems and GetInboxInvoiceInfo) then LG.stats.noApi = true; return 0 end
	LG.stats.noApi = false
	local okN, n = pcall(GetInboxNumItems)
	n = okN and ns.Safe(n)
	if type(n) ~= "number" then return 0 end
	LG.stats.scans = LG.stats.scans + 1
	LG.stats.lastScan = ns.MarketData.Now()
	LG.stats.mails = n
	local now, added = ns.MarketData.Now(), 0
	local L = ns.db.ledger
	L.unsold = L.unsold or {}
	for i = 1, n do
		local inv = Invoice(i)
		if not inv then
			local u = UnsoldMail(i)
			if u then
				local days = DaysLeft(i)
				local expires = now + (days or 0) * DAY
				local sig = table.concat({ "unsold", u.kind, tostring(u.name), u.qty }, "|")
				if not SeenBefore(sig, expires) then
					L.unsold[#L.unsold + 1] = { t = now, kind = u.kind, name = u.name, id = u.id or LG.ItemID(u.name), qty = u.qty, char = ns.CharacterManager.currentKey }
					Remember(sig, expires)
					added = added + 1
				end
			end
		end
		if inv then
			LG.stats.invoices = LG.stats.invoices + 1
			local days = DaysLeft(i)
			local expires = now + (days or 0) * DAY
			local gross = inv.bid > 0 and inv.bid or inv.buyout
			local sig = table.concat({ inv.type, tostring(inv.name), inv.bid, inv.buyout, inv.deposit, inv.fee, inv.count }, "|")
			if gross > 0 and not SeenBefore(sig, expires) then
				L.entries[#L.entries + 1] = {
					t = now, kind = inv.type == "seller" and "sale" or "purchase",
					name = inv.name, id = LG.ItemID(inv.name), qty = math.max(1, inv.count),
					gross = gross, fee = inv.type == "seller" and inv.fee or 0,
					char = ns.CharacterManager.currentKey,
				}
				Remember(sig, expires)
				added = added + 1
			end
		end
	end
	while #L.entries > MAX_ENTRIES do table.remove(L.entries, 1) end
	while #L.unsold > MAX_ENTRIES do table.remove(L.unsold, 1) end
	LG.stats.recorded = LG.stats.recorded + added
	if added > 0 then
		LG.revision = (LG.revision or 0) + 1
		ns.Debug("ledger: recorded", added, "new invoice(s)", tostring(reason))
		ns.UI.RefreshIfShown()
	end
	return added
end

local pending = false
local function Queue(reason)
	if pending then return end
	pending = true
	C_Timer.After(1, function() pending = false; ns.Try("ledger scan", LG.Scan, reason) end)
end
ns.On("MAIL_SHOW", function() Queue("mail show") end)
ns.On("MAIL_INBOX_UPDATE", function() Queue("inbox update") end)

-- What does the mailbox look like to this addon? For checking the invoice call in game.
function LG.Debug()
	if not (GetInboxNumItems and GetInboxInvoiceInfo) then ns.Print("this client has no GetInboxInvoiceInfo."); return end
	local n = ns.Safe(GetInboxNumItems())
	if type(n) ~= "number" or n == 0 then ns.Print("no mail in the box (open your mailbox first)."); return end
	ns.Print(("%d mails:"):format(n))
	for i = 1, math.min(n, 15) do
		local h = { pcall(GetInboxHeaderInfo, i) }
		local inv, other = Invoice(i)
		print(("  #%d from %s, subject %s, money %s, days left %s -> %s"):format(i, tostring(ns.Safe(h[4])), tostring(ns.Safe(h[5])),
			tostring(ns.Safe(h[6])), tostring(ns.Safe(h[8])),
			inv and (inv.type .. " invoice for " .. tostring(inv.name) .. " x" .. inv.count) or (UnsoldMail(i) and ("returned unsold (" .. UnsoldMail(i).kind .. ")") or (other and ("invoice type " .. tostring(other)) or "no invoice"))))
	end
end

---------------------------------------------------------------- numbers
-- Entries inside a window. opts = { since = seconds back (nil = all), char = key (nil = all) }
function LG.Entries(opts)
	opts = opts or {}
	local out, cutoff = {}, opts.since and (ns.MarketData.Now() - opts.since) or nil
	for _, e in ipairs(ns.db.ledger.entries) do
		if (not cutoff or e.t >= cutoff) and (not opts.char or e.char == opts.char) then out[#out + 1] = e end
	end
	return out
end

function LG.Unsold(opts)
	opts = opts or {}
	local out, cutoff = {}, opts.since and (ns.MarketData.Now() - opts.since) or nil
	for _, e in ipairs(ns.db.ledger.unsold or {}) do
		if (not cutoff or e.t >= cutoff) and (not opts.char or e.char == opts.char) then out[#out + 1] = e end
	end
	return out
end

-- crafted = output of a recorded recipe, material = used as a reagent; cached per recipe revision
local classCache = { rev = nil, crafted = {}, material = {} }
local function Class(id)
	if not id then return "other" end
	if classCache.rev ~= ns.RecipeManager.revision then
		classCache = { rev = ns.RecipeManager.revision, crafted = {}, material = {} }
		for _, rec in pairs(ns.db.recipes) do if rec.out then classCache.crafted[rec.out] = true end end
		for _, m in ipairs(ns.Recommendations.MaterialIDs()) do classCache.material[m] = true end
	end
	if classCache.crafted[id] then return "crafted" end
	if classCache.material[id] then return "material" end
	return "other"
end

-- Totals and a per-item table. All money in copper. Realized prices are what you actually got/paid.
function LG.Summary(opts)
	local entries = LG.Entries(opts)
	local s = { entries = entries, sold = 0, fees = 0, bought = 0, items = {}, byClass = { crafted = 0, material = 0, other = 0 } }
	local byKey = {}
	for _, e in ipairs(entries) do
		local key = e.id or ("name:" .. tostring(e.name):lower())
		local it = byKey[key]
		if not it then
			it = { key = key, id = e.id, name = e.name, soldQty = 0, soldGross = 0, soldNet = 0, boughtQty = 0, boughtCost = 0, class = Class(e.id) }
			byKey[key] = it
			s.items[#s.items + 1] = it
		end
		if e.kind == "sale" then
			it.soldQty, it.soldGross, it.soldNet = it.soldQty + e.qty, it.soldGross + e.gross, it.soldNet + (e.gross - e.fee)
			s.sold, s.fees = s.sold + e.gross, s.fees + e.fee
			s.byClass[it.class] = s.byClass[it.class] + (e.gross - e.fee)
		else
			it.boughtQty, it.boughtCost = it.boughtQty + e.qty, it.boughtCost + e.gross
			s.bought = s.bought + e.gross
		end
	end
	s.unsoldQty = 0
	for _, e in ipairs(LG.Unsold(opts)) do
		local key = e.id or ("name:" .. tostring(e.name):lower())
		local it = byKey[key]
		if not it then
			it = { key = key, id = e.id, name = e.name, soldQty = 0, soldGross = 0, soldNet = 0, boughtQty = 0, boughtCost = 0, class = Class(e.id) }
			byKey[key] = it
			s.items[#s.items + 1] = it
		end
		it.unsoldQty = (it.unsoldQty or 0) + e.qty
		s.unsoldQty = s.unsoldQty + e.qty
	end
	s.soldQty = 0
	for _, it in ipairs(s.items) do
		it.unsoldQty = it.unsoldQty or 0
		s.soldQty = s.soldQty + it.soldQty
		-- sell-through: of the items you listed, how many sold (only counts mail seen since install)
		if it.soldQty + it.unsoldQty > 0 then it.sellThrough = it.soldQty / (it.soldQty + it.unsoldQty) end
		if it.soldQty > 0 then it.avgSold = it.soldGross / it.soldQty end
		if it.boughtQty > 0 then it.avgBought = it.boughtCost / it.boughtQty end
		if it.id and it.avgSold then
			local st = ns.MarketData.GetStats(it.id)
			if st then it.market = st.price; it.vsMarket = (it.avgSold - st.price) / st.price end
		end
		it.net = it.soldNet - it.boughtCost
	end
	s.net = s.sold - s.fees - s.bought
	if s.soldQty + s.unsoldQty > 0 then s.sellThrough = s.soldQty / (s.soldQty + s.unsoldQty) end
	return s
end

---------------------------------------------------------------- crafting vs raw
-- For each crafted item you actually sold: what one sold item netted you (real, after the AH cut)
-- against what its reagents would have netted if you had sold them raw instead.
-- Raw value of a reagent = its real average sale in the ledger if you have sold it, otherwise the
-- scanned market price after the 5% cut (an estimate, flagged in "basis"). The cheapest tier is used,
-- like the profit calculator. Nothing is recorded about the crafts themselves.
local AH_CUT = 0.05
function LG.Crafting(opts)
	local sum = LG.Summary(opts)
	local realRaw = {}
	for _, it in ipairs(sum.items) do
		if it.id and it.soldQty > 0 then realRaw[it.id] = it.soldNet / it.soldQty end
	end
	local recipeFor = {}
	local rids = {}
	for rid in pairs(ns.db.recipes) do rids[#rids + 1] = rid end
	table.sort(rids)
	for _, rid in ipairs(rids) do
		local rec = ns.db.recipes[rid]
		if rec.out and not recipeFor[rec.out] then recipeFor[rec.out] = rec end
	end
	local rows, total, counted = {}, 0, 0
	for _, it in ipairs(sum.items) do
		local rec = it.id and it.soldQty > 0 and recipeFor[it.id]
		if rec then
			local row = { id = it.id, name = it.name, soldQty = it.soldQty, netEach = it.soldNet / it.soldQty, recipe = rec }
			local yield = ((rec.qmin or 1) + (rec.qmax or rec.qmin or 1)) / 2
			if yield < 1 then yield = 1 end
			local raw, real, est, missing = 0, 0, 0, false
			for _, slot in ipairs(rec.reagents) do
				local best, kind
				for _, id in ipairs(slot.ids) do
					local v, k = realRaw[id], "real"
					if not v then
						local st = ns.MarketData.GetStats(id)
						if st then v, k = st.price * (1 - AH_CUT), "market" end
					end
					if v and (not best or v < best) then best, kind = v, k end
				end
				if best then
					raw = raw + best * slot.qty
					if kind == "real" then real = real + 1 else est = est + 1 end
				else
					missing = true
				end
			end
			if not missing and #rec.reagents > 0 then
				row.rawPer = raw / yield
				row.gain = row.netEach - row.rawPer
				row.totalGain = row.gain * row.soldQty
				row.basis = est == 0 and "real" or (real == 0 and "market" or "mixed")
				total, counted = total + row.totalGain, counted + 1
			end
			rows[#rows + 1] = row
		end
	end
	table.sort(rows, function(a, b) return (a.totalGain or -math.huge) > (b.totalGain or -math.huge) end)
	return { rows = rows, total = total, counted = counted }
end

function LG.CSV(opts)
	local rows = { "date,type,item,item_id,quantity,unit_price_gold,gross_gold,ah_cut_gold,net_gold,character" }
	local function g(c) return string.format("%.4f", (c or 0) / 10000) end
	for _, e in ipairs(LG.Entries(opts)) do
		local d = ""
		if date then local ok, v = pcall(date, "%Y-%m-%d %H:%M", e.t); if ok then d = v end end
		local name = tostring(e.name or ""):gsub('"', '""')
		rows[#rows + 1] = ('%s,%s,"%s",%s,%d,%s,%s,%s,%s,%s'):format(d, e.kind, name, e.id or "", e.qty,
			g(e.gross / e.qty), g(e.gross), g(e.fee), g(e.kind == "sale" and (e.gross - e.fee) or -e.gross), e.char or "")
	end
	return table.concat(rows, "\n")
end

function LG.Clear() ns.db.ledger.entries, ns.db.ledger.seen, ns.db.ledger.unsold = {}, {}, {} ; LG.revision = (LG.revision or 0) + 1 end
