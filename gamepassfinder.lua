--[[=================================================================
    PASS & PRODUCT BROWSER
    Lists EVERY game pass and developer product in the current
    universe - including ones the game's own shop UI hides.
    Click any entry to open the Roblox purchase prompt.
    Shift+click runs a prompt diagnostic. Ctrl+click copies the
    web link. Right-click copies the ID.
===================================================================]]

local genv = (getgenv and getgenv()) or _G
if genv.PPBrowserUnhook then pcall(genv.PPBrowserUnhook) end
if genv.PPBrowserGui and genv.PPBrowserGui.Parent then
	pcall(function() genv.PPBrowserGui:Destroy() end)
end

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService        = game:GetService("HttpService")
local UserInputService   = game:GetService("UserInputService")
local RunService         = game:GetService("RunService")

local UIS = UserInputService
local LP  = Players.LocalPlayer

-------------------------------------------------------------------
-- helpers
-------------------------------------------------------------------
local function httpGet(url)
	local ok, body = pcall(function() return game:HttpGet(url, true) end)
	if ok and body and #body > 0 then return body end
	if syn and syn.request then
		local o, r = pcall(syn.request, { Url = url, Method = "GET" })
		if o and r and r.Body then return r.Body end
	end
	if request then
		local o, r = pcall(request, { Url = url, Method = "GET" })
		if o and r and r.Body then return r.Body end
	end
	return nil
end

local function json(body)
	local ok, d = pcall(function() return HttpService:JSONDecode(body) end)
	return ok and d or nil
end

local UNIVERSE = game.GameId
if UNIVERSE == 0 then
	local d = json(httpGet("https://apis.roblox.com/universes/v1/places/" .. game.PlaceId .. "/universe") or "")
	if d and d.universeId then UNIVERSE = d.universeId end
end

-------------------------------------------------------------------
-- state
-------------------------------------------------------------------
local ITEMS      = {}
local SEEN       = {}
local ROWS       = {}
local ACTIVE     = "pass"
local QUERY      = ""
local alive      = true
local promptLock = false

local function addItem(kind, id, name, price, forSale)
	if not id then return false end
	local key = kind .. ":" .. tostring(id)
	if SEEN[key] then return false end
	SEEN[key] = true
	ITEMS[#ITEMS + 1] = {
		kind    = kind,
		id      = id,
		name    = name or ("Unnamed " .. kind .. " #" .. tostring(id)),
		price   = price,
		forSale = forSale,
	}
	return true
end

local function priceText(it)
	if it.forSale == false or it.price == nil then return "OFF SALE" end
	if it.price == 0 then return "FREE" end
	return "R$ " .. tostring(it.price)
end

-------------------------------------------------------------------
-- fetching  (engine APIs + web APIs, merged & de-duped)
-------------------------------------------------------------------
local function fetchPassesEngine()
	local ok, pages = pcall(function() return MarketplaceService:GetGamePasses(UNIVERSE) end)
	if not ok or not pages then return end
	local guard = 0
	repeat
		guard += 1
		for _, gp in ipairs(pages:GetCurrentPage()) do
			addItem("pass", gp.Id, gp.Name, gp.Price, nil)
		end
		if pages.IsFinished then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		task.wait()
	until guard > 30
end

local function fetchPassesWeb()
	local cursor, guard = nil, 0
	repeat
		guard += 1
		local url = "https://games.roblox.com/v1/games/" .. UNIVERSE ..
			"/game-passes?limit=100&sortOrder=Asc"
		if cursor then url = url .. "&cursor=" .. cursor end
		local data = json(httpGet(url) or "")
		if not data then break end
		for _, p in ipairs(data.gamePasses or {}) do
			addItem("pass", p.id, p.displayName or p.name, p.price, p.isForSale)
		end
		cursor = data.nextPageCursor
		task.wait(0.2)
	until not cursor or cursor == "" or guard > 30
end

local function fetchProductsEngine()
	local ok, pages = pcall(function() return MarketplaceService:GetDeveloperProductsAsync() end)
	if not ok or not pages then return end
	local guard = 0
	repeat
		guard += 1
		for _, dp in ipairs(pages:GetCurrentPage()) do
			addItem("product", dp.ProductId, dp.Name, dp.PriceInRobux, true)
		end
		if pages.IsFinished then break end
		if not pcall(function() pages:AdvanceToNextPageAsync() end) then break end
		task.wait()
	until guard > 30
