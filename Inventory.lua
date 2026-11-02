-- Goblin Advisor: bank snapshots
-- The game only lets an addon read bank contents while the bank is open, so each visit records
-- what is in this character's bank tabs (and the shared Warband bank) in the saved variables.
-- "Owned" counts then add the last recorded bank contents to what is in your bags right now.
-- Reading containers is read-only: nothing is moved, bought or sold.
-- UNVERIFIED in game: container ids come from Enum.BagIndex (character tabs 6-14, Warband
-- tabs 15-23); /ga bank shows what was actually recorded.
local _, ns = ...

local INV = {}
ns.Inventory = INV
INV.bankOpen = false

local function Ids(prefix, firstId)
	local ids = {}
	local e = Enum and Enum.BagIndex
	for i = 1, 9 do
		local v = e and e[prefix .. i]
		ids[#ids + 1] = type(v) == "number" and v or (firstId + i - 1)
	end
	return ids
end

local function Scan(containers)
	local items, slots = {}, 0
	local C = C_Container
	for _, bag in ipairs(containers) do
		local okN, n = pcall(C.GetContainerNumSlots, bag)
		n = okN and ns.Safe(n) or 0
		if type(n) == "number" and n > 0 then
			slots = slots + n
			for slot = 1, n do
				local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
				if ok and type(info) == "table" then
					local id, count = ns.Safe(info.itemID), ns.Safe(info.stackCount)
					if type(id) == "number" then items[id] = (items[id] or 0) + (tonumber(count) or 1) end
				end
			end
		end
	end
	return items, slots
end

-- Record the bank as it is right now. Keeps the previous record when nothing was readable.
function INV.Snapshot()
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return false end
	local cur = ns.CharacterManager.GetCurrent()
	if not cur then return false end
	local now = ns.MarketData.Now()
	local mine, mySlots = Scan(Ids("CharacterBankTab_", 6))
	local shared, sharedSlots = Scan(Ids("AccountBankTab_", 15))
	if mySlots > 0 then cur.bank = { items = mine, t = now } end
	if sharedSlots > 0 then ns.db.accountBank = { items = shared, t = now } end
	INV.revision = (INV.revision or 0) + 1
	ns.Debug("bank snapshot: character slots " .. mySlots .. ", warband slots " .. sharedSlots)
	return mySlots > 0 or sharedSlots > 0
end

-- { bags, bank, warband } for one item; nil parts when never recorded.
function INV.Breakdown(itemID)
	local bags
	if C_Item and C_Item.GetItemCount then
		local ok, n = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
		n = ok and ns.Safe(n)
		bags = type(n) == "number" and n or nil
	end
	local cur = ns.CharacterManager.GetCurrent()
	local bank = cur and cur.bank and cur.bank.items[itemID] or 0
	local warband = ns.db.accountBank and ns.db.accountBank.items[itemID] or 0
	return { bags = bags, bank = bank, warband = warband }
end

-- Bag contents of this character for every tracked material, so other characters (and the
-- allocation view) know where materials are. Updated a few seconds after bags change.
function INV.SnapshotBags()
	local cur = ns.CharacterManager.GetCurrent()
	if not cur or not (C_Item and C_Item.GetItemCount) then return false end
	local items = {}
	for _, id in ipairs(ns.Recommendations.MaterialIDs()) do
		local ok, n = pcall(C_Item.GetItemCount, id, false, false, false, false)
		n = ok and ns.Safe(n)
		if type(n) == "number" and n > 0 then items[id] = n end
	end
	cur.bags = { items = items, t = ns.MarketData.Now() }
	INV.revision = (INV.revision or 0) + 1
	return true
end

-- Who holds an item: { holders = { {label, count, t}, ... }, total }. Characters other than
-- the one you are on show what they held when last logged out. The Warband bank counts once.
function INV.Holdings(itemID)
	local holders, total = {}, 0
	for _, e in ipairs(ns.CharacterManager.List()) do
		local rec = e.rec
		local bags = rec.bags and rec.bags.items[itemID] or 0
		local bank = rec.bank and rec.bank.items[itemID] or 0
		if bags + bank > 0 then
			holders[#holders + 1] = { key = e.key, label = rec.name or e.key, count = bags + bank, bags = bags, bank = bank,
				t = (e.key == ns.CharacterManager.currentKey) and ns.MarketData.Now() or math.max((rec.bags and rec.bags.t) or 0, (rec.bank and rec.bank.t) or 0) }
			total = total + bags + bank
		end
	end
	local wb = ns.db.accountBank and ns.db.accountBank.items[itemID] or 0
	if wb > 0 then
		holders[#holders + 1] = { key = "warband", label = "Warband bank", count = wb, bags = 0, bank = wb, t = ns.db.accountBank.t }
		total = total + wb
	end
	table.sort(holders, function(a, b) return a.count > b.count end)
	return { holders = holders, total = total }
end

local bagPending = false
local function QueueBags(delay)
	if bagPending then return end
	bagPending = true
	C_Timer.After(delay or 3, function() bagPending = false; INV.SnapshotBags() end)
end
ns.On("PLAYER_LOGIN", function() QueueBags(6) end)
ns.On("PLAYER_LOGOUT", function() INV.SnapshotBags() end)

local pending = false
local function Queue()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function() pending = false; INV.Snapshot(); ns.UI.RefreshIfShown() end)
end

ns.On("BANKFRAME_OPENED", function() INV.bankOpen = true; Queue() end)
ns.On("BANKFRAME_CLOSED", function() INV.bankOpen = false end)
ns.On("BAG_UPDATE_DELAYED", function() QueueBags(3); if INV.bankOpen then Queue() end end)

function INV.PrintStatus()
	local cur = ns.CharacterManager.GetCurrent()
	local function line(label, rec)
		if not rec then print("  " .. label .. ": never recorded (open the bank once)"); return end
		local kinds, total = 0, 0
		for _, n in pairs(rec.items) do kinds = kinds + 1; total = total + n end
		print(("  %s: %d kinds, %d items, recorded %s"):format(label, kinds, total, ns.MarketData.FormatAge(rec.t)))
	end
	line("character bank", cur and cur.bank)
	line("warband bank", ns.db.accountBank)
end
