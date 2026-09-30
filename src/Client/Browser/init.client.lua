local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local starterGui = game:GetService("StarterGui")
local tweenService = game:GetService("TweenService")
local guiService = game:GetService("GuiService")
local contextActionService = game:GetService("ContextActionService")
local soundService = game:GetService("SoundService")
local gamepadService = game:GetService("GamepadService")
local userInputService = game:GetService("UserInputService")

-- Runs from ReplicatedFirst next to the Lobby gui. Characters never load in the
-- lobby, so StarterGui is never copied into PlayerGui; we move the gui ourselves.
local playerGui = playersService.LocalPlayer:WaitForChild("PlayerGui")

-- landscape only on phones and tablets; the stage is laid out wide. Set on
-- PlayerGui because StarterGui's copy only lands with a character
playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
local gui = script.Parent:WaitForChild("Lobby")
gui.Parent = playerGui

-- ReplicatedFirst runs before the rest of the game has replicated
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local names = require(replicatedStorage.Shared.Names)
local platform = require(replicatedStorage.Shared.Platform)
local slideshow = require(script.Slideshow)
local loading = require(script.Loading)

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

-- a scrolling frame can sit in an EdgeFade CanvasGroup (see edgeFade)
local function scroller(parent, name)
	local fade = parent:FindFirstChild("EdgeFade")

	return fade and fade:FindFirstChild(name) or parent[name]
end

local cardRow = scroller(picker, "Maps")
local serverList = scroller(browser, "List")

-- optional: the list's search box and its platform-only filter chip
local searchBox = browser:FindFirstChild("Search")
local search = searchBox and searchBox:FindFirstChild("Input")
local filterChip = browser:FindFirstChild("Filter")

-- optional: without it teleports use Roblox's default screen
local loadingGui = script.Parent:FindFirstChild("LoadingGui")

if loadingGui then
	loading.Init(loadingGui, playerGui)
end

----

local STAGE = Vector2.new(1440, 810)

-- screen pixels kept clear around the stage, on top of Roblox's top bar;
-- phones (short screens) get the smaller one, they can't spare the room
local MARGIN = 24
local SMALL_MARGIN = 8
local SMALL_SCREEN = 600 -- screen height below which a screen counts as small

-- stage pixels between the picker's first and last card and the stage edge
-- when the row is wider than the stage and scrolls
local CARD_EDGE = 64

-- stage pixels a scrolling list takes to fade out at an edge with more past it
local EDGE_FADE = 36

local SLIDE = 6
local CARD_CYCLE = 8

