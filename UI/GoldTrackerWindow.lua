-- Goblin Advisor: Gold Tracker tab
local _, ns = ...
local UI = ns.UI

local function Rate(copper)
	if copper == nil then return ns.Color("grey", "n/a (needs 1+ minute)") end
	return ns.FormatMoney(copper) .. " per hour"
end

local function Signed(copper)
	if copper == nil then return ns.Color("grey", "unknown") end
	return ns.Color(copper > 0 and "green" or (copper < 0 and "red" or "grey"), copper > 0 and "+" or "") .. ns.FormatMoney(copper, true)
end

local function SnapshotText(snap)
	local L = {}
	L[#L + 1] = ("Time: %s"):format(ns.Color("white", ns.GoldTracker.FormatDuration(snap.seconds)))
	L[#L + 1] = ns.Color("gold", "Recorded (real gold)")
	L[#L + 1] = "  Gold change: " .. Signed(snap.goldChange)
	L[#L + 1] = "  Rate: " .. Rate(snap.recordedPerHour)
	L[#L + 1] = ns.Color("gold", "Looted items (market value, theoretical)")
	L[#L + 1] = ("  %d items looted, %d of them materials"):format(snap.items, snap.materials)
	L[#L + 1] = "  Worth about: " .. ns.FormatMoney(snap.marketValue) .. (snap.unpriced > 0 and ns.Color("orange", ("  (%d unpriced items counted as 0)"):format(snap.unpriced)) or "")
	L[#L + 1] = "  Rate: " .. (snap.marketPerHour and (ns.FormatMoney(snap.marketPerHour) .. " per hour") or ns.Color("grey", "n/a"))
	return L
end

UI.RegisterPage("goldtracker", function(parent)
	local startBtn = UI.Button(parent, "Start session", 110, 24, function()
		local ok, err = ns.GoldTracker.Start()
		if not ok then ns.Print(err) end
		UI.RefreshIfShown()
	end)
	local stopBtn = UI.Button(parent, "Stop session", 110, 24, function()
		local ok, res = ns.GoldTracker.Stop()
		if not ok then ns.Print(res) end
		UI.RefreshIfShown()
	end)
	startBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	stopBtn:SetPoint("LEFT", startBtn, "RIGHT", 6, 0)

	-- finished-session history: this character only, or everyone
	local allChars = false
	local resetBtn
	local scopeBtn = UI.Button(parent, "History: this character", 160, 24, function()
		allChars = not allChars
		resetBtn.Disarm()          -- a pending reset must not carry over to the other scope
		UI.RefreshIfShown()
	end)
	scopeBtn:SetPoint("LEFT", stopBtn, "RIGHT", 16, 0)
	resetBtn = UI.ConfirmButton(parent, "Reset history", 110, 24, "Click again to reset", function()
		if allChars then ns.GoldTracker.Clear() else ns.GoldTracker.Clear(ns.CharacterManager.currentKey) end
		ns.Print(allChars and "finished sessions cleared for every character" or "finished sessions cleared for this character")
		UI.RefreshIfShown()
	end)
	resetBtn:SetPoint("LEFT", scopeBtn, "RIGHT", 6, 0)

	local cur = UI.Panel(parent, "Current session")
	cur:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -32)
	cur:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -32)
	cur:SetHeight(170)
	local hist = UI.Panel(parent, "Finished sessions")
	hist:SetPoint("TOPLEFT", cur, "BOTTOMLEFT", 0, -6)
	hist:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

	local acc = 0
	parent:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + (elapsed or 0)
		if acc >= 1 and ns.db and ns.db.activeSession then acc = 0; UI.RefreshIfShown() end
	end)

	local function Refresh()
		local s = ns.db.activeSession
		if s then
			local snap = ns.GoldTracker.Snapshot(s)
			local L = SnapshotText(snap)
			if s.zone then table.insert(L, 1, ns.Color("grey", "Started in " .. s.zone)) end
			cur:SetTitle("Current session " .. ns.Color("green", "[running]"))
			cur:SetBody(table.concat(L, "\n"))
		else
			cur:SetTitle("Current session")
			cur:SetBody(ns.Color("grey", "No session running.\n\nPress Start before you begin farming and Stop when you are done.\nGold change is your real gold; looted item value is a price-based estimate\nand is kept separate on purpose. Vendoring and repairs are already inside\nthe gold change; they are not tracked separately."))
		end
		startBtn:SetActive(s ~= nil)

		scopeBtn.text:SetText(allChars and "History: all characters" or "History: this character")
		local L = {}
		local list = ns.GoldTracker.List(not allChars and ns.CharacterManager.currentKey or nil)
		local cur = ns.CharacterManager.GetCurrent()
		hist:SetTitle(allChars and "Finished sessions (all characters)" or ("Finished sessions" .. (cur and (" - " .. (cur.name or "this character")) or "")))
		for i = #list, math.max(1, #list - 7), -1 do
			local snap = ns.GoldTracker.Snapshot(list[i])
			local who = allChars and list[i].character and ns.Color("grey", (list[i].character:match("^[^%-]+") or "") .. "  ") or ""
			L[#L + 1] = who .. ("%s  %s   gold %s  (%s)   loot ~%s  (%s)"):format(
				ns.Color("white", ns.GoldTracker.FormatDuration(snap.seconds)),
				ns.Color("grey", list[i].zone or ""),
				Signed(snap.goldChange),
				snap.recordedPerHour and (ns.FormatMoney(snap.recordedPerHour) .. "/h") or "n/a",
				ns.FormatMoney(list[i].marketValue or snap.marketValue),
				snap.marketPerHour and (ns.FormatMoney(snap.marketPerHour) .. "/h") or "n/a")
		end
		if #L == 0 then L[1] = ns.Color("grey", "None yet.") end
		hist:SetBody(table.concat(L, "\n"))
	end

	return { frame = parent, Refresh = Refresh }
end)
