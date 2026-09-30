local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local starterGui = game:GetService("StarterGui")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")
local guiService = game:GetService("GuiService")
local contextActionService = game:GetService("ContextActionService")

-- Runs from ReplicatedFirst next to the Lobby gui. Characters never load in the
-- lobby, so StarterGui is never copied into PlayerGui; we move the gui ourselves.
local playerGui = playersService.LocalPlayer:WaitForChild("PlayerGui")
local gui = script.Parent:WaitForChild("Lobby")
gui.Parent = playerGui

-- ReplicatedFirst runs before the rest of the game has replicated
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local names = require(replicatedStorage.Shared.Names)
local platform = require(replicatedStorage.Shared.Platform)
local protocol = require(replicatedStorage.Shared.Protocol)

local remotes = replicatedStorage.Remotes

local templates = gui.Templates
local stage = gui.Stage
local bleed = gui.Background.Bleed
local picker = stage.Picker
local mapView = stage.MapView
local info = mapView.Info
local browser = mapView.Browser
local footer = browser.Footer
local statusBox = stage.Status

----

local STAGE = Vector2.new(1440, 810)

local SLIDE = 6
local CARD_CYCLE = 8
local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
local PAN = TweenInfo.new(SLIDE + 1.5, Enum.EasingStyle.Linear)
local QUICK = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SPIN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- how far each preview shot drifts; images are 1.12x the frame, so keep under 0.06
local DRIFTS = {
	Vector2.new(0.035, 0.015),
	Vector2.new(-0.03, 0.02),
	Vector2.new(0.02, -0.025),
	Vector2.new(-0.035, -0.01),
}

local BONE = Color3.fromRGB(229, 226, 219)
local GOLD = Color3.fromRGB(202, 188, 131)
local GRUNGE_TINT = Color3.fromRGB(255, 193, 138)
local AMBER = Color3.fromRGB(227, 166, 74)
local DIM = Color3.fromRGB(85, 85, 85)
local LOCKED_STROKE = Color3.fromRGB(124, 124, 124)
local LOCKED_TINT = Color3.fromRGB(193, 193, 193)

local STATUS_TEXT = {
	joining = "joining",
	full = "server full",
	closed = "server closed",
	failed = "couldn't join",
	denied = "no access",
	password = "wrong password",
	slow = "too many tries",
	unavailable = "unavailable",
}

-- sort chip name -> mode
local SORTS = {
	Players = "players",
	Newest = "newest",
	Region = "region",
}

local here = platform:Detect()

-- the server sends the maps this player may see (the test lobby hides some
-- by group role), in display order, with each one's servers
local maps = {}
local mapsByKey = {}
local snapshot = {}
local liveMaps = {}
local cards = {}
local rows = {} -- [jobId] = row

local openMap = nil
local selectedId = nil
local sortMode = "players"
local joining = false
local slideToken = 0
local lastRefresh = -math.huge

----

-- "Beta Map" -> "B E T A   M A P", the game's header style
local function spaced(text)
	local words = {}

	for word in text:upper():gmatch("%S+") do
		local letters = word:gsub("(.)", "%1 ")
		table.insert(words, (letters:gsub(" $", "")))
	end

	return table.concat(words, "   ")
end

local function titleText(map)
	local first, rest = map.Name:match("^(%S+)%s*(.*)$")
	local title = string.format('<font color="%s">%s</font>', map.Accent, spaced(first))

	if rest ~= "" then
		title ..= "   " .. spaced(rest)
	end

	return title
end

-- text boxes hold the label and its drop-shadow copy; keep them in step
local function setText(box, text)
	box.Text.Text = text
	box.Shadow.Text = (text:gsub("<[^>]+>", ""))
end

local function formatUptime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

local function clear(bin)
	for _, child in bin:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function usingGamepad()
	return userInputService:GetLastInputType().Name:find("Gamepad") ~= nil
end

local function focus(object)
	if object and usingGamepad() then
		guiService.SelectedObject = object
	end