-- a map's CardImages are cut for the card: 756x1024, full-bleed
local CARD_ART = { aspect = 756 / 1024, focus = { 1, 1 } }
local QUICK = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AMBIENT_FADE = TweenInfo.new(8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local BONE = Color3.fromRGB(229, 226, 219)
local AMBER = Color3.fromRGB(227, 166, 74)
local DIM = Color3.fromRGB(85, 85, 85)
local LOCKED_STROKE = Color3.fromRGB(124, 124, 124)
local LOCKED_TINT = Color3.fromRGB(193, 193, 193)
-- a platform a map can't run on: said plainly, not just greyed out
local BLOCKED = Color3.fromRGB(214, 92, 74)
-- tags without a colour of their own
local DULL = Color3.fromRGB(150, 147, 141)

local STATUS_TEXT = {
	joining = "joining",
	full = "server full",
	closed = "server closed",
	failed = "couldn't join",
	denied = "no access",
	password = "wrong password",
	slow = "too many tries",
	unavailable = "unavailable",
	locked = "server locked",
	banned = "banned from server",
	unsupported = "not available on your platform",
}

-- sort chip name -> mode
local SORTS = {
	Players = "players",
	Newest = "newest",
	Region = "region",
}

local here = platform:Detect()

-- the platform-only pool this client can join (console, mobile), nil on PC
local myPool = platform:PoolFor(here)

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
local poolOnly = false
local joining = false

----

-- the game's header style (its spaceOut): "Beta Map" -> "BETA MAP" with a
-- hair space (U+200A) between every character, so words split by hair,
-- space, hair. Full spaces look far too wide
local HAIR = utf8.char(0x200A)

local function spaced(text)
	local characters = {}

	for _, code in utf8.codes(text:upper()) do
		table.insert(characters, utf8.char(code))
	end

	return table.concat(characters, HAIR)
end

local function titleText(map)
	return spaced(map.Name)
end

-- text boxes hold the label and its drop-shadow copy; keep them in step
local function setText(box, text)
	box.Text.Text = text
	box.Shadow.Text = (text:gsub("<[^>]+>", ""))
end

-- "1 server", "3 servers"
local function count(amount, noun)
	return string.format("%d %s%s", amount, noun, amount == 1 and "" or "s")
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

----

-- ReplicatedStorage.Sounds is set up in the place (not Rojo): AmbientLoop and
-- the game's Interface sounds. Anything missing just stays silent
local sounds = replicatedStorage:FindFirstChild("Sounds")
local interfaceSounds = sounds and sounds:FindFirstChild("Interface")

-- one-shot interface sound, like the game's Interface:PlaySound
local function playSound(name)
	local source = interfaceSounds and interfaceSounds:FindFirstChild(name)

	if not source then
		return
	end

	local sound = source:Clone()
	sound.Parent = soundService
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

-- a background drone so the lobby isn't silent; fades up to the volume it's
-- set to in the place
local function startAmbient()
	local source = sounds and sounds:FindFirstChild("AmbientLoop")

	if not source then
		return
	end

	local ambient = source:Clone()
	local volume = ambient.Volume

	ambient.Volume = 0
	ambient.Looped = true
	ambient.Parent = soundService
	ambient:Play()

	tweenService:Create(ambient, AMBIENT_FADE, { Volume = volume }):Play()
end

-- the game's button frames: highlight on hover, click sound, ignore presses
-- while disabled. Pass sound = false when the action plays its own
local function bindButton(frame, callback, sound)
	frame.Button.MouseEnter:Connect(function()
		frame.HighlightBox.Visible = not frame:GetAttribute("Disabled")
	end)

	frame.Button.MouseLeave:Connect(function()
		frame.HighlightBox.Visible = false
	end)

	frame.Button.Activated:Connect(function()
		if not frame:GetAttribute("Disabled") then
			if sound ~= false then
				playSound("Click")
			end

			callback()
		end
	end)
end

-- [button frame] = { stroke, tint, label }: its colours as built in the place
local authored = {}

-- greys a button out like the game's Locked/Full buttons, and back to the
-- colours it has in the place
local function setEnabled(frame, enabled)
	local colors = authored[frame]

	if not colors then
		colors = { frame.Stroke.Color, frame.Backdrop.ImageColor3, frame.Label.Text.TextColor3 }
		authored[frame] = colors
	end

	frame:SetAttribute("Disabled", not enabled)
	frame.Stroke.Color = enabled and colors[1] or LOCKED_STROKE
	frame.Backdrop.ImageColor3 = enabled and colors[2] or LOCKED_TINT
	frame.Label.Text.TextColor3 = enabled and colors[3] or DIM
	frame.Button.Selectable = enabled

	if not enabled then
		frame.HighlightBox.Visible = false
	end
end

local function setStatus(code)
	local text = code and STATUS_TEXT[code]

	-- "teleporting" is the server confirming the teleport is under way
	joining = code == "joining" or code == "teleporting"
	statusBox.Visible = text ~= nil

	if text then
		setText(statusBox, spaced(text))
	end
end

local function drawChips(bin, map)
	clear(bin)

	for index, entry in platform.List do
		local support = platform:Support(map, entry.Key)
		local color = support == "blocked" and BLOCKED or support == "warn" and AMBER or BONE
		local chip = templates.PlatformChip:Clone()

		chip.Name = entry.Key
		chip.LayoutOrder = index
		chip.Stroke.Color = color
		-- only the chip for the platform you're on gets an outline (both PS4
		-- and PS5 on PlayStation, which can't tell them apart)
		chip.Stroke.Transparency = platform:Covers(here, entry.Key) and 0.3 or 1

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

-- "#D9A21B" -> Color3, or `fallback` if it isn't one
local function hexColor(hex, fallback)
	local worked, color = pcall(Color3.fromHex, hex or "")

	return worked and color or fallback
end

local function drawTags(bin, map)
	clear(bin)

	local template = templates:FindFirstChild("Tag")

	for index, tag in template and map.Tags or {} do
		local color = hexColor(tag[2], DULL)
		local chip = template:Clone()

		chip.LayoutOrder = index
		chip.Label.Text = tag[1]
		chip.Label.TextColor3 = color
		chip.Stroke.Color = color
		chip.Visible = true
		chip.Parent = bin
	end

	bin.Visible = #(map.Tags or {}) > 0
end

-- true if this client's platform can't play the map at all
local function blockedHere(map)
	return platform:Support(map, here) == "blocked"
end

-- the platform-only pool this client can quick-join on the map, if any
local function poolHere(map)
	return myPool and table.find(map.Pools or {}, myPool) and myPool or nil
end

----

-- jobId: a server from the list; pool: quick-join a platform-only pool
-- instead of the Any servers
local function play(mapKey, jobId, pool)
	local map = mapsByKey[mapKey]

	if joining or not map or not liveMaps[mapKey] or blockedHere(map) then
		return
	end

	-- only the map view has the password field
	local password = nil

	if map.Password then
		if openMap ~= map then
			return
		end

		password = info.Buttons.Password.Input.Text
	end

	setStatus("joining")
	loading.Prepare(map.Title)
	remotes.Play:FireServer(mapKey, jobId, password, pool, here)
end

----

local function sortServers(servers)
	table.sort(servers, function(a, b)
		local aFull = a.Players >= a.Max
		local bFull = b.Players >= b.Max

		if aFull ~= bFull then
			return bFull
		end

		-- public servers first, then VIP
		if a.Kind ~= b.Kind then
			return a.Kind == "public"
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

-- a search matches the server's name, id, region or VIP host
local function matches(server, query)
	local fields = {
		names:ForJob(server.Id),
		server.Id,
		server.Region or "",
		server.Host or "",
	}

	for _, field in fields do
		if field:lower():find(query, 1, true) then
			return true
		end
	end

	return false
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

		playSound("Click")

		if selectedId == jobId then
			play(openMap.Key, jobId)
		else
			selectedId = jobId
			drawServers()
		end
	end)

	row.Parent = serverList

	return row
end

function drawServers()
	if not openMap then
		return
	end

	local bucket = snapshot[openMap.Key]
	local pool = poolHere(openMap)
	local query = search and search.Text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	local servers = {}
	local now = workspace:GetServerTimeNow()

	-- PC only sees the Any servers; everyone else also sees their own pool's,
	-- or only those with the filter on
	local sources = { pool and poolOnly and {} or (bucket and bucket.Servers or {}) }

	if pool and bucket and bucket.Pools then
		table.insert(sources, bucket.Pools[pool] or {})
	end

	for _, source in sources do
		for _, server in source do
			if query == "" or matches(server, query) then
				table.insert(servers, server)
			end
		end
	end
	local picked = nil
	local seen = {}
	local newest = 0

	for _, server in servers do
		newest = math.max(newest, server.Version or 0)
	end

	-- "v1234" (the game's PlaceVersion), amber on a server running an older
	-- build than the newest one up for this map; nil when the beacon didn't say
	local function version(server)
		if not server.Version then
			return nil
		end

		local text = "v" .. server.Version

		if server.Version < newest then
			-- full opacity: the id line itself is faint
			return string.format('<font color="#%s" transparency="0">%s</font>', AMBER:ToHex(), text)
		end

		return text
	end

	local function idLine(server)
		local line = server.Kind ~= "public" and ("VIP  ·  " .. (server.Host or "…")) or names:ShortId(server.Id)

		if server.Pool then
			line = platform.Pools[server.Pool].Long .. " ONLY  ·  " .. line
		end

		local build = version(server)

		return build and (line .. "  ·  " .. build) or line
	end

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
		setText(row.Id, idLine(server))
		setText(row.Region, server.Region or "—")
		setText(row.Uptime, formatUptime(math.max(0, now - server.StartedAt)))
		setText(row.Players, full and "FULL" or server.Locked and "LOCKED" or string.format("%d / %d", server.Players, server.Max))

		for _, cell in { row.Server, row.Region, row.Uptime, row.Players } do
			cell.Text.TextColor3 = ink
		end

		-- the host and their co-hosts can still get into a locked server, so it
		-- stays selectable; the lobby server decides
		if server.Locked and not full then
			row.Players.Text.TextColor3 = AMBER
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
		local meta = {
			idLine(picked),
			picked.Region or "—",
			"up " .. formatUptime(math.max(0, now - picked.StartedAt)),
			string.format("%d / %d", picked.Players, picked.Max),
		}

		for _, tag in picked.Tags or {} do
			table.insert(meta, tag)
		end

		setText(footer.Meta, table.concat(meta, "  ·  "))
	else
		setText(footer.ServerName, "")
		setText(footer.Meta, "")
	end

	footer.Join.Visible = not blockedHere(openMap)
	setEnabled(footer.Join, picked ~= nil)

	setText(info.Counts.Online, string.format("%d online", bucket and bucket.Online or 0))
	setText(info.Counts.Servers, count(#servers, "server"))
end

local function drawChip(chip, on)
	chip.Label.TextTransparency = on and 0 or 0.5
	chip.Stroke.Transparency = on and 0.35 or 0.8
	chip.BackgroundTransparency = on and 0 or 0.2
end

local function drawSorts()
	for chipName, mode in SORTS do
		drawChip(browser.Sorts[chipName], mode == sortMode)
	end

	-- the platform filter only means something with a pool to filter to
	if filterChip then
		local pool = openMap and poolHere(openMap)

		filterChip.Visible = pool ~= nil
		filterChip.Label.Text = pool and (platform.Pools[pool].Long .. " ONLY") or ""
		drawChip(filterChip, pool ~= nil and poolOnly)
	end
end

----

local preview = nil

-- lights the picker bar for the showing image
local function drawDots(index)
	for _, dot in info.Preview.Clip.Dots:GetChildren() do
		if dot:IsA("GuiButton") then
			dot.Bar.BackgroundTransparency = dot.LayoutOrder == index and 0 or 0.6
		end
	end
end

local function startSlides(images)
	local clip = info.Preview.Clip

	if not preview then
		-- the slideshow draws into viewports; image labels from older builds of the UI go unused
		for _, name in { "ImageA", "ImageB" } do
			local old = clip:FindFirstChild(name)

			if old then
				old.Visible = false
			end
		end

		preview = slideshow.new(clip, { interval = SLIDE, zIndex = 1, onChange = drawDots })
	end

	-- the picker: one bar per image, only worth showing with more than one
	clear(clip.Dots)
	clip.Shade.Visible = #images > 1

	if #images > 1 then
		for index = 1, #images do
			local dot = templates.PreviewDot:Clone()
			dot.LayoutOrder = index
			dot.Visible = true

			dot.MouseEnter:Connect(function()
				if preview.index ~= index then
					dot.Bar.BackgroundTransparency = 0.3
				end
			end)

			dot.MouseLeave:Connect(function()
				drawDots(preview.index)
			end)

			dot.Activated:Connect(function()
				if preview.index ~= index then
					playSound("Click")
					preview:Show(index)
				end
			end)

			dot.Parent = clip.Dots
		end
	end

	preview:SetImages(images)
end

local function drawNotice(map)
	-- `worst` is set when a PlayStation client can't be told apart and only
	-- one generation is supported: warn about that one, don't block
	local support, long, worst = platform:Support(map, here)

	info.Notice.Visible = support ~= "ok"

	if worst == "blocked" then
		setText(info.Notice, spaced("not available on " .. long))
		info.Notice.Text.TextColor3 = AMBER
	elseif support == "warn" then
		setText(info.Notice, spaced("limited support on " .. long))
		info.Notice.Text.TextColor3 = AMBER
	elseif support == "blocked" then
		setText(info.Notice, spaced("not available on " .. long))
		info.Notice.Text.TextColor3 = BLOCKED
	end
end

-- Play joins an Any server. With a pool for this platform, a second button
-- joins a platform-only one: "PLAY ANY" and "PLAY CONSOLE". A platform the
-- map can't run on gets neither
local function drawPlayButtons(map)
	local buttons = info.Buttons
	local poolButton = buttons:FindFirstChild("PlayPool")
	local blocked = blockedHere(map)
	local pool = not blocked and poolButton ~= nil and poolHere(map) or nil

	buttons.Play.Visible = not blocked
	buttons.Password.Visible = map.Password == true and not blocked
	setText(buttons.Play.Label, pool and "PLAY ANY" or "PLAY")

	if poolButton then
		poolButton.Visible = pool ~= nil

		if pool then
			setText(poolButton.Label, "PLAY " .. platform.Pools[pool].Long)
		end
	end
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
	drawPlayButtons(map)

	info.Buttons.Password.Input.Text = ""

	if map.Backdrop then
		bleed.Image = map.Backdrop
		tweenService:Create(bleed, QUICK, { ImageTransparency = 0.35 }):Play()
	else
		bleed.ImageTransparency = 1
	end

	startSlides(map.Images or {})
	drawSorts()
	drawServers()

	picker.Visible = false
	mapView.Visible = true

	playSound("MapOpen")
end

local function closeMapView()
	if not openMap then
		return
	end

	openMap = nil

	if preview then
		preview:Stop()
	end

	tweenService:Create(bleed, QUICK, { ImageTransparency = 1 }):Play()

	mapView.Visible = false
	picker.Visible = true

	playSound("MapClose")
end

----

-- cards change images at spread-out times: golden-ratio steps through the
-- cycle stay apart however many cards there are
local function cardDelay(index)
	return ((index - 1) * 0.618 % 1) * CARD_CYCLE
end

local function drawCard(map)
	local card = cards[map.Key]
	local bucket = snapshot[map.Key]
	local live = liveMaps[map.Key] == true

	card.ComingSoon.Visible = not live
	card.Online.Visible = live and bucket ~= nil
	card.Button.Selectable = live

	-- one tap into a game: this platform's own servers where it has them, Any
	-- otherwise. Password maps open instead, since the field is in the map view
	local quick = card:FindFirstChild("Play")

	if quick then
		quick.Visible = live and not blockedHere(map) and not map.Password
	end

	-- every server the map has up, platform-only ones included, like Online
	if bucket then
		local servers = #bucket.Servers

		for _, pool in bucket.Pools or {} do
			servers += #pool
		end

		setText(card.Online, string.format("%d online  ·  %s", bucket.Online, count(servers, "server")))
	end
end

local function makeCard(map, index)
	local card = templates.MapCard:Clone()
	card.Name = map.Key
	card.LayoutOrder = index
	card.Visible = true

	setText(card.Title, titleText(map))
	drawChips(card.Platforms, map)

	if card:FindFirstChild("Tags") then
		drawTags(card.Tags, map)
	end

	local quick = card:FindFirstChild("Play")

	-- the card highlights on hover, except while the pointer is on its Play
	-- button, which has its own highlight. Enter/leave fire by position even
	-- under another object, so the card can't tell on its own
	local overCard, overQuick = false, false

	-- optional: a glow round the card that goes with its highlight box
	local glow = card:FindFirstChild("HighlightShadow")

	local function drawHighlight()
		local on = overCard and not overQuick and liveMaps[map.Key] == true

		card.HighlightBox.Visible = on

		if glow then
			glow.Enabled = on
		end
	end

	drawHighlight()

	if quick then
		bindButton(quick, function()
			local current = mapsByKey[map.Key]

			if current then
				play(current.Key, nil, poolHere(current))
			end
		end)

		quick.Button.MouseEnter:Connect(function()
			overQuick = true
			drawHighlight()
		end)

		quick.Button.MouseLeave:Connect(function()
			overQuick = false
			drawHighlight()
		end)
	end

	local art = card.Clip:FindFirstChild("Art")

	if art then
		art.Visible = false
	end

	-- the card's own art if it has some, else the preview's cropped to the card
	local cardArt = map.CardImages and #map.CardImages > 0

	local show = slideshow.new(card.Clip, {
		interval = CARD_CYCLE,
		zIndex = 0, -- under the card's Fade
		delay = cardDelay(index),
		seed = index * 7919,
		aspect = cardArt and CARD_ART.aspect or nil,
		focus = cardArt and CARD_ART.focus or nil,
	})

	show:SetImages(cardArt and map.CardImages or map.Images or {})
	card.Destroying:Connect(function()
		show:Destroy()
	end)

	card.Button.MouseEnter:Connect(function()
		overCard = true
		drawHighlight()
	end)

	card.Button.MouseLeave:Connect(function()
		overCard = false
		drawHighlight()
	end)

	card.Button.Activated:Connect(function()
		openMapView(map)
	end)

	cards[map.Key] = card
	card.Parent = cardRow

	drawCard(map)
end

-- keeps cards in step with the server's list; maps can appear, vanish or
-- change (a role change, a test map added)
local function syncMaps(list)
	local seen = {}
	local art = {}

	-- fetch every map's art now, so opening a map never waits on its images
	for _, map in list do
		for _, image in map.Images or {} do
			table.insert(art, image)
		end

		for _, image in map.CardImages or {} do
			table.insert(art, image)
		end
	end

	slideshow.Preload(art)

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
			drawPlayButtons(openMap)
			drawSorts()
		else
			closeMapView()
		end
	end
end

----

-- the device's safe area (notches, rounded corners), read off an empty
-- ScreenGui inset to it; the lobby's own gui ignores it for the background
local safeArea = Instance.new("ScreenGui")
safeArea.Name = "LobbySafeArea"
safeArea.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
safeArea.Parent = playerGui

-- the corner Roblox's own top bar buttons take: { right edge, bottom edge }.
-- TopbarInset is the free part of the bar, starting where the buttons end
local function topBarCorner()
	local found, inset = pcall(function()
		return guiService.TopbarInset
	end)

	if found and inset and inset.Max.Y > 0 then
		return Vector2.new(inset.Min.X, inset.Max.Y), inset.Max.X
	end

	return Vector2.new(gui.AbsoluteSize.X, guiService:GetGuiInset().Y), gui.AbsoluteSize.X
end

-- the gui covers the whole screen so the background runs under the top bar.
-- The stage (laid out at 1440x810) scales to the biggest fit that stays clear
-- of Roblox's buttons: either below the whole bar, or beside the buttons at
-- full height. Wide, short phone screens do much better beside
local function fit()
	local size = gui.AbsoluteSize
	-- AbsolutePosition is measured from below the top bar, not the screen's
	-- corner, so bring the safe area into the gui's own space, where the
	-- stage's Position and TopbarInset both live
	local safeMin = safeArea.AbsolutePosition - gui.AbsolutePosition
	local safeMax = safeMin + safeArea.AbsoluteSize

	if safeArea.AbsoluteSize.X <= 0 or safeArea.AbsoluteSize.Y <= 0 then
		safeMin, safeMax = Vector2.zero, size
	end

	local corner, barRight = topBarCorner()
	local margin = size.Y < SMALL_SCREEN and SMALL_MARGIN or MARGIN

	local areas = {
		-- below the bar
		{ Vector2.new(safeMin.X, math.max(safeMin.Y, corner.Y)), safeMax },
		-- beside the buttons, between them and anything Roblox puts on the right
		{ Vector2.new(math.max(safeMin.X, corner.X), safeMin.Y), Vector2.new(math.min(safeMax.X, barRight), safeMax.Y) },
	}

	local bestScale, bestCentre = 0, size / 2

	for _, area in areas do
		local low = area[1] + Vector2.one * margin
		local high = area[2] - Vector2.one * margin
		local room = high - low

		if room.X > 0 and room.Y > 0 then
			local scale = math.min(room.X / STAGE.X, room.Y / STAGE.Y)

			if scale > bestScale then
				bestScale, bestCentre = scale, (low + high) / 2
			end
		end
	end

	if bestScale > 0 then
		stage.Scale.Scale = bestScale
		stage.Position = UDim2.fromOffset(math.floor(bestCentre.X), math.floor(bestCentre.Y))
	end
end

for _, coreGui in { Enum.CoreGuiType.Backpack, Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.EmotesMenu } do
	pcall(starterGui.SetCoreGuiEnabled, starterGui, coreGui, false)
end

-- the picker row: centred while the cards fit, otherwise starting at the
-- edge and scrolling. A centred UIListLayout in a scrolling frame pushes the
-- first cards off the left edge, out of reach, so the padding centres it
local function centreCards()
	local row = cardRow
	local layout = row:FindFirstChildOfClass("UIListLayout")
	local padding = row:FindFirstChildOfClass("UIPadding")
	local scale = stage.Scale.Scale

	if not layout or not padding or scale <= 0 then
		return
	end

	local content = layout.AbsoluteContentSize.X / scale
	local width = row.AbsoluteSize.X / scale
	local side = math.max(CARD_EDGE, math.floor((width - content) / 2))

	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	padding.PaddingLeft = UDim.new(0, side)
	padding.PaddingRight = UDim.new(0, side)
end

fit()
centreCards()
startAmbient()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
gui:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)
cardRow:FindFirstChildOfClass("UIListLayout"):GetPropertyChangedSignal("AbsoluteContentSize"):Connect(centreCards)
cardRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(centreCards)

-- the game's trick: a scrolling frame in a CanvasGroup whose UIGradient fades
-- its edges, so items scroll into the background instead of being cut off.
-- An edge only fades once there's more to scroll that way
local function edgeFade(list)
	local group = list.Parent
	local gradient = group:IsA("CanvasGroup") and group:FindFirstChildOfClass("UIGradient")

	if not gradient then
		return
	end

	local vertical = list.ScrollingDirection == Enum.ScrollingDirection.Y
	gradient.Rotation = vertical and 90 or 0

	local function update()
		local window = list.AbsoluteWindowSize
		local canvas = list.AbsoluteCanvasSize
		local length = vertical and window.Y or window.X
		local fade = EDGE_FADE * stage.Scale.Scale

		if length <= 0 or fade <= 0 then
			return
		end

		local before = vertical and list.CanvasPosition.Y or list.CanvasPosition.X
		local after = (vertical and canvas.Y or canvas.X) - length - before
		local width = math.min(fade / length, 0.25)

		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(before / fade, 0, 1)),
			NumberSequenceKeypoint.new(width, 0),
			NumberSequenceKeypoint.new(1 - width, 0),
			NumberSequenceKeypoint.new(1, math.clamp(after / fade, 0, 1)),
		})
	end

	for _, property in { "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" } do
		list:GetPropertyChangedSignal(property):Connect(update)
	end

	update()
