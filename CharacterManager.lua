-- Goblin Advisor: CharacterManager
-- Records a snapshot of the character you are logged in with (name, class, level, gold,
-- professions). Only characters you have actually logged in with ever appear here.
local _, ns = ...

local CM = {}
ns.CharacterManager = CM

CM.sessionStartGold = nil     -- gold when this login began (real, for "this session")
CM.professionsReadable = nil  -- true/false once we have tried; nil = not tried yet

local function Key()
	local name = ns.Safe(UnitName("player"))
	local realm = GetRealmName and ns.Safe(GetRealmName())
	if not name or not realm then return nil end
	return name .. "-" .. realm, name, realm
end

-- Professions via GetProfessions/GetProfessionInfo. This API is present in the client's
-- global list but its signature is NOT documented in docs/api, so it is wrapped defensively.
-- UNVERIFIED until checked in game: run /ga status.
local function ReadProfessions()
	local list = {}
	if not (GetProfessions and GetProfessionInfo) then return list, false end
	local ok, a, b, c, d, e = pcall(GetProfessions)
	if not ok then ns.Debug("GetProfessions failed:", a); return list, false end
	local indexes = { a, b, c, d, e }
	for i = 1, 5 do
		local idx = indexes[i]
		if idx then
			local ok2, pname, icon, skill, maxSkill = pcall(GetProfessionInfo, idx)
			if ok2 and pname then
				list[#list + 1] = {
					name = pname, icon = icon,
					skill = tonumber(ns.Safe(skill)) or 0,
					maxSkill = tonumber(ns.Safe(maxSkill)) or 0,
				}
			end
		end
	end
	return list, true
end

function CM.Capture(reason)
	local key, name, realm = Key()
	if not key or not ns.db then return end

	local _, classToken = UnitClass("player")
	local className = UnitClass("player")
	local gold = ns.Safe(GetMoney())
	local rec = ns.db.characters[key] or {}

	rec.name, rec.realm = name, realm
	rec.class, rec.classToken = className, classToken
	rec.level = ns.Safe(UnitLevel("player")) or rec.level
	if type(gold) == "number" then
		rec.gold = gold
		if not CM.sessionStartGold then CM.sessionStartGold = gold end
	end

	local profs, readable = ReadProfessions()
	CM.professionsReadable = readable
	-- Keep the last good list if this read came back empty (e.g. skills not loaded yet).
	if #profs > 0 or readable then rec.professions = profs end

	rec.lastSeen = GetServerTime and GetServerTime() or time()
	ns.db.characters[key] = rec
	CM.currentKey = key
	ns.Debug("captured", key, "reason=" .. tostring(reason), "gold=" .. tostring(rec.gold))
end

function CM.GetCurrent()
	return CM.currentKey and ns.db.characters[CM.currentKey] or nil
end

-- Real session change in copper, or nil if unknown.
function CM.SessionDelta()
	local cur = CM.GetCurrent()
	if cur and cur.gold and CM.sessionStartGold then return cur.gold - CM.sessionStartGold end
end

function CM.Count()
	local n = 0
	for _ in pairs(ns.db.characters) do n = n + 1 end
	return n
end

-- Gold across tracked characters only (not the whole account, only ones seen by this addon).
function CM.TotalGold()
	local total = 0
	for _, rec in pairs(ns.db.characters) do total = total + (rec.gold or 0) end
	return total
end

-- Tracked characters, richest first: { { key, rec }, ... }
function CM.List()
	local list = {}
	for key, rec in pairs(ns.db.characters) do list[#list + 1] = { key = key, rec = rec } end
	table.sort(list, function(a, b)
		local ga, gb = a.rec.gold or 0, b.rec.gold or 0
		if ga ~= gb then return ga > gb end
		return a.key < b.key
	end)
	return list
end

-- total gold, number of characters, and the oldest "last seen" time (nil if none recorded).
-- Other characters' gold is whatever it was when you last logged them out.
function CM.GoldSummary()
	local total, n, oldest = 0, 0, nil
	for key, rec in pairs(ns.db.characters) do
		n = n + 1
		total = total + (rec.gold or 0)
		local seen = key == CM.currentKey and ns.MarketData.Now() or rec.lastSeen
		if seen and (not oldest or seen < oldest) then oldest = seen end
	end
	return total, n, oldest
end

-- "Mining 150/300 - Herbalism 90/300", or nil when none are recorded.
function CM.ProfessionLine(rec)
	local parts = {}
	for _, p in ipairs(rec and rec.professions or {}) do
		parts[#parts + 1] = ("%s %d/%d"):format(p.name, p.skill or 0, p.maxSkill or 0)
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "  -  ")
end

-- profession name -> list of character names that have it
function CM.ProfessionOwners()
	local map = {}
	for _, e in ipairs(CM.List()) do
		for _, p in ipairs(e.rec.professions or {}) do
			map[p.name] = map[p.name] or {}
			table.insert(map[p.name], e.rec.name or e.key)
		end
	end
	return map
end

-- Remove one character and everything stored for it. The character you are logged in with
-- cannot be removed: the addon would just record it again.
function CM.Delete(key)
	if key == CM.currentKey then return false, "you are logged in as this character" end
	if not ns.db.characters[key] then return false, "no such character" end
	ns.db.characters[key] = nil
	local kept = {}
	for _, s in ipairs(ns.db.sessions) do
		if s.character ~= key then kept[#kept + 1] = s end
	end
	ns.db.sessions = kept
	return true
end

function CM.PrintStatus()
	ns.Print("character data:")
	print("  GetMoney: " .. (type(ns.Safe(GetMoney())) == "number" and "ok" or "unreadable"))
	if CM.professionsReadable == nil then
		print("  professions: not read yet")
	elseif CM.professionsReadable then
		local cur = CM.GetCurrent()
		print("  professions: readable (" .. (cur and cur.professions and #cur.professions or 0) .. " found)")
	else
		print("  professions: GetProfessions unavailable or failed (see /ga log)")
	end
	print("  characters tracked: " .. CM.Count())
end