end

----

-- the game's button frames: highlight on hover, ignore clicks while disabled
local function bindButton(frame, callback)
	frame.Button.MouseEnter:Connect(function()
		frame.HighlightBox.Visible = not frame:GetAttribute("Disabled")
	end)

	frame.Button.MouseLeave:Connect(function()
		frame.HighlightBox.Visible = false
	end)

	frame.Button.Activated:Connect(function()
		if not frame:GetAttribute("Disabled") then
			callback()
		end
	end)
end

-- greys a gold button out like the game's Locked/Full buttons
local function setEnabled(frame, enabled)
	frame:SetAttribute("Disabled", not enabled)
	frame.Stroke.Color = enabled and GOLD or LOCKED_STROKE
	frame.Backdrop.ImageColor3 = enabled and GRUNGE_TINT or LOCKED_TINT
	frame.Label.Text.TextColor3 = enabled and GOLD or DIM
	frame.Button.Selectable = enabled

	if not enabled then
		frame.HighlightBox.Visible = false
	end
end

local function setStatus(code)
	local text = code and STATUS_TEXT[code]

	joining = code == "joining"
	statusBox.Visible = text ~= nil

	if text then
		setText(statusBox, spaced(text))
	end
end

local function drawChips(bin, map)
	clear(bin)

	for index, entry in platform.List do
		local support = platform:Support(map, entry.Key)
		local color = support == "blocked" and DIM or support == "warn" and AMBER or BONE
		local chip = templates.PlatformChip:Clone()

		chip.Name = entry.Key
		chip.LayoutOrder = index
		chip.Stroke.Color = color
		-- the chip for the platform you're on stands out a little
		chip.Stroke.Transparency = entry.Key == here and 0.15 or 0.7

		if entry.Icon ~= "" then
			chip.Icon.Image = entry.Icon
			chip.Icon.ImageColor3 = color
			chip.Icon.Visible = true
			chip.Label.Visible = false
		else
			chip.Label.Text = support == "blocked" and ("<s>" .. entry.Short .. "</s>") or entry.Short
			chip.Label.TextColor3 = color
		end

		chip.Visible = true
		chip.Parent = bin
	end
end

----

local function play(mapKey, jobId)
	local map = openMap

	if joining or not map or map.Key ~= mapKey or not liveMaps[mapKey] then
		return
	end

	if platform:Support(map, here) == "blocked" then
		return
	end

	local password = map.Password and info.Buttons.Password.Input.Text or nil

	setStatus("joining")
	remotes.Play:FireServer(mapKey, jobId, password)
end

local function refresh()
	if os.clock() - lastRefresh < protocol.REFRESH_COOLDOWN then
		return
	end

	lastRefresh = os.clock()
	remotes.Refresh:FireServer()

	-- rotation isn't inherited, so spin the glyph and its shadow directly
	local icon = info.Buttons.Refresh.Icon
	local spinning = icon:IsA("ImageLabel") and { icon } or { icon.Text, icon.Shadow }

	for _, object in spinning do
		object.Rotation = 0
		tweenService:Create(object, SPIN, { Rotation = 360 }):Play()
	end
end

----

local function sortServers(servers)
	table.sort(servers, function(a, b)
		local aFull = a.Players >= a.Max
		local bFull = b.Players >= b.Max

		if aFull ~= bFull then
			return bFull
		end

		if sortMode == "newest" and a.StartedAt ~= b.StartedAt then
			return a.StartedAt > b.StartedAt
		end

		if sortMode == "region" and (a.Region or "") ~= (b.Region or "") then
			-- servers without a region go last
			return (a.Region or "~") < (b.Region or "~")
		end

		if a.Players ~= b.Players then
			return a.Players > b.Players
		end

		return a.Id < b.Id
	end)
end

local drawServers

