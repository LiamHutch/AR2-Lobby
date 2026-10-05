-- The game's own loading screen (ReplicatedFirst.LoadingGui, copied from the
-- game's GuiMain.LoadingGui) used as the teleport screen, so the trip into a
-- game server looks like one continuous load:
--
--   lobby -> fade to the loading screen -> Roblox shows it during the
--   teleport (SetTeleportGui) -> the game adopts it on arrival
--   (GetArrivingTeleportGui) and swaps in its identical own
--
-- Nothing inside a teleport gui runs, so it's set up here before it goes.
--
-- The other way round, the game's Return To Lobby sends its own copy of the
-- screen with the teleport; Adopt keeps it up over the lobby until Settle
-- fades it out once the lobby has drawn.

local teleportService = game:GetService("TeleportService")
local tweenService = game:GetService("TweenService")

local library = {}

----

local FADE = TweenInfo.new(0.5, Enum.EasingStyle.Sine)

----

local template = nil
local playerGui = nil

-- the copy Roblox carries across the teleport, and the one faded in here
local carried = nil
local shown = nil
local showToken = 0

local function setText(screen, text)
	local label = screen.LoadingGui.Logo.Label

	label.Label.Text = text
	label.LabelBackdrop.Text = text
end

local function make(text)
	local screen = template:Clone()

	screen.ResetOnSpawn = false
	-- fully up: the game fades these in on a cold start, but here it's mid-load
	screen.LoadingGui.Logo.ImageLabel.ImageTransparency = 0
	screen.LoadingGui["Loading Shade"].BackgroundTransparency = 1
	setText(screen, text)

	return screen
end

local function label(title)
	return title and ("joining " .. title:lower()) or "joining"
end

----

-- the screen a game teleport arrived with, kept up until Settle; nil for a
-- cold start
local arrived = nil

function library.Adopt(gui, above)
	local screen = teleportService:GetArrivingTeleportGui()

	if screen then
		screen.DisplayOrder = above.DisplayOrder + 1
		screen.Parent = gui
		arrived = screen
	end

	return screen ~= nil
end

function library.Settle()
	local screen = arrived
	arrived = nil

	if not screen then
		return
	end

	local frame = screen:FindFirstChild("LoadingGui")

	if not frame then
		screen:Destroy()

		return
	end

	local group = Instance.new("CanvasGroup")
	group.Name = "Fade"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.Parent = screen
	frame.Parent = group

	local tween = tweenService:Create(group, FADE, { GroupTransparency = 1 })

	tween.Completed:Connect(function()
		screen:Destroy()
	end)

	tween:Play()
end

function library.Init(source, gui)
	template = source
	playerGui = gui

	-- a template in ReplicatedFirst never renders on its own
	template.Enabled = false

	library.Prepare(nil)
end

-- registers the screen Roblox shows during the next teleport. Called before
-- asking the server to teleport, since the teleport can start before any
-- reply gets back
function library.Prepare(title)
	if not template then
		return
	end

	if carried then
		carried:Destroy()
	end

	carried = make(label(title))
	carried.Enabled = true
	teleportService:SetTeleportGui(carried)
end

-- fades the loading screen in over the lobby once the teleport is under way
function library.Show(title)
	if not template or shown then
		return
	end

	showToken += 1

	local token = showToken
	local screen = make(label(title))
	local frame = screen.LoadingGui

	-- a CanvasGroup fades the whole screen as one, then it goes back to a
	-- plain Frame so it renders at full resolution
	local group = Instance.new("CanvasGroup")
	group.Name = "Fade"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = screen

	frame.Parent = group
	screen.Enabled = true
	screen.Parent = playerGui
	shown = screen

	local tween = tweenService:Create(group, FADE, { GroupTransparency = 0 })

	tween.Completed:Connect(function()
		if token == showToken then
			frame.Parent = screen
			group:Destroy()
		end
	end)

	tween:Play()
end

-- the teleport failed; back to the lobby
function library.Hide()
	showToken += 1

	if shown then
		shown:Destroy()
		shown = nil
	end
end

return library