end

local function fetchProductsWeb()
	local cursor, guard = nil, 0
	repeat
		guard += 1
		local url = "https://apis.roblox.com/developer-products/v2/universes/" .. UNIVERSE ..
			"/developerproducts?limit=50"
		if cursor then url = url .. "&cursor=" .. cursor end
		local data = json(httpGet(url) or "")
		if not data then break end
		for _, p in ipairs(data.developerProducts or data.data or {}) do
			addItem("product", p.productId, p.name, p.priceInRobux, true)
		end
		cursor = data.nextPageCursor
		task.wait(0.2)
	until not cursor or cursor == "" or guard > 30
end

-------------------------------------------------------------------
-- gui shell
-------------------------------------------------------------------
local parentGui = (gethui and gethui()) or LP:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "PassProductBrowser"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parentGui
genv.PPBrowserGui = gui

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(480, 440)
main.Position = UDim2.new(0.5, -240, 0.5, -220)
main.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
main.BorderSizePixel = 0
main.Active = true
main.Visible = false
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)
local mStroke = Instance.new("UIStroke", main)
mStroke.Color = Color3.fromRGB(58, 58, 68)

-- header ------------------------------------------------------
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 40)
header.BackgroundColor3 = Color3.fromRGB(31, 31, 37)
header.BorderSizePixel = 0
header.Parent = main
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)
local hFix = Instance.new("Frame")
hFix.Size = UDim2.new(1, 0, 0, 12)
hFix.Position = UDim2.new(0, 0, 1, -12)
hFix.BackgroundColor3 = Color3.fromRGB(31, 31, 37)
hFix.BorderSizePixel = 0
hFix.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(12, 0)
title.Size = UDim2.new(1, -80, 1, 0)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Text = "PASS / PRODUCT BROWSER"
title.Parent = header

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(26, 26)
closeBtn.Position = UDim2.new(1, -34, 0.5, -13)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 60, 60)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- tabs --------------------------------------------------------
local function makeTab(text, x, w)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 26)
	b.Position = UDim2.fromOffset(x, 46)
	b.BackgroundColor3 = Color3.fromRGB(36, 36, 43)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = Color3.fromRGB(200, 200, 210)
	b.Text = text
	b.Parent = main
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

local tabPass    = makeTab("Game Passes (0)", 10, 120)
local tabProd    = makeTab("Products (0)", 136, 120)
local refreshBtn = makeTab("Rescan", 262, 56)

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(324, 42)
hint.Size = UDim2.new(0, 146, 0, 36)
hint.Font = Enum.Font.Gotham
hint.TextSize = 9
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Right
hint.TextYAlignment = Enum.TextYAlignment.Top
hint.TextColor3 = Color3.fromRGB(115, 115, 132)
hint.Text = "copy ID: right-click\ndiagnose: shift+click\nweb link: ctrl+click"
hint.Parent = main

-- search ------------------------------------------------------
local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -20, 0, 28)
search.Position = UDim2.fromOffset(10, 78)
search.BackgroundColor3 = Color3.fromRGB(32, 32, 38)
search.BorderSizePixel = 0
search.Font = Enum.Font.Gotham
search.TextSize = 13
search.TextColor3 = Color3.fromRGB(230, 230, 235)
search.PlaceholderText = "Search by name or ID..."
search.PlaceholderColor3 = Color3.fromRGB(105, 105, 120)
search.Text = ""
search.ClearTextOnFocus = false
search.Parent = main
Instance.new("UICorner", search).CornerRadius = UDim.new(0, 6)

-- list --------------------------------------------------------
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -160)
list.Position = UDim2.fromOffset(10, 112)
list.BackgroundColor3 = Color3.fromRGB(26, 26, 31)
list.BorderSizePixel = 0
list.ScrollBarThickness = 5
list.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 95)
list.CanvasSize = UDim2.new()
list.Parent = main
Instance.new("UICorner", list).CornerRadius = UDim.new(0, 6)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 4)
pad.PaddingRight = UDim.new(0, 4)
pad.PaddingBottom = UDim.new(0, 6)
pad.Parent = list

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 18)
status.Position = UDim2.new(0, 10, 1, -32)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(130, 130, 145)
status.Text = "scanning..."
status.Parent = main

