-- Goblin Advisor: Demo data
-- Everything in this file is SAMPLE data so the Phase 1 dashboard has something to show.
-- It is NOT market data. The UI must always label it DEMO, and no calculation may treat it as real.
local _, ns = ...

ns.Demo = {
	activities = {
		{ name = "Sample: gather copper ore in a starter zone", perHour = 100000 },
		{ name = "Sample: skin beasts and sell leather", perHour = 70000 },
		{ name = "Sample: craft and sell bandages", perHour = 40000 },
	},
	professions = {
		{ name = "Sample Profession A", rating = "green", note = "high demo profit" },
		{ name = "Sample Profession B", rating = "orange", note = "medium demo profit" },
		{ name = "Sample Profession C", rating = "red", note = "low demo profit" },
	},
	materials = {
		{ name = "Sample Ore", price = 5000, trend = "up", action = "Gather" },
		{ name = "Sample Herb", price = 3000, trend = "flat", action = "Hold" },
		{ name = "Sample Cloth", price = 1000, trend = "down", action = "Sell" },
	},
}
