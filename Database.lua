-- Goblin Advisor: Database
-- Owns the SavedVariables table (GoblinAdvisorDB): defaults, versioning, small helpers.
local _, ns = ...

local Database = {}
ns.Database = Database

local DB_VERSION = 1

local defaults = {
	settings = {
		debug = false,
		coinIcons = true,                   -- show WoW's coin icons next to gold/silver/copper
		showDemo = false,                   -- sample data is only for previewing the layout (/ga demo on)
		autoScan = true,                    -- request an Auction House scan when you open the AH (read only)
		scanPriceIsUnit = false,            -- false: scan buyout is a stack total, divide by stack size
		lastTab = "dashboard",
		window = { w = 760, h = 520 },      -- x/y are saved once the window has been moved
	},
	market = {
		prices = {},                        -- [itemID] = { price, t, src } latest scanned unit price
		history = {},                       -- [itemID] = { {d = day, p = price}, ... }
		manual = {},                        -- [itemID] = { price, t } set with /ga setprice
		lastScan = nil,
	},
	sessions = {},                          -- finished gold-per-hour sessions, newest last
	activeSession = nil,                    -- the running session, kept across /reload
	recipes = {},                           -- [recipeID] = recipe (see RecipeManager), account-wide
	characters = {},                        -- ["Name-Realm"] = snapshot (see CharacterManager)
	ledger = { entries = {}, seen = {} },   -- real AH sales and purchases read from mail invoices (see Ledger)
}

-- Fill in anything missing without touching values the player already has.
local function Merge(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then dst[k] = Merge({}, v) else dst[k] = v end
		elseif type(v) == "table" and type(dst[k]) == "table" then
			Merge(dst[k], v)
		end
	end
	return dst
end

function Database.Init()
	GoblinAdvisorDB = GoblinAdvisorDB or {}
	local db = GoblinAdvisorDB
	if type(db.version) ~= "number" then db.version = DB_VERSION end
	-- Future schema changes go here, e.g. if db.version < 2 then ... db.version = 2 end
	Merge(db, defaults)
	ns.db = db
end