end

edgeFade(cardRow)
edgeFade(serverList)
safeArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
safeArea:GetPropertyChangedSignal("AbsolutePosition"):Connect(fit)
pcall(function()
	guiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)
end)

-- Controllers use Roblox's virtual cursor (StarterGui.VirtualCursorMode =
-- Enabled in the place, like the game; scripts can't set it), which hovers
-- and clicks like a mouse. This ring only shows if someone uses classic
-- selection anyway
local selection = templates.Selection:Clone()
selection.Visible = true
playerGui.SelectionImageObject = selection

-- the lobby is all buttons, so a gamepad always drives the cursor: it's
-- turned on whenever a pad is in use (or on console) and off, including
-- after Select toggles it away, which confused players. Left alone while
-- Roblox's own menu is open. The game's Input library does the same
local function keepCursor()
	if guiService.MenuIsOpen or gamepadService.GamepadCursorEnabled then
		return
	end

	local padInUse = userInputService:GetLastInputType().Name:find("^Gamepad") ~= nil

	if padInUse or guiService:IsTenFootInterface() then
		pcall(gamepadService.EnableGamepadCursor, gamepadService, nil)
	end
end

userInputService.LastInputTypeChanged:Connect(keepCursor)
guiService.MenuClosed:Connect(keepCursor)

