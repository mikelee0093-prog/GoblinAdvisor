-- Goblin Advisor: Watch list
-- Items you want to keep an eye on, each with a target price. After every Auction House scan the
-- addon prints a chat message when a watched item crosses its target. Prices come only from your
-- own scans (or prices you typed); an item with no price just says "no data". Nothing is automated.
local _, ns = ...

local W = {}
ns.Watch = W

local function Items() ns.db.watch = ns.db.watch or { items = {} }; ns.db.watch.items = ns.db.watch.items or {}; return ns.db.watch.items end

-- "12", "12.5" -> copper. Gold only; nil if it is not a positive number.
function W.ParseGold(text)
	local n = tonumber((tostring(text or ""):gsub("[gG]%s*$", "")))
	if not n or n <= 0 then return nil end
	return math.floor(n * 10000 + 0.5)
end

-- An item id, an item link, or the exact name of an item the addon already knows about.
function W.Resolve(text)
	text = tostring(text or "")
	local id = tonumber(text:match("|Hitem:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
	if id then return id end
	local name = text:match("^%s*(.-)%s*$")
	if name ~= "" and ns.Ledger and ns.Ledger.ItemID then return ns.Ledger.ItemID(name) end
	return nil
end

function W.Get(id) return Items()[id] end
function W.Count() local n = 0; for _ in pairs(Items()) do n = n + 1 end; return n end

-- dir = "below" (alert when the price falls to the target or lower: a buying chance)
--       "above" (alert when it rises to the target or higher: a selling chance)
function W.Add(id, target, dir)
	if type(id) ~= "number" or type(target) ~= "number" or target <= 0 then return false end
	dir = dir == "above" and "above" or "below"
	local old = Items()[id]
	Items()[id] = { target = math.floor(target), dir = dir, added = (old and old.added) or ns.MarketData.Now(), alerted = false }
	ns.UI.RefreshIfShown()
	return true
end

function W.Remove(id)
	if not Items()[id] then return false end
	Items()[id] = nil
	ns.UI.RefreshIfShown()
	return true
end

-- A starting target for the Market "Watch" button: 10% under today's price (the player can edit it).
function W.DefaultTarget(id)
	local st = ns.MarketData.GetStats(id)
	if not st then return nil end
	return math.max(1, math.floor(st.price * 0.9))
end

local function Hit(w, price)
	if w.dir == "above" then return price >= w.target end
	return price <= w.target
end

-- One row per watched item for the UI. status: "hit", "waiting" or "nodata".
function W.List()
	local out = {}
	for id, w in pairs(Items()) do
		local st = ns.MarketData.GetStats(id)
		local status = "nodata"
		if st then status = Hit(w, st.price) and "hit" or "waiting" end
		out[#out + 1] = { id = id, name = ns.RecipeManager.ItemName(id), target = w.target, dir = w.dir, price = st and st.price,
			stale = st and st.stale, thin = st and st.thin, avg = st and st.avg, status = status }
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- Called after each scan. Prints one line per item that has newly crossed its target; an item is
-- announced again only after it has left its target and come back. Stale prices never alert.
function W.Check()
	local hits = {}
	for id, w in pairs(Items()) do
		local st = ns.MarketData.GetStats(id)
		if st and not st.stale then
			if Hit(w, st.price) then
				if not w.alerted then
					w.alerted = true
					hits[#hits + 1] = id
					ns.Print(("watch: %s is %s, %s your target of %s."):format(ns.RecipeManager.ItemName(id), ns.FormatMoney(st.price),
						w.dir == "above" and "at or above" or "at or below", ns.FormatMoney(w.target)))
				end
			else
				w.alerted = false
			end
		end
	end
	if #hits > 0 then ns.UI.RefreshIfShown() end
	return hits
end
