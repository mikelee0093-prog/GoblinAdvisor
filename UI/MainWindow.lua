-- Goblin Advisor: Main window
-- The shell (title bar, tabs, saved position/size) plus small skinning helpers shared by
-- every page. Colours are drawn with plain textures so no frame templates are needed.
local _, ns = ...

local UI = { pages = {}, tabButtons = {}, builders = {}, current = nil }
ns.UI = UI

local TABS = {
	{ id = "dashboard", label = "Dashboard" },
	{ id = "professions", label = "Professions", phase = 2,
	  planned = "Read your professions, skills and recipes; compare professions side by side." },
	{ id = "market", label = "Market", phase = 3,
	  planned = "Price providers, material values, price history and Sell / Hold / Gather / Craft hints." },
	{ id = "gathering", label = "Gathering", phase = 4,
	  planned = "Gathering priorities by level, skill and zone, based on real prices." },
	{ id = "goldtracker", label = "Gold Tracker", phase = 4,
	  planned = "Start/stop farming sessions with recorded gold, loot and gold per hour." },
	{ id = "ledger", label = "Ledger", phase = 6,
	  planned = "Real Auction House sales and purchases read from your mailbox invoices." },
	{ id = "lists", label = "Lists", phase = 6,
	  planned = "Shopping list for crafts and a watch list with price alerts." },
	{ id = "characters", label = "Characters", phase = 5,
	  planned = "All your characters, material allocation, and import/export between accounts." },
	{ id = "settings", label = "Settings" },
}

local BG = { 0.07, 0.07, 0.09, 0.96 }
local PANEL = { 0.10, 0.10, 0.13, 0.95 }
local EDGE = { 0.30, 0.26, 0.12, 1 }

---------------------------------------------------------------- skinning helpers
-- Solid background plus a 1px border. Returns the background texture so callers can recolour it.
function UI.Skin(frame, bg, border)
	bg = bg or BG
	border = border or EDGE
	local tex = frame:CreateTexture(nil, "BACKGROUND")
	tex:SetAllPoints(frame)
	tex:SetColorTexture(bg[1], bg[2], bg[3], bg[4])

	local function edge()
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(border[1], border[2], border[3], border[4])
		return t
	end
	local top, bottom, left, right = edge(), edge(), edge(), edge()
	top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
	bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
	left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
	right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
	return tex
end

-- A titled box with a multi-line text body. Use panel:SetBody("...").
function UI.Panel(parent, title)
	local p = CreateFrame("Frame", nil, parent)
	UI.Skin(p, PANEL)
	p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	p.title:SetPoint("TOPLEFT", 10, -8)
	p.title:SetText(title)
	p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.body:SetPoint("TOPLEFT", 10, -28)
	p.body:SetPoint("BOTTOMRIGHT", -10, 8)
	p.body:SetJustifyH("LEFT")
	p.body:SetJustifyV("TOP")
	p.body:SetSpacing(2)
	function p:SetBody(text) self.body:SetText(text or "") end
	function p:SetTitle(text) self.title:SetText(text or "") end
	return p
end