-- floating toggle ---------------------------------------------
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(46, 46)
toggle.Position = UDim2.new(0, 16, 1, -110)
toggle.BackgroundColor3 = Color3.fromRGB(0, 145, 220)
toggle.Text = "GP"
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 16
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Parent = gui
Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 23)
toggle.MouseButton1Click:Connect(function() main.Visible = not main.Visible end)
closeBtn.MouseButton1Click:Connect(function() main.Visible = false end)

-------------------------------------------------------------------
-- prompt dispatch
-- executor threads can be "blocked" for this API, so try several
-- call paths and remember whichever one gets through.
-------------------------------------------------------------------
local getIdent = getthreadidentity or getidentity
local setIdent = setthreadidentity or setidentity

local function rawPrompt(kind, id, viaDot)
	if kind == "pass" then
		if viaDot then
			MarketplaceService.PromptGamePassPurchase(MarketplaceService, LP, id)
		else
			MarketplaceService:PromptGamePassPurchase(LP, id)
		end
	else
		if viaDot then
			MarketplaceService.PromptProductPurchase(MarketplaceService, LP, id)
		else
			MarketplaceService:PromptProductPurchase(LP, id)
		end
	end
end

local function withIdentity(n, fn)
	local prev
	if type(setIdent) == "function" then
		pcall(function() prev = getIdent and getIdent() end)
		pcall(setIdent, n)
	end
	local ok, err = pcall(fn)
	if type(setIdent) == "function" and type(prev) == "number" then
		pcall(setIdent, prev)
	end
	if not ok then error(err, 0) end
end

local STRATEGIES = {
	{ name = "dotcall",   fn = function(k, id) rawPrompt(k, id, true) end },
	{ name = "direct",    fn = function(k, id) rawPrompt(k, id, false) end },
	{ name = "yield",     fn = function(k, id) task.wait() rawPrompt(k, id, false) end },
	{ name = "ident2",    fn = function(k, id)
		withIdentity(2, function() rawPrompt(k, id, false) end)
	end },
	{ name = "ident8",    fn = function(k, id)
		withIdentity(8, function() rawPrompt(k, id, false) end)
	end },
	{ name = "heartbeat", fn = function(k, id)
		local fired = false
		local conn
		conn = RunService.Heartbeat:Connect(function()
			conn:Disconnect()
			rawPrompt(k, id, false)
			fired = true
		end)
		local t = 0
		while not fired and t < 1 do t += task.wait() end
	end },
	{ name = "altapi",    fn = function(k, id)
		MarketplaceService:PromptPurchase(LP, id)
	end },
}

local bestStrategy

