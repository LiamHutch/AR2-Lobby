local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local starterGui = game:GetService("StarterGui")
local tweenService = game:GetService("TweenService")

local maps = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("Maps"))

local remotes = replicatedStorage:WaitForChild("Remotes")

local gui = playersService.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Lobby")
local templates = gui:WaitForChild("Templates")
local mapsBin = gui:WaitForChild("Maps")
local serversPanel = gui:WaitForChild("Servers")
local statusLabel = gui:WaitForChild("Status")

----

local IMAGE_CYCLE = 6
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local STATUS_TEXT = {
	joining = "joining",
	full = "server full",
	closed = "server closed",
	failed = "couldn't join",
}

local cards = {}
local snapshot = {}
local liveMaps = {}
local openMapKey = nil
local joining = false

----

local function spaced(text)
	return (text:upper():gsub("(%S)", "%1 "):gsub(" $", ""))
end

local function titleText(map)
	local first, rest = map.Name:match("^(%S+)%s*(.*)$")
	local title = string.format('<font color="%s">%s</font>', map.Accent, spaced(first))

	if rest ~= "" then
		title = title .. "   " .. spaced(rest)
	end

	return title
end

local function formatUptime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end

	return string.format("%dm", minutes)
end

local function hover(button, highlight)
	button.MouseEnter:Connect(function()
		highlight.Visible = true
	end)

	button.MouseLeave:Connect(function()
		highlight.Visible = false
	end)
end

local function setStatus(code)
	local text = code and STATUS_TEXT[code]

	joining = code == "joining"

	if text then
		statusLabel.Text = spaced(text)
		statusLabel.Visible = true
	else
		statusLabel.Visible = false
	end
end

local function play(mapKey, jobId)
	if joining or not liveMaps[mapKey] then
		return
	end

	setStatus("joining")
	remotes.Play:FireServer(mapKey, jobId)
end

----

local function drawServers()
	local list = serversPanel.List

	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local bucket = snapshot[openMapKey]
	local servers = bucket and bucket.Servers or {}
	local now = workspace:GetServerTimeNow()

	serversPanel.Empty.Visible = #servers == 0

	for index, server in servers do
		local row = templates.ServerRow:Clone()
		local full = server.Players >= server.Max

		row.LayoutOrder = index
		row.Players.Text = string.format("%d / %d", server.Players, server.Max)
		row.Uptime.Text = formatUptime(math.max(0, now - server.StartedAt))

		if full then
			row.Players.TextTransparency = 0.5
			row.Uptime.TextTransparency = 0.5
		else
			hover(row.Button, row.HighlightBox)

			row.Button.MouseButton1Click:Connect(function()
				play(openMapKey, server.Id)
			end)
		end

		row.Parent = list
	end
end

local function openServers(map)
	openMapKey = map.Key

	serversPanel.Title.Text = titleText(map)
	mapsBin.Visible = false
	serversPanel.Visible = true

	drawServers()
end

local function closeServers()
	openMapKey = nil

	serversPanel.Visible = false
	mapsBin.Visible = true
end

----

local function cycleImages(card, images)
	local art = card.Art
	local index = 1

	art.Image = images[1] or ""

	if #images < 2 then
		return
	end

	task.spawn(function()
		while card.Parent do
			task.wait(IMAGE_CYCLE)

			index = index % #images + 1

			local out = tweenService:Create(art, FADE, { ImageTransparency = 1 })
			out:Play()
			out.Completed:Wait()

			art.Image = images[index]
			tweenService:Create(art, FADE, { ImageTransparency = 0 }):Play()
		end
	end)
end

local function drawCard(map)
	local card = cards[map.Key]
	local bucket = snapshot[map.Key]

	if liveMaps[map.Key] then
		card.Status.Text = string.format("%d online", bucket and bucket.Online or 0)
		card.Status.Visible = bucket ~= nil
		card.ComingSoon.Visible = false
		card.Servers.Visible = true
	else
		card.Status.Visible = false
		card.ComingSoon.Visible = true
		card.Servers.Visible = false
	end
end

local function makeCard(map, index)
	local card = templates.MapCard:Clone()
	card.Name = map.Key
	card.LayoutOrder = index
	card.Title.Text = titleText(map)
	card.Stats.Text = table.concat(map.Stats, "   ·   ")

	cycleImages(card, map.Images)

	card.ClickButton.MouseEnter:Connect(function()
		card.HighlightBox.Visible = liveMaps[map.Key] == true
		card.Stats.Visible = #map.Stats > 0
	end)

	card.ClickButton.MouseLeave:Connect(function()
		card.HighlightBox.Visible = false
		card.Stats.Visible = false
	end)

	card.ClickButton.MouseButton1Click:Connect(function()
		play(map.Key)
	end)

	hover(card.Servers.Button, card.Servers.HighlightBox)

	card.Servers.Button.MouseButton1Click:Connect(function()
		openServers(map)
	end)

	cards[map.Key] = card
	card.Parent = mapsBin

	drawCard(map)
end

----

local function readLiveMaps()
	table.clear(liveMaps)

	for key in (replicatedStorage:GetAttribute("LiveMaps") or ""):gmatch("[^,]+") do
		liveMaps[key] = true
	end

	for _, map in maps do
		if cards[map.Key] then
			drawCard(map)
		end
	end
end

----

for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu } do
	pcall(starterGui.SetCoreGuiEnabled, starterGui, coreGui, false)
end

readLiveMaps()
replicatedStorage:GetAttributeChangedSignal("LiveMaps"):Connect(readLiveMaps)

for index, map in maps do
	makeCard(map, index)
end

hover(serversPanel.Close, serversPanel.CloseHighlight)
serversPanel.Close.MouseButton1Click:Connect(closeServers)

remotes.Directory.OnClientEvent:Connect(function(newSnapshot)
	snapshot = newSnapshot or {}

	for _, map in maps do
		drawCard(map)
	end

	if openMapKey then
		drawServers()
	end
end)

remotes.Status.OnClientEvent:Connect(function(code)
	setStatus(code)

	if code ~= "joining" then
		task.delay(3, function()
			if not joining and statusLabel.Text == spaced(STATUS_TEXT[code] or "") then
				setStatus(nil)
			end
		end)
	end
end)