gamepadService:GetPropertyChangedSignal("GamepadCursorEnabled"):Connect(function()
	task.defer(keepCursor)
end)

keepCursor()

-- closing plays MapClose itself (gamepad B closes too)
bindButton(info.Buttons.Back, closeMapView, false)

bindButton(info.Buttons.Play, function()
	if openMap then
		play(openMap.Key)
	end
end)

if info.Buttons:FindFirstChild("PlayPool") then
	bindButton(info.Buttons.PlayPool, function()
		if openMap then
			play(openMap.Key, nil, poolHere(openMap))
		end
	end)
end

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
		playSound("Click")
		sortMode = mode
		drawSorts()
		drawServers()
	end)
end

if filterChip then
	filterChip.Button.MouseEnter:Connect(function()
		filterChip.HighlightBox.Visible = true
	end)

	filterChip.Button.MouseLeave:Connect(function()
		filterChip.HighlightBox.Visible = false
	end)

	filterChip.Button.Activated:Connect(function()
		playSound("Click")
		poolOnly = not poolOnly
		drawSorts()
		drawServers()
	end)
end

if search then
	search:GetPropertyChangedSignal("Text"):Connect(function()
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

remotes.Directory.OnClientEvent:Connect(function(payload)
	snapshot = payload and payload.Servers or {}
	syncMaps(payload and payload.Maps or {})
	drawServers()
end)

-- a paid VIP server sends everyone on to the host's own server, so the
-- browser stays hidden and only the status shows
local function forwarding()
	return replicatedStorage:GetAttribute("VipForward") == true
end

local function drawForwarding()
	local on = forwarding()

	picker.Visible = not on and openMap == nil
	mapView.Visible = not on and openMap ~= nil

	if on then
		setStatus("joining")
	elseif statusBox.Visible and not joining then
		setStatus(nil)
	end
end

drawForwarding()
replicatedStorage:GetAttributeChangedSignal("VipForward"):Connect(drawForwarding)

remotes.Status.OnClientEvent:Connect(function(code, title)
	setStatus(code)

	if code == "teleporting" then
		loading.Show(title)
	elseif code == "joining" then
		-- VIP forwards teleport without a Play, so they name the map here
		if title then
			loading.Prepare(title)
		end
	else
		loading.Hide()
	end

	-- while forwarding, a failure stays up until the server retries
	if code ~= "joining" and code ~= "teleporting" and not forwarding() then
		task.delay(3, function()
			if not joining and statusBox.Text.Text == spaced(STATUS_TEXT[code] or "") then
				setStatus(nil)
			end
		end)
	end
end)