local function dispatch(kind, id)
	local order = {}
	if bestStrategy then order[#order + 1] = bestStrategy end
	for _, s in ipairs(STRATEGIES) do
		if s ~= bestStrategy then order[#order + 1] = s end
	end

	for _, s in ipairs(order) do
		local ok, err = pcall(s.fn, kind, id)
		if ok then
			if bestStrategy ~= s then
				bestStrategy = s
				print("[browser] prompt strategy -> " .. s.name)
			end
			return true, s.name
		end
		print("[browser] strategy '" .. s.name .. "' blocked: " .. tostring(err))
		task.wait(0.2)
	end
	return false, "none"
end

local function diagnose(kind, id)
	print("=== prompt diagnostic: " .. kind .. " " .. tostring(id) .. " ===")
	print("executor:", identifyexecutor and identifyexecutor() or "unknown")
	print("thread identity:", getIdent and tostring(getIdent()) or "n/a")
	for _, s in ipairs(STRATEGIES) do
		local ok, err = pcall(s.fn, kind, id)
		print(string.format("  %-10s %s%s", s.name,
			ok and "OK" or "FAIL", ok and "" or ("   " .. tostring(err))))
		task.wait(1.3)
	end
	print("=== end diagnostic ===")
end

local function firePrompt(it, mode)
	local id = tonumber(it.id)
	if not id then return end

	if mode == "web" then
		local url = it.kind == "pass"
			and ("https://www.roblox.com/game-pass/" .. id)
			or ("https://www.roblox.com/developer-product/" .. id)
		if setclipboard then setclipboard(url) end
		status.Text = "copied: " .. url
		return
	end

	if promptLock then
		status.Text = "busy, wait a moment..."
		return
	end
	promptLock = true

	task.spawn(function()
		if mode == "diag" then
			status.Text = "running diagnostic..."
			diagnose(it.kind, id)
			status.Text = "diagnostic printed to console"
		else
			status.Text = "prompting " .. it.kind .. " " .. id .. "..."
			local ok, used = dispatch(it.kind, id)
			if ok then
				status.Text = "prompted " .. it.kind .. " " .. id .. "  [" .. used .. "]"
			else
				status.Text = "every prompt path blocked - ctrl+click for the web link"
			end
		end
		task.wait(1.2)
		promptLock = false
	end)
end

-------------------------------------------------------------------
-- render
-------------------------------------------------------------------
local function render()
	for _, r in ipairs(ROWS) do r:Destroy() end
	ROWS = {}

	local nPass, nProd = 0, 0
	for _, it in ipairs(ITEMS) do
		if it.kind == "pass" then nPass += 1 else nProd += 1 end
	end
	tabPass.Text = "Game Passes (" .. nPass .. ")"
	tabProd.Text = "Products (" .. nProd .. ")"
	tabPass.BackgroundColor3 = ACTIVE == "pass" and Color3.fromRGB(0, 130, 200) or Color3.fromRGB(36, 36, 43)
	tabProd.BackgroundColor3 = ACTIVE == "product" and Color3.fromRGB(0, 130, 200) or Color3.fromRGB(36, 36, 43)

	local shown = {}
	for _, it in ipairs(ITEMS) do
		if it.kind == ACTIVE then
			local q = QUERY
			if q == ""
				or string.find(string.lower(it.name), q, 1, true)
				or string.find(tostring(it.id), q, 1, true)
			then
				shown[#shown + 1] = it
			end
		end
	end

	table.sort(shown, function(a, b)
		local ap = a.price or math.huge
		local bp = b.price or math.huge
		if ap ~= bp then return ap < bp end
		return a.name < b.name
	end)

	for i, it in ipairs(shown) do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, -4, 0, 38)
		row.BackgroundColor3 = Color3.fromRGB(34, 34, 41)
		row.Text = ""
		row.AutoButtonColor = false
		row.LayoutOrder = i
		row.Parent = list
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1
		nm.Position = UDim2.fromOffset(9, 3)
		nm.Size = UDim2.new(1, -108, 0, 16)
		nm.Font = Enum.Font.GothamMedium
		nm.TextSize = 13
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextColor3 = Color3.fromRGB(235, 235, 242)
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.Text = it.name
		nm.Parent = row

		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromOffset(9, 19)
		sub.Size = UDim2.new(1, -108, 0, 15)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 11
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.TextColor3 = Color3.fromRGB(118, 118, 134)
		sub.Text = (it.kind == "pass" and "Pass ID " or "Product ID ") .. it.id
		sub.Parent = row

		local pr = Instance.new("TextLabel")
		pr.AnchorPoint = Vector2.new(1, 0.5)
		pr.Position = UDim2.new(1, -9, 0.5, 0)
		pr.Size = UDim2.fromOffset(94, 20)
		pr.BackgroundTransparency = 1
		pr.Font = Enum.Font.GothamBold
		pr.TextSize = 13
		pr.TextXAlignment = Enum.TextXAlignment.Right
		pr.Text = priceText(it)
		pr.TextColor3 = (it.forSale == false or it.price == nil)
			and Color3.fromRGB(150, 90, 90)
			or Color3.fromRGB(120, 220, 140)
		pr.Parent = row

		row.MouseEnter:Connect(function()
			row.BackgroundColor3 = Color3.fromRGB(44, 44, 54)
		end)
		row.MouseLeave:Connect(function()
			row.BackgroundColor3 = Color3.fromRGB(34, 34, 41)
		end)

		row.MouseButton1Click:Connect(function()
			if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
				firePrompt(it, "diag")
			elseif UIS:IsKeyDown(Enum.KeyCode.LeftControl)
				or UIS:IsKeyDown(Enum.KeyCode.RightControl) then
				firePrompt(it, "web")
			else
				firePrompt(it, "auto")
			end
		end)

		row.MouseButton2Click:Connect(function()
			if setclipboard then
				setclipboard(tostring(it.id))
				status.Text = "copied ID " .. it.id
			end
		end)

		ROWS[#ROWS + 1] = row
	end

	list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
	status.Text = string.format("%d game passes  |  %d products  |  showing %d",
		nPass, nProd, #shown)
end

tabPass.MouseButton1Click:Connect(function() ACTIVE = "pass"; render() end)
tabProd.MouseButton1Click:Connect(function() ACTIVE = "product"; render() end)

search:GetPropertyChangedSignal("Text"):Connect(function()
	QUERY = string.lower(search.Text)
	render()
end)

-------------------------------------------------------------------
-- drag
-------------------------------------------------------------------
local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = main.Position
	end
end)
UIS.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - dragStart
		main.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)
UIS.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.F2 then
		main.Visible = not main.Visible
	end
end)

-------------------------------------------------------------------
-- enrichment: fill in real price / on-sale status + verify asset type
-------------------------------------------------------------------
local function enrich()
	for _, it in ipairs(ITEMS) do
		if not alive then return end

		local expected = it.kind == "pass" and 34 or 35

		if it.price == nil or it.forSale == nil or it.assetType == nil then
			local infoType = it.kind == "pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(it.id, infoType)
			end)

			if ok and info then
				it.assetType = info.AssetTypeId
				if info.Name and info.Name ~= "" then it.name = info.Name end
				it.forSale = info.IsForSale
				it.price = info.IsForSale and info.PriceInRobux or nil

				if it.assetType and it.assetType ~= expected then
					print(string.format("[warn] %s %d is AssetTypeId %d (expected %d)",
						it.kind, it.id, it.assetType, expected))
				end
			else
				it.forSale = false
			end

			render()
			task.wait(0.07)
		end
	end
	render()