local function makeRow(jobId)
	local row = templates.ServerRow:Clone()
	row.Visible = true
	rows[jobId] = row

	row.MouseEnter:Connect(function()
		row.HighlightBox.Visible = not row:GetAttribute("Full")
	end)

	row.MouseLeave:Connect(function()
		row.HighlightBox.Visible = selectedId == jobId
	end)

	-- first press selects, pressing the selected row again joins it
	row.Activated:Connect(function()
		if row:GetAttribute("Full") then
			return
		end

		if selectedId == jobId then
			play(openMap.Key, jobId)
		else
			selectedId = jobId
			drawServers()
		end
	end)

	row.Parent = browser.List

	return row
end

function drawServers()
	if not openMap then
		return
	end

	local bucket = snapshot[openMap.Key]
	local servers = table.clone(bucket and bucket.Servers or {})
	local now = workspace:GetServerTimeNow()
	local picked = nil
	local seen = {}

	sortServers(servers)

	-- keep the selection while that server is up and has room
	for _, server in servers do
		if server.Id == selectedId and server.Players < server.Max then
			picked = server
		end
	end

	if not picked then
		for _, server in servers do
			if server.Players < server.Max then
				picked = server

				break
			end
		end
	end

	selectedId = picked and picked.Id

	for index, server in servers do
		local row = rows[server.Id] or makeRow(server.Id)
		local full = server.Players >= server.Max
		local ink = full and DIM or BONE
		local chosen = server.Id == selectedId

		seen[server.Id] = true

		row.LayoutOrder = index
		row.Selectable = not full
		row:SetAttribute("Full", full)
		row.Stroke.Enabled = chosen
		row.HighlightBox.Visible = chosen

		setText(row.Server, names:ForJob(server.Id))
		setText(row.Id, names:ShortId(server.Id))
		setText(row.Region, server.Region or "—")
		setText(row.Uptime, formatUptime(math.max(0, now - server.StartedAt)))
		setText(row.Players, full and "FULL" or string.format("%d / %d", server.Players, server.Max))

		for _, cell in { row.Server, row.Region, row.Uptime, row.Players } do
			cell.Text.TextColor3 = ink
		end
	end

	for jobId, row in rows do
		if not seen[jobId] then
			row:Destroy()
			rows[jobId] = nil
		end
	end

	browser.Empty.Visible = #servers == 0

	if picked then
		setText(footer.ServerName, names:ForJob(picked.Id):upper())
		setText(footer.Meta, table.concat({
			names:ShortId(picked.Id),
			picked.Region or "—",
			"up " .. formatUptime(math.max(0, now - picked.StartedAt)),
			string.format("%d / %d", picked.Players, picked.Max),
		}, "  ·  "))
	else
		setText(footer.ServerName, "")
		setText(footer.Meta, "")
	end

	setEnabled(footer.Join, picked ~= nil and platform:Support(openMap, here) ~= "blocked")

	setText(info.Counts.Online, string.format("%d online", bucket and bucket.Online or 0))
	setText(info.Counts.Servers, string.format("%d servers", #servers))
end

local function drawSorts()
	for chipName, mode in SORTS do
		local chip = browser.Sorts[chipName]
		local on = mode == sortMode

		chip.Label.TextTransparency = on and 0 or 0.5
		chip.Stroke.Transparency = on and 0.4 or 0.8
		chip.BackgroundTransparency = on and 0.15 or 0.6
	end
end

----

local function panShot(image, index)
	local drift = DRIFTS[(index - 1) % #DRIFTS + 1]

	image.Position = UDim2.fromScale(0.5 - drift.X, 0.5 - drift.Y)
	tweenService:Create(image, PAN, { Position = UDim2.fromScale(0.5 + drift.X, 0.5 + drift.Y) }):Play()
end

-- crossfades the preview through the map's images, each one drifting slowly
local function startSlides(images)
	slideToken += 1

	local token = slideToken
	local clip = info.Preview.Clip
	local front, back = clip.ImageA, clip.ImageB

	front.Image = images[1] or ""
	front.ImageTransparency = 0
	front.ZIndex = 1
	back.ImageTransparency = 1

	if #images == 0 then
		return
	end

	task.spawn(function()
		local index = 1

		panShot(front, index)

		while true do
			task.wait(SLIDE)

			if token ~= slideToken then
				return
			end

			if #images < 2 then
				panShot(front, index)

				continue
			end

			index = index % #images + 1

			back.Image = images[index]
			back.ImageTransparency = 1
			back.ZIndex = 2
			front.ZIndex = 1

			panShot(back, index)
			tweenService:Create(back, FADE, { ImageTransparency = 0 }):Play()

			front, back = back, front
		end
	end)
end

local function drawNotice(map)
	local support = platform:Support(map, here)
	local long = platform.ByKey[here].Long

	info.Notice.Visible = support ~= "ok"

	if support == "warn" then
		setText(info.Notice, spaced("limited support on " .. long))
		info.Notice.Text.TextColor3 = AMBER
	elseif support == "blocked" then
		setText(info.Notice, spaced("not available on " .. long))
		info.Notice.Text.TextColor3 = LOCKED_TINT
	end

	setEnabled(info.Buttons.Play, support ~= "blocked")
end

local function openMapView(map)
	if not liveMaps[map.Key] then
		return
	end

	openMap = map
	selectedId = nil

	for _, row in rows do
		row:Destroy()
	end

	table.clear(rows)

	setText(info.Title, titleText(map))
	setText(info.Blurb, map.Blurb or "")
	info.Blurb.Visible = (map.Blurb or "") ~= ""

	clear(info.Stats)

	for index, stat in map.Stats or {} do
		local item = templates.StatItem:Clone()
		item.LayoutOrder = index
		setText(item.Label, stat[1])
		setText(item.Value, stat[2])
		item.Visible = true
		item.Parent = info.Stats
	end

	info.Stats.Visible = #(map.Stats or {}) > 0

	drawChips(info.Platforms, map)
	drawNotice(map)

	info.Buttons.Password.Visible = map.Password == true
	info.Buttons.Password.Input.Text = ""

	if map.Backdrop then
		bleed.Image = map.Backdrop
		tweenService:Create(bleed, QUICK, { ImageTransparency = 0.35 }):Play()
	else
		bleed.ImageTransparency = 1
	end

	startSlides(map.Images or {})
	drawServers()

	picker.Visible = false
	mapView.Visible = true

	focus(info.Buttons.Play.Button)
end

local function closeMapView()
	if not openMap then
		return
	end

	local card = cards[openMap.Key]

	openMap = nil
	slideToken += 1

	tweenService:Create(bleed, QUICK, { ImageTransparency = 1 }):Play()

	mapView.Visible = false
	picker.Visible = true

	focus(card and card.Button)
end

----

local function cycleArt(card, images)
	local art = card.Clip.Art
	local index = 1

	art.Image = images[1] or ""

	if #images < 2 then
		return
	end

	task.spawn(function()
		while card.Parent do
			task.wait(CARD_CYCLE)

			index = index % #images + 1

			local out = tweenService:Create(art, QUICK, { ImageTransparency = 1 })
			out:Play()
			out.Completed:Wait()

			art.Image = images[index]
			tweenService:Create(art, QUICK, { ImageTransparency = 0 }):Play()
		end
	end)
end

local function drawCard(map)
	local card = cards[map.Key]
	local bucket = snapshot[map.Key]
	local live = liveMaps[map.Key] == true

	card.ComingSoon.Visible = not live
	card.Online.Visible = live and bucket ~= nil
	card.Button.Selectable = live

	if bucket then
		setText(card.Online, string.format("%d online", bucket.Online))
	end
end

local function makeCard(map, index)
	local card = templates.MapCard:Clone()
	card.Name = map.Key
	card.LayoutOrder = index
	card.Visible = true

	setText(card.Title, titleText(map))
	drawChips(card.Platforms, map)
	cycleArt(card, map.Images or {})

	card.Button.MouseEnter:Connect(function()
		card.HighlightBox.Visible = liveMaps[map.Key] == true
	end)

	card.Button.MouseLeave:Connect(function()
		card.HighlightBox.Visible = false
	end)

	card.Button.Activated:Connect(function()
		openMapView(map)
	end)

	cards[map.Key] = card
	card.Parent = picker.Maps

	drawCard(map)
end

-- keeps cards in step with the server's list; maps can appear, vanish or
-- change (a role change, a test map added)
local function syncMaps(list)
	local seen = {}

	table.clear(maps)
	table.clear(mapsByKey)
	table.clear(liveMaps)

	for index, map in list do
		table.insert(maps, map)
		mapsByKey[map.Key] = map
		liveMaps[map.Key] = map.Live == true
		seen[map.Key] = true

		if cards[map.Key] then
			cards[map.Key].LayoutOrder = index
		else
			makeCard(map, index)
		end
	end

	for key, card in cards do
		if not seen[key] then
			card:Destroy()
			cards[key] = nil
		end
	end

	for _, map in maps do
		drawCard(map)
	end

	if openMap then
		if mapsByKey[openMap.Key] then
			openMap = mapsByKey[openMap.Key]
		else
			closeMapView()
		end
	end
end

----

-- the gui is inset clear of Roblox's buttons; the stage (laid out at
-- 1440x810) scales to fit inside that, the background covers the whole screen
local function fit()
	local size = gui.AbsoluteSize
	local camera = workspace.CurrentCamera
	local background = gui.Background

	if size.X > 0 and size.Y > 0 then
		stage.Scale.Scale = math.min(size.X / STAGE.X, size.Y / STAGE.Y)
	end

	if camera then
		background.Position = UDim2.fromOffset(-gui.AbsolutePosition.X, -gui.AbsolutePosition.Y)
		background.Size = UDim2.fromOffset(camera.ViewportSize.X, camera.ViewportSize.Y)
	end
end

for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu } do
	pcall(starterGui.SetCoreGuiEnabled, starterGui, coreGui, false)
end

fit()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
end

-- gamepad focus uses the game's highlight box instead of Roblox's default ring
local selection = templates.Selection:Clone()
selection.Visible = true
playerGui.SelectionImageObject = selection

bindButton(info.Buttons.Back, closeMapView)
bindButton(info.Buttons.Refresh, refresh)

bindButton(info.Buttons.Play, function()
	if openMap then
		play(openMap.Key)
	end
end)

bindButton(footer.Join, function()
	if openMap and selectedId then
		play(openMap.Key, selectedId)
	end
end)

for chipName, mode in SORTS do
	local chip = browser.Sorts[chipName]

	chip.Button.MouseEnter:Connect(function()
		chip.HighlightBox.Visible = true
	end)

	chip.Button.MouseLeave:Connect(function()
		chip.HighlightBox.Visible = false
	end)

	chip.Button.Activated:Connect(function()
		sortMode = mode
		drawSorts()
		drawServers()
	end)
end

drawSorts()

contextActionService:BindAction("LobbyBack", function(_, state)
	if state == Enum.UserInputState.Begin and openMap then
		closeMapView()
	end

	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.ButtonB)

contextActionService:BindAction("LobbyRefresh", function(_, state)
	if state == Enum.UserInputState.Begin and openMap then
		refresh()
	end

	return Enum.ContextActionResult.Pass
end, false, Enum.KeyCode.ButtonX)

remotes.Directory.OnClientEvent:Connect(function(payload)
	local first = next(cards) == nil

	snapshot = payload and payload.Servers or {}
	syncMaps(payload and payload.Maps or {})
	drawServers()

	if first and maps[1] then
		focus(cards[maps[1].Key].Button)
	end
end)

remotes.Status.OnClientEvent:Connect(function(code)
	setStatus(code)

	if code ~= "joining" then
		task.delay(3, function()
			if not joining and statusBox.Text.Text == spaced(STATUS_TEXT[code] or "") then
				setStatus(nil)
			end
		end)
	end
end)