function UI.Button(parent, label, w, h, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	local bg = UI.Skin(b, { 0.14, 0.14, 0.18, 1 })
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetPoint("CENTER")
	b.text:SetText(label)
	b.active = false
	local function paint(hover)
		if b.active then bg:SetColorTexture(0.25, 0.21, 0.08, 1)
		elseif hover then bg:SetColorTexture(0.20, 0.20, 0.26, 1)
		else bg:SetColorTexture(0.14, 0.14, 0.18, 1) end
	end
	function b:SetActive(on) self.active = on and true or false; paint(false) end
	b:SetScript("OnEnter", function() paint(true) end)
	b:SetScript("OnLeave", function() paint(false) end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- A labelled check box: get() returns the current state, set(value) stores it.
function UI.Checkbox(parent, label, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(300, 20)
	local box = CreateFrame("Frame", nil, b)
	box:SetSize(16, 16)
	box:SetPoint("LEFT")
	UI.Skin(box, { 0.12, 0.12, 0.16, 1 })
	local mark = box:CreateTexture(nil, "OVERLAY")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	mark:SetColorTexture(1, 0.82, 0, 1)
	local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", box, "RIGHT", 8, 0)
	text:SetText(label)
	function b:Refresh() if get() then mark:Show() else mark:Hide() end end
	b:SetScript("OnClick", function() set(not get()); b:Refresh() end)
	b:Refresh()
	return b
end

---------------------------------------------------------------- pages
UI.tabHome = {}
function UI.RegisterPage(id, builder) UI.builders[id] = builder end

local function BuildPlaceholder(tab, parent)
	local panel = UI.Panel(parent, tab.label)
	panel:SetAllPoints(parent)
	panel:SetBody(
		ns.Color("orange", "Not built yet: planned for Phase " .. tostring(tab.phase) .. ".") .. "\n\n" ..
		tostring(tab.planned) .. "\n\n" ..
		ns.Color("grey", "Nothing on this tab is real or fake data. It is simply not implemented in this version."))
	return { frame = panel, Refresh = function() end }
end

---------------------------------------------------------------- window
local win

local function SaveWindowState()
	if not win or not ns.db then return end
	local w = ns.db.settings.window
	w.w, w.h = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5)
	local point, _, relPoint, x, y = win:GetPoint(1)
	if point then w.point, w.relPoint, w.x, w.y = point, relPoint, x, y end
end

local function ApplyWindowState()
	local w = ns.db.settings.window
	win:SetSize(w.w or 760, w.h or 520)
	win:ClearAllPoints()
	if w.point and w.x and w.y then
		win:SetPoint(w.point, UIParent, w.relPoint or w.point, w.x, w.y)
	else
		win:SetPoint("CENTER")
	end
end

local function LayoutTabs()
	local n = #TABS
	local tw = math.floor((win:GetWidth() - 16 - (n - 1) * 2) / n)
	for i, tab in ipairs(TABS) do
		local b = UI.tabButtons[tab.id]
		b:SetWidth(tw)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", win, "TOPLEFT", 8 + (i - 1) * (tw + 2), -32)
	end
end

function UI.UpdateHeader()
	if not win then return end
	local demo = ns.db.settings.showDemo and ns.Color("orange", "  DEMO DATA ON") or ""
	win.title:SetText("Goblin Advisor  " .. ns.Color("grey", "v" .. ns.version) .. demo)
end

function UI.OpenTab(id)
	if not UI.pages[id] then return false end
	if not win then return false end
	for tabId, page in pairs(UI.pages) do
		if tabId == id then page.frame:Show() else page.frame:Hide() end
	end
	for tabId, b in pairs(UI.tabButtons) do b:SetActive(tabId == id) end
	UI.current = id
	ns.db.settings.lastTab = id
	if not win:IsShown() then win:Show() end
	ns.Try("page refresh", UI.pages[id].Refresh)
	return true
end

function UI.RefreshIfShown()
	if win and win:IsShown() and UI.current and UI.pages[UI.current] then
		UI.UpdateHeader()
		ns.Try("page refresh", UI.pages[UI.current].Refresh)
	end
end

function UI.Toggle()
	if not win then ns.Print("the window is not ready yet (log in first)."); return end
	if win:IsShown() then win:Hide() else UI.OpenTab(UI.current or ns.db.settings.lastTab or "dashboard") end
end

function UI.ResetWindow()
	local w = ns.db.settings.window
	w.w, w.h, w.point, w.relPoint, w.x, w.y = 760, 520, nil, nil, nil, nil
	if win then ApplyWindowState(); LayoutTabs() end
end

function UI.Build()
	if win then return end
	win = CreateFrame("Frame", "GoblinAdvisorFrame", UIParent)
	UI.frame = win
	win:SetFrameStrata("HIGH")
	win:SetMovable(true)
	win:EnableMouse(true)
	win:SetClampedToScreen(true)
	ApplyWindowState()
	UI.Skin(win, BG)
	win:Hide()

	-- Resizable where the client supports it.
	win:SetResizable(true)
	if win.SetResizeBounds then win:SetResizeBounds(680, 440, 1300, 900)
	elseif win.SetMinResize then win:SetMinResize(680, 440) end

	-- Title bar doubles as the drag handle.
	local bar = CreateFrame("Frame", nil, win)
	bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT", -30, 0); bar:SetHeight(28)   -- stops short of the close button
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() win:StartMoving() end)
	bar:SetScript("OnDragStop", function() win:StopMovingOrSizing(); SaveWindowState() end)
	win.title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	win.title:SetPoint("LEFT", 10, 0)

	local close = UI.Button(win, "X", 22, 20, function() win:Hide() end)
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetFrameLevel(win:GetFrameLevel() + 20)   -- always above the title bar so it gets the click
	if close.RegisterForClicks then close:RegisterForClicks("LeftButtonUp") end

	-- Corner grip for resizing.
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	local gt = grip:CreateTexture(nil, "OVERLAY")
	gt:SetAllPoints(grip)
	gt:SetColorTexture(0.45, 0.38, 0.15, 0.9)
	grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing(); SaveWindowState() end)

	-- Tabs and pages.
	local content = CreateFrame("Frame", nil, win)
	content:SetPoint("TOPLEFT", 8, -60)
	content:SetPoint("BOTTOMRIGHT", -8, 24)
	UI.content = content

	for _, tab in ipairs(TABS) do
		local b = UI.Button(win, tab.label, 90, 22, function()
			if UI.tabHome and UI.tabHome[tab.id] then UI.tabHome[tab.id]() end   -- clicking a tab opens its home view
			UI.OpenTab(tab.id)
		end)
		UI.tabButtons[tab.id] = b

		local host = CreateFrame("Frame", nil, content)
		host:SetAllPoints(content)
		host:Hide()
		local builder = UI.builders[tab.id]
		local page
		if builder then
			local ok, result = pcall(builder, host)
			if ok then page = result else ns.Error("build " .. tab.id, result) end
		end
		if not page then page = BuildPlaceholder(tab, host) end
		UI.pages[tab.id] = { frame = host, Refresh = page.Refresh or function() end }
	end

	local footer = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 10, 8)
	footer:SetText("Phase 5: characters, materials, import/export. /ga help for commands.")

	win:SetScript("OnSizeChanged", function() LayoutTabs() end)
	win:SetScript("OnShow", function() UI.RefreshIfShown() end)
	LayoutTabs()
	UI.UpdateHeader()

	if UISpecialFrames then table.insert(UISpecialFrames, "GoblinAdvisorFrame") end
	UI.current = ns.db.settings.lastTab
	if not UI.pages[UI.current] then UI.current = "dashboard" end
end