end

-------------------------------------------------------------------
-- bonus: catch passes/products the game uses at runtime
-- set genv.PPBrowserNoHook = true before running to skip it
-------------------------------------------------------------------
local function installHook()
	local ok, mt = pcall(getrawmetatable, game)
	if not ok or not mt or not mt.__namecall then return end
	local old = mt.__namecall
	local wrap = newcclosure or function(f) return f end

	setreadonly(mt, false)
	mt.__namecall = wrap(function(self, ...)
		local method = getnamecallmethod()
		if method == "PromptGamePassPurchase" or method == "PromptProductPurchase" then
			local args = { ... }
			local id = args[2] or args[1]
			if type(id) == "number" then
				local kind = method == "PromptGamePassPurchase" and "pass" or "product"
				if addItem(kind, id, nil, nil, nil) then render() end
			end
		end
		return old(self, ...)
	end)
	setreadonly(mt, true)

	genv.PPBrowserUnhook = function()
		setreadonly(mt, false)
		mt.__namecall = old
		setreadonly(mt, true)
	end
end

-------------------------------------------------------------------
-- go
-------------------------------------------------------------------
task.spawn(function()
	if not genv.PPBrowserNoHook then installHook() end

	print(string.format("[browser] universe %s | executor %s | identity %s | newcclosure %s",
		tostring(UNIVERSE),
		identifyexecutor and identifyexecutor() or "unknown",
		getIdent and tostring(getIdent()) or "n/a",
		newcclosure and "yes" or "NO"))

	status.Text = "scanning universe " .. UNIVERSE .. "..."
	fetchPassesEngine();   render()
	fetchProductsEngine(); render()
	fetchPassesWeb();      render()
	fetchProductsWeb();    render()
	enrich()
	status.Text = status.Text .. "  (done)"
end)

refreshBtn.MouseButton1Click:Connect(function()
	status.Text = "rescanning..."
	task.spawn(function()
		fetchPassesEngine();   fetchPassesWeb();   render()
		fetchProductsEngine(); fetchProductsWeb(); render()
		enrich()
	end)
end)

main.Visible = true
