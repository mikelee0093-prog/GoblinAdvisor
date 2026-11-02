-- Goblin Advisor: export / import
-- Moves your manual prices and your character summaries (name, class, level, gold, professions)
-- between accounts as one line of text you copy and paste. Nothing is sent over the internet.
-- Imported text is parsed by a small reader (it is never run as code), every value is checked,
-- and the import is previewed before anything is changed.
local _, ns = ...

local T = {}
ns.Transfer = T

local VERSION = 1
local MAX_NODES = 60000
local MAX_DEPTH = 6

---------------------------------------------------------------- serialise (plain text, no code)
local function Write(v, out, depth)
	local tv = type(v)
	if tv == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif tv == "number" then
		out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
	elseif tv == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif tv == "table" then
		if depth > MAX_DEPTH then error("too deep") end
		out[#out + 1] = "{"
		for k, val in pairs(v) do
			if type(k) == "string" or type(k) == "number" then
				Write(k, out, depth + 1)
				Write(val, out, depth + 1)
			end
		end
		out[#out + 1] = "}"
	end
end

-- Reader: returns value, nextPosition (or nil, error text).
local nodes
local function Read(str, pos, depth)
	nodes = nodes + 1
	if nodes > MAX_NODES then return nil, "too much data" end
	if depth > MAX_DEPTH then return nil, "nested too deep" end
	local c = str:sub(pos, pos)
	if c == "s" then
		local len, colon = str:match("^s(%d+):()", pos)
		len = tonumber(len)
		if not len or len > 200 then return nil, "bad text length" end
		local e = colon + len
		if e - 1 > #str then return nil, "truncated text" end
		return str:sub(colon, e - 1), e
	elseif c == "n" then
		local num, e = str:match("^n([%-%+%.%deE]+);()", pos)
		num = tonumber(num)
		if not num or num ~= num or num == math.huge or num == -math.huge then return nil, "bad number" end
		return num, e
	elseif c == "T" then return true, pos + 1
	elseif c == "F" then return false, pos + 1
	elseif c == "{" then
		local t = {}
		pos = pos + 1
		while true do
			if pos > #str then return nil, "unterminated table" end
			if str:sub(pos, pos) == "}" then return t, pos + 1 end
			local k, p2 = Read(str, pos, depth + 1)
			if k == nil then return nil, p2 end
			if type(k) ~= "string" and type(k) ~= "number" then return nil, "bad key" end
			local v, p3 = Read(str, p2, depth + 1)
			if v == nil then return nil, p3 end
			t[k] = v
			pos = p3
		end
	end
	return nil, "unexpected character"
end

---------------------------------------------------------------- base64 and checksum
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Encode(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end
local DEC = {}
for i = 1, #B64 do DEC[B64:byte(i)] = i - 1 end
local function Decode(text)
	if #text % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #text, 4 do
		local a, b, c, d = text:byte(i, i + 3)
		local va, vb = DEC[a], DEC[b]
		local vc, vd = DEC[c], DEC[d]
		if not va or not vb then return nil end
		if c == 61 then
			if d ~= 61 then return nil end
			local n = va * 4096 + vb * 64
			out[#out + 1] = string.char(math.floor(n / 1024) % 256)
		elseif d == 61 then
			if not vc then return nil end
			local n = va * 4096 + vb * 64 + vc
			out[#out + 1] = string.char(math.floor(n / 1024) % 256, math.floor(n / 4) % 256)
		else
			if not vc or not vd then return nil end
			local n = va * 262144 + vb * 4096 + vc * 64 + vd
			out[#out + 1] = string.char(math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
		end
	end
	return table.concat(out)
end
local function Checksum(data)
	local s1, s2 = 1, 0
	for i = 1, #data do
		s1 = (s1 + data:byte(i)) % 65521
		s2 = (s2 + s1) % 65521
	end
	return string.format("%04x%04x", s2, s1)
end

---------------------------------------------------------------- export
function T.Build()
	local payload = { v = VERSION, version = ns.version, exported = ns.MarketData.Now(), manual = {}, characters = {} }
	local nManual, nChars = 0, 0
	for id, m in pairs(ns.db.market.manual) do
		payload.manual[id] = { price = m.price, t = m.t }
		nManual = nManual + 1
	end
	for key, rec in pairs(ns.db.characters) do
		local profs = {}
		for _, p in ipairs(rec.professions or {}) do profs[#profs + 1] = { name = p.name, skill = p.skill or 0, maxSkill = p.maxSkill or 0 } end
		payload.characters[key] = {
			name = rec.name, realm = rec.realm, class = rec.class, classToken = rec.classToken,
			level = rec.level, gold = rec.gold, professions = profs,
			lastSeen = key == ns.CharacterManager.currentKey and ns.MarketData.Now() or rec.lastSeen,
		}
		nChars = nChars + 1
	end
	return T.Pack(payload), { manual = nManual, characters = nChars }
end

-- Turn a table into the export text (also used by the tests to build unusual payloads).
function T.Pack(payload)
	local out = {}
	Write(payload, out, 0)
	local raw = table.concat(out)
	return "GA1:" .. Checksum(raw) .. ":" .. Encode(raw)
end

---------------------------------------------------------------- import
local function Int(v, lo, hi)
	if type(v) ~= "number" or v ~= math.floor(v) or v < lo or v > hi then return nil end
	return v
end
local function Str(v, max)
	if type(v) ~= "string" or v == "" or #v > max then return nil end
	return v
end

-- Parse and validate. Returns a preview table (never changes any data).
function T.Preview(text)
	text = tostring(text or ""):gsub("%s+", "")
	local sum, b64 = text:match("^GA1:(%x%x%x%x%x%x%x%x):([A-Za-z0-9%+/=]*)$")
	if not sum then return { ok = false, err = "This is not a Goblin Advisor export (it should start with GA1:)." } end
	local raw = Decode(b64)
	if not raw then return { ok = false, err = "The text is damaged: copy the whole line again." } end
	if Checksum(raw) ~= sum:lower() then return { ok = false, err = "The text is incomplete or was changed: copy the whole line again." } end
	nodes = 0
	local payload, err = Read(raw, 1, 0)
	if type(payload) ~= "table" then return { ok = false, err = "Could not read the data (" .. tostring(err) .. ")." } end
	if payload.v ~= VERSION then return { ok = false, err = "This export is from a different version of the addon format." } end

	local pv = { ok = true, manual = {}, characters = {}, newManual = 0, updatedManual = 0, skippedManual = 0,
		newChars = 0, updatedChars = 0, skippedChars = 0, rejected = 0 }
	for id, m in pairs(type(payload.manual) == "table" and payload.manual or {}) do
		local iid, price, t = Int(id, 1, 10000000), type(m) == "table" and Int(m.price, 1, 1e10), type(m) == "table" and Int(m.t, 0, 4e9)
		if iid and price and t then
			local cur = ns.db.market.manual[iid]
			if not cur then pv.newManual = pv.newManual + 1; pv.manual[iid] = { price = price, t = t }
			elseif (cur.t or 0) < t then pv.updatedManual = pv.updatedManual + 1; pv.manual[iid] = { price = price, t = t }
			else pv.skippedManual = pv.skippedManual + 1 end
		else
			pv.rejected = pv.rejected + 1
		end
	end
	for key, c in pairs(type(payload.characters) == "table" and payload.characters or {}) do
		local k = Str(key, 80)
		if k and k:find("^[^%-]+%-.+$") and type(c) == "table" then
			local clean = {
				name = Str(c.name, 40), realm = Str(c.realm, 60), class = Str(c.class, 40), classToken = Str(c.classToken, 30),
				level = Int(c.level, 1, 200), gold = Int(c.gold, 0, 1e13), lastSeen = Int(c.lastSeen, 0, 4e9), professions = {},
			}
			for _, p in ipairs(type(c.professions) == "table" and c.professions or {}) do
				local pname = type(p) == "table" and Str(p.name, 30)
				if pname and #clean.professions < 6 then
					clean.professions[#clean.professions + 1] = { name = pname, skill = Int(p.skill, 0, 1000) or 0, maxSkill = Int(p.maxSkill, 0, 1000) or 0 }
				end
			end
			if clean.name and clean.realm then
				local cur = ns.db.characters[k]
				if k == ns.CharacterManager.currentKey then pv.skippedChars = pv.skippedChars + 1
				elseif not cur then pv.newChars = pv.newChars + 1; pv.characters[k] = clean
				elseif (clean.lastSeen or 0) > (cur.lastSeen or 0) then pv.updatedChars = pv.updatedChars + 1; pv.characters[k] = clean
				else pv.skippedChars = pv.skippedChars + 1 end
			else
				pv.rejected = pv.rejected + 1
			end
		else
			pv.rejected = pv.rejected + 1
		end
	end
	return pv
end

-- Apply a preview from T.Preview. Newer data wins; the character you are on is never changed.
function T.Apply(pv)
	if not pv or not pv.ok then return false, "nothing to import" end
	for id, m in pairs(pv.manual) do ns.db.market.manual[id] = { price = m.price, t = m.t } end
	ns.MarketData.revision = ns.MarketData.revision + 1
	for key, c in pairs(pv.characters) do
		local rec = ns.db.characters[key] or {}
		rec.name, rec.realm, rec.class, rec.classToken = c.name, c.realm, c.class or rec.class, c.classToken or rec.classToken
		rec.level, rec.gold, rec.lastSeen = c.level or rec.level, c.gold or rec.gold, c.lastSeen or rec.lastSeen
		rec.professions = c.professions
		ns.db.characters[key] = rec
	end
	return true
end

function T.Summary(pv)
	if not pv or not pv.ok then return pv and pv.err or "" end
	return ("%d new and %d newer manual prices, %d new and %d updated characters; %d unchanged%s."):format(
		pv.newManual, pv.updatedManual, pv.newChars, pv.updatedChars,
		pv.skippedManual + pv.skippedChars, pv.rejected > 0 and (", " .. pv.rejected .. " invalid entries ignored") or "")
end
