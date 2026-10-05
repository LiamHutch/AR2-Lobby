-- The private server pages: Tourney and Free Roam tiles in the picker, and
-- the mode view they open (Stage.ModeView): a list of the sessions this
-- player may see, the roster of a tourney lobby, its match settings, and a
-- free roam server's settings. Talks to Sessions.lua over Remotes.Private
-- (its header lists the messages). Shared/Private.lua describes the modes.
--
-- init.client.lua makes this with the helpers it already has (text boxes,
-- buttons, sounds, the edge fades) and keeps the picker/map view switching;
-- this only owns ModeView and the mode cards.

local playersService = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local socialService = game:GetService("SocialService")
local tweenService = game:GetService("TweenService")

local private = require(replicatedStorage.Shared.Private)

local localPlayer = playersService.LocalPlayer

return function(context)
	local gui = context.gui
	local stage = context.stage
	local templates = context.templates
	local cardRow = context.cardRow
	local remote = context.remotes.Private
	local slideshow = context.slideshow
	local loading = context.loading
	local here = context.here

	local spaced = context.spaced
	local setText = context.setText
	local clear = context.clear
	local bindButton = context.bindButton
	local setEnabled = context.setEnabled
	local playSound = context.playSound
	local drawChips = context.drawChips
	local drawTags = context.drawTags
	local hexColor = context.hexColor
	local count = context.count
	local setStatus = context.setStatus
	local isJoining = context.isJoining

	local view = stage.ModeView
	local info = view.Info
	local lobbies = view.Lobbies
	local roster = view.Roster
	local config = view.Config
	local server = view.Server
	local dropdown = stage.Dropdown
	local shield = stage.DropdownShield

	local lobbyList = lobbies.EdgeFade.List
	local rosterList = roster.EdgeFade.List
	local configList = config.EdgeFade.List
	local serverList = server.EdgeFade.List
	local footer = lobbies.Footer

	local library = {}

	----

	local BONE = Color3.fromRGB(229, 226, 219)
	local AMBER = Color3.fromRGB(227, 166, 74)
	local DIM = Color3.fromRGB(85, 85, 85)
	local GOLD = Color3.fromRGB(202, 188, 131)
	local QUICK = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local SLIDE = 6

	-- the ordinal under a picked map tile
	local ORDINALS = { "1ST", "2ND", "3RD" }

	-- the hub tile's pages borrow ModeView; they have no sessions, their rows
	-- come from elsewhere (Client = true)
	local CLIENT_MODES = {
		Friends = {
			Key = "Friends",
			Client = true,
			Name = "Friends",
			Blurb = "Friends playing AR2 right now and where they are. Join lands you in their server, or in their lobby if they're setting up a match.",
			Images = private.ByKey.Freeroam.Images,
			Heading = "Online",
			Empty = "No friends in AR2",
			Primary = "INVITE A FRIEND",
			Columns = { "Friend", "Where", "Players" },
		},
		-- blank screens with a back button until the pages exist
		News = { Key = "News", Client = true, Static = true, Name = "Coming Soon" },
		Events = { Key = "Events", Client = true, Static = true, Name = "Coming Soon" },
	}

	-- seconds between friend list refreshes while the page is open
	local FRIENDS_REFRESH = 30

	-- a friend whose JOIN sent us here; opened once their lobby shows up
	local pendingFollow = nil

	local openMode = nil
	-- "list" | "roster" | "config" | "server"
	local panel = "list"

	-- the list: rows the server sent, my own row, the selected one
	local rows = {}
	local own = nil
	local selectedHostId = nil
	local scope = "all" -- "all" | "friends"
	local openOnly = false
	local rejoin = nil

	-- the session on screen
	local viewedHostId = nil
	local state = nil
	local countdownEnds = nil

	-- [key] = { Online, Sessions } for the tiles
	local counts = {}
	local cards = {}
	local placesLive = {}

	local preview = nil
	local previewImages = nil
	local dropdownOpen = nil

	----

	local function plural(amount, singular, many)
		return string.format("%d %s", amount, amount == 1 and singular or many)
	end

	local function ordinal(index)
		return ORDINALS[index] or (index .. "TH")
	end

	local function teamColor(index)
		return private.TeamColors[index] or private.TeamColors[1]
	end

	local function mine()
		return state ~= nil and state.Mine == true
	end

	-- a session row's name for the footer: "LMH_HUTCH'S LOBBY"
	local function possessive(name, noun)
		return string.format("%s'S %s", name:upper(), noun:upper())
	end

	local function act(action, ...)
		if openMode and viewedHostId then
			remote:FireServer("act", openMode.Key, viewedHostId, action, ...)
		end
	end

	local function chipOn(chip, on)
		chip.Label.TextTransparency = on and 0 or 0.5
		chip.Stroke.Transparency = on and 0.35 or 0.8
		chip.BackgroundTransparency = on and 0 or 0.2
	end

	-- hover and click for a chip (sortChip style): HighlightBox on hover
	local function bindChip(chip, callback)
		chip.Button.MouseEnter:Connect(function()
			chip.HighlightBox.Visible = not chip:GetAttribute("Disabled")
		end)

		chip.Button.MouseLeave:Connect(function()
			chip.HighlightBox.Visible = false
		end)

		chip.Button.Activated:Connect(function()
			if not chip:GetAttribute("Disabled") then
				playSound("Click")
				callback()
			end
		end)
	end

	----

	-- the preview slideshow, with the picker dots like the map view's
	local function drawDots(index)
		for _, dot in info.Preview.Clip.Dots:GetChildren() do
			if dot:IsA("GuiButton") then
				dot.Bar.BackgroundTransparency = dot.LayoutOrder == index and 0 or 0.6
			end
		end
	end

	local function showImages(images)
		local clip = info.Preview.Clip

		if not preview then
			preview = slideshow.new(clip, { interval = SLIDE, zIndex = 1, onChange = drawDots })
		end

		-- the same set keeps playing; a new one restarts the show
		if previewImages and #previewImages == #images then
			local same = true

			for index, image in images do
				if previewImages[index] ~= image then
					same = false

					break
				end
			end

			if same then
				return
			end
		end

		previewImages = table.clone(images)

		clear(clip.Dots)
		clip.Shade.Visible = #images > 1

		for index = 1, #images > 1 and #images or 0 do
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

		preview:SetImages(images)
	end

	-- a tourney lobby previews its picked maps; everything else the mode's art
	local function previewFor()
		if openMode.Key == "Tourney" and state and panel ~= "list" then
			local images = {}

			if state.Settings.mapOrder ~= "shuffleAll" then
				for _, name in state.Maps do
					local map = openMode.MapsByName[name]

					if map then
						table.insert(images, map.BigImage)
					end
				end
			end

			if #images > 0 then
				return images
			end
		end

		return openMode.Images or {}
	end

	----

	-- the info column changes with what's on the right
	local function drawInfo()
		local mode = openMode

		setText(info.Title, spaced(mode.Name))
		setText(info.Blurb, mode.Blurb or "")
		info.Platforms.Visible = not mode.Client
		drawChips(info.Platforms, mode)

		-- a blank page: the title and the back button, nothing else
		for _, name in { "Counts", "Blurb", "Preview" } do
			info[name].Visible = not mode.Static
		end

		view.Panel.Visible = not mode.Static

		if mode.Static then
			info.Visibility.Visible = false
			info.Buttons.Primary.Visible = false
			info.Buttons.Toggle.Visible = false

			if preview then
				preview:Stop()
				previewImages = nil
			end

			return
		end

		if mode.Client then
			if mode.Key == "Friends" then
				local inGame, online = 0, #rows

				for _, row in rows do
					if row.Joinable then
						inGame += 1
					end
				end

				setText(info.Counts.Online, string.format("%d in AR2", inGame))
				setText(info.Counts.Servers, count(online, "friend") .. " online")
			else
				setText(info.Counts.Online, "")
				setText(info.Counts.Servers, "")
			end

			info.Visibility.Visible = false
		elseif panel == "list" or not state then
			local tally = counts[mode.Key] or {}
			setText(info.Counts.Online, string.format(mode.Key == "Tourney" and "%d queued" or "%d online", tally.Online or 0))
			setText(info.Counts.Servers, mode.Key == "Tourney" and plural(tally.Sessions or 0, "lobby", "lobbies") or count(tally.Sessions or 0, "server"))
			info.Visibility.Visible = false
		else
			local noun = mode.Key == "Tourney" and "lobby" or "server"

			setText(info.Counts.Online, state.Mine and ("Your " .. noun) or (state.Host .. "'s " .. noun))

			if mode.Key == "Tourney" then
				local extra = state.Visibility ~= "public" and ("  ·  " .. private.VisibilityLabels[state.Visibility]:lower()) or ""
				setText(info.Counts.Servers, string.format("%d in lobby%s", state.Members, extra))
			else
				setText(info.Counts.Servers, state.Running and string.format("%d online  ·  running", state.Players or 0) or "offline")
			end

			info.Visibility.Visible = state.Mine

			for _, visibility in private.Visibilities do
				local chip = info.Visibility:FindFirstChild(visibility:sub(1, 1):upper() .. visibility:sub(2))

				if chip then
					chipOn(chip, state.Visibility == visibility)
				end
			end
		end

		showImages(previewFor())

		-- buttons
		local primary = info.Buttons.Primary
		local toggle = info.Buttons.Toggle
		local label, enabled = mode.Primary or "", true

		toggle.Visible = false
		primary.Visible = mode.Primary ~= nil

		if mode.Client then
			enabled = mode.Key == "Friends"
		elseif panel ~= "list" and state then
			if mode.Key == "Tourney" then
				if state.Mine then
					toggle.Visible = true

					if state.StartButton == "cancel" then
						label = "CANCEL"
					elseif state.StartButton == "" then
						label, enabled = "STARTING", false
					else
						label, enabled = "START", state.StartButton == "start"
					end
				else
					label, enabled = "LEAVE LOBBY", state.YourTeam ~= nil and state.Phase == "open"
				end
			else
				label = state.Mine and "JOIN MY SERVER" or "JOIN SERVER"
				enabled = state.Ready and not state.Banned and (not state.Locked or state.Mine) and not isJoining()
			end
		elseif panel == "list" then
			enabled = placesLive[mode.Key] == true
		end

		setText(primary.Label, label)
		setEnabled(primary, enabled)
	end

	----

	local lobbyRows = {}

	local function rowFor(row)
		return row.Rejoin and "rejoin" or row.HostId
	end

	local function drawFooter(row)
		if not row then
			setText(footer.ServerName, "")
			setText(footer.Meta, "")
			setEnabled(footer.Join, false)

			return
		end

		local noun = openMode.Key == "Tourney" and "lobby" or "server"

		if openMode.Client then
			setText(footer.ServerName, row.Host:upper())
			setText(footer.Meta, row.Detail)
			setText(footer.Join.Label, "JOIN")
			setEnabled(footer.Join, row.Joinable == true and not isJoining())

			return
		end

		if row.Rejoin then
			setText(footer.ServerName, spaced("Your last match"))
			setText(footer.Meta, "A match you were in is still running")
		else
			setText(footer.ServerName, row.Mine and spaced("Your " .. noun) or possessive(row.Host, noun))

			local meta = { row.Detail, row.Access:lower() }

			if row.Players then
				table.insert(meta, string.format("%d / %d", row.Players, row.Max))
			elseif openMode.Key == "Freeroam" then
				table.insert(meta, "offline")
			end

			setText(footer.Meta, table.concat(meta, "  ·  "))
		end

		setText(footer.Join.Label, row.Rejoin and "REJOIN" or (openMode.Key == "Tourney" and "OPEN" or "JOIN"))
		setEnabled(footer.Join, not row.Full and not isJoining())
	end

	-- the rows the filters and the search box leave
	local function visibleRows()
		local query = lobbies.Search.Input.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local list = {}

		if rejoin and openMode.Key == "Tourney" then
			table.insert(list, { Rejoin = true, Host = "", Detail = "", Access = "LIVE" })
		end

		if own then
			table.insert(list, own)
		end

		for _, row in rows do
			local keep = true

			if scope == "friends" and not row.Friend then
				keep = false
			end

			if openOnly and (row.Locked or (openMode.Key == "Freeroam" and not row.Running)) then
				keep = false
			end

			if query ~= "" and not row.Host:lower():find(query, 1, true) then
				keep = false
			end

			if keep then
				table.insert(list, row)
			end
		end

		return list
	end

	local drawList

	local function makeRow(id)
		local row = templates.SessionRow:Clone()
		row.Visible = true
		lobbyRows[id] = row

		row.MouseEnter:Connect(function()
			row.HighlightBox.Visible = not row:GetAttribute("Full")
		end)

		row.MouseLeave:Connect(function()
			row.HighlightBox.Visible = selectedHostId == id
		end)

		-- first press selects, pressing the selected row again opens or joins
		row.Activated:Connect(function()
			if row:GetAttribute("Full") then
				return
			end

			playSound("Click")

			if selectedHostId == id then
				library.JoinSelected()
			else
				selectedHostId = id
				drawList()
			end
		end)

		row.Parent = lobbyList

		return row
	end

	function drawList()
		if not openMode then
			return
		end

		local list = visibleRows()
		local seen = {}
		local picked = nil

		for _, row in list do
			if rowFor(row) == selectedHostId and not row.Full then
				picked = row
			end
		end

		if not picked then
			for _, row in list do
				if not row.Full then
					picked = row

					break
				end
			end
		end

		selectedHostId = picked and rowFor(picked) or nil

		for index, row in list do
			local id = rowFor(row)
			local frame = lobbyRows[id] or makeRow(id)
			local chosen = id == selectedHostId
			local ink = row.Full and DIM or BONE

			seen[id] = true
			frame.LayoutOrder = index
			frame.Selectable = not row.Full
			frame:SetAttribute("Full", row.Full == true)
			frame.Stroke.Enabled = chosen
			frame.HighlightBox.Visible = chosen

			if row.Rejoin then
				setText(frame.Line.Host, "Your last match")
				setText(frame.Line.Tag, "")
				setText(frame.Detail, "A match you were in is still running")
				setText(frame.Access, "LIVE")
				setText(frame.Players, "")
				frame.Access.Text.TextColor3 = AMBER
			else
				setText(frame.Line.Host, row.Host)
				setText(frame.Line.Tag, row.Mine and "YOU" or (row.Friend and "FRIEND" or ""))
				setText(frame.Detail, row.Detail)
				setText(frame.Access, row.Access)
				frame.Access.Text.TextColor3 = row.AccessColor or (row.Locked and AMBER or BONE)

				if row.PlayersText then
					setText(frame.Players, row.PlayersText)
				elseif row.Players then
					setText(frame.Players, row.Full and "FULL" or string.format("%d / %d", row.Players, row.Max))
				else
					setText(frame.Players, "offline")
				end
			end

			frame.Line.Host.Text.TextColor3 = ink
			frame.Players.Text.TextColor3 = ink
		end

		for id, frame in lobbyRows do
			if not seen[id] then
				frame:Destroy()
				lobbyRows[id] = nil
			end
		end

		lobbies.Empty.Visible = #list == 0
		lobbies.Filters.Visible = not openMode.Client
		chipOn(lobbies.Filters.Friends, scope == "friends")
		chipOn(lobbies.Filters.Public, scope == "all")
		chipOn(lobbies.Filters.Open, openOnly)
		drawFooter(picked)
	end

	----

	-- the dropdown under a setting's value chip
	local function closeDropdown()
		dropdown.Visible = false
		shield.Visible = false
		dropdownOpen = nil
	end

	local function openDropdown(chip, setting, current, onPick)
		closeDropdown()

		for _, child in dropdown:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for index, option in setting.Options do
			local item = templates.DropdownItem:Clone()
			local picked = option[1] == current

			item.LayoutOrder = index
			item.Label.Text = option[2]
			item.Label.TextColor3 = picked and GOLD or BONE
			item.BackgroundTransparency = picked and 0.88 or 1
			item.Visible = true

			item.MouseEnter:Connect(function()
				item.BackgroundTransparency = 0.88
			end)

			item.MouseLeave:Connect(function()
				item.BackgroundTransparency = picked and 0.88 or 1
			end)

			item.Activated:Connect(function()
				playSound("Click")
				closeDropdown()
				onPick(option[1])
			end)

			item.Parent = dropdown
		end

		-- under the chip, in stage space
		local scale = stage.Scale.Scale
		local corner = (chip.AbsolutePosition - stage.AbsolutePosition) / scale
		local size = chip.AbsoluteSize / scale

		dropdown.Position = UDim2.fromOffset(math.floor(corner.X + size.X - dropdown.Size.X.Offset), math.floor(corner.Y + size.Y + 2))
		dropdown.Visible = true
		shield.Visible = true
		dropdownOpen = chip
	end

	shield.Activated:Connect(closeDropdown)

	----

	-- a setting row whose value chip opens the options; editable or not
	local function makeSettingRow(parent, order, setting, value, editable, onPick)
		local row = templates.SettingRow:Clone()
		row.LayoutOrder = order
		row.Visible = true
		setText(row.Label, setting.Label)
		row.Value.Label.Text = private:Label(setting, value)
		row.Value:SetAttribute("Disabled", not editable)
		row.Value.Chevron.Visible = editable
		row.Value.Stroke.Transparency = editable and 0.45 or 0.8
		row.Value.Label.TextTransparency = editable and 0 or 0.4

		if editable then
			bindChip(row.Value, function()
				if dropdownOpen == row.Value then
					closeDropdown()
				else
					openDropdown(row.Value, setting, value, onPick)
				end
			end)
		end

		row.Parent = parent

		return row
	end

	local function makeHeading(parent, order, title, note)
		local heading = templates.SectionHeading:Clone()
		heading.LayoutOrder = order
		heading.Visible = true
		setText(heading.Title, spaced(title))
		setText(heading.Note, note or "")
		heading.Parent = parent

		return heading
	end

	----

	local countdownThread = nil

	local function drawReadout(frame)
		local big, small = state.Readout[1], state.Readout[2]

		if state.Phase == "countdown" and countdownEnds then
			local left = math.max(0, math.ceil(countdownEnds - os.clock()))
			big = string.format("Starting in %d seconds", left)
		end

		setText(frame.Big, big)
		setText(frame.Small, small)
		frame.Big.Text.TextColor3 = state.Phase == "open" and BONE or AMBER
	end

	local function drawRoster()
		clear(rosterList)

		if not state then
			return
		end

		local readout = templates.Readout:Clone()
		readout.LayoutOrder = 0
		readout.Visible = true
		readout.Parent = rosterList
		drawReadout(readout)

		-- the countdown ticks locally between server updates
		if state.Phase == "countdown" then
			local token = {}
			countdownThread = token

			task.spawn(function()
				while countdownThread == token and readout.Parent do
					task.wait(0.25)

					if countdownThread == token and state and state.Phase == "countdown" then
						drawReadout(readout)
					end
				end
			end)
		else
			countdownThread = nil
		end

		local order = 1

		for index, team in state.Teams do
			local header = templates.TeamHeader:Clone()
			local color = team.Color and teamColor(team.Color) or Color3.fromRGB(109, 109, 109)

			header.LayoutOrder = order
			header.Visible = true
			header.Band.BackgroundColor3 = color
			setText(header.Title, spaced(team.Name))
			setText(header.Count, string.format("%d / %d", #team.Roster, team.Cap))

			local joined = state.YourTeam == index
			header.Join.Visible = state.Phase == "open" and (joined or #team.Roster < team.Cap)
			header.Join.Label.Text = joined and "LEAVE" or "JOIN"

			bindChip(header.Join, function()
				if joined then
					act("leave")
				else
					act("join", index)
				end
			end)

			header.Parent = rosterList
			order += 1

			-- teams show every seat; spectators only the taken ones and a few spare
			local slots = index == 3 and math.max(3, #team.Roster) or team.Cap

			for slot = 1, slots do
				local frame = templates.Slot:Clone()
				local name = team.Roster[slot]

				frame.LayoutOrder = order
				frame.Visible = true
				setText(frame.Player, name or "—")
				frame.Player.Text.TextTransparency = name and 0 or 0.7
				frame.Stroke.Enabled = name == localPlayer.Name

				-- the host can seat anyone else out
				if name and mine() and name ~= localPlayer.Name and state.Phase == "open" then
					frame.MouseEnter:Connect(function()
						frame.Kick.Visible = true
					end)

					frame.MouseLeave:Connect(function()
						frame.Kick.Visible = false
					end)

					bindChip(frame.Kick, function()
						local target = playersService:FindFirstChild(name)

						if target then
							act("kick", target.UserId)
						end
					end)
				end

				frame.Parent = rosterList
				order += 1
			end
		end
	end

	----

	local function drawConfig()
		clear(configList)
		closeDropdown()

		if not state then
			return
		end

		local mode = openMode
		local order = 1
		local editable = mine() and state.Phase == "open"

		makeHeading(configList, order, "Match settings")
		order += 1

		for _, setting in mode.Settings do
			makeSettingRow(configList, order, setting, state.Settings[setting.Key], editable, function(value)
				act("setting", setting.Key, value)
			end)
			order += 1
		end

		makeHeading(configList, order, "Teams")
		order += 1

		for index = 1, 2 do
			local team = state.Teams[index]
			local edit = templates.TeamEdit:Clone()

			edit.LayoutOrder = order
			edit.Visible = true
			edit.Band.BackgroundColor3 = teamColor(team.Color)
			edit.NameBox.Input.Text = team.Name
			edit.NameBox.Input.TextEditable = editable

			edit.NameBox.Input.FocusLost:Connect(function(enter)
				if enter and editable then
					act("teamName", index, edit.NameBox.Input.Text)
				else
					edit.NameBox.Input.Text = team.Name
				end
			end)

			for colorIndex, color in private.TeamColors do
				local swatch = templates.Swatch:Clone()
				swatch.LayoutOrder = colorIndex
				swatch.BackgroundColor3 = color
				swatch.Stroke.Color = colorIndex == team.Color and BONE or Color3.new()
				swatch.Stroke.Transparency = colorIndex == team.Color and 0 or 0.5
				swatch.Visible = true

				if editable then
					swatch.Activated:Connect(function()
						playSound("Click")
						act("teamColor", index, colorIndex)
					end)
				end

				swatch.Parent = edit.Swatches
			end

			edit.Parent = configList
			order += 1
		end

		makeHeading(configList, order, "Maps", string.format("%d selected", #state.Maps))
		order += 1

		local grid = templates.MapTiles:Clone()
		grid.LayoutOrder = order
		grid.Visible = true

		for mapIndex, map in mode.Maps do
			local tile = templates.MapTile:Clone()
			local pick = table.find(state.Maps, map.Name)

			tile.LayoutOrder = mapIndex
			tile.Visible = true
			tile.Image = map.SmallImage
			tile.ImageColor3 = pick and Color3.new(1, 1, 1) or Color3.fromRGB(110, 110, 110)
			tile.Stroke.Color = pick and GOLD or Color3.fromRGB(98, 94, 90)
			setText(tile.Title, map.DisplayName)
			tile.Pick.Visible = pick ~= nil
			tile.Pick.Text.Text = pick and ordinal(pick) or ""

			tile.MouseEnter:Connect(function()
				tile.HighlightBox.Visible = editable
			end)

			tile.MouseLeave:Connect(function()
				tile.HighlightBox.Visible = false
			end)

			tile.Activated:Connect(function()
				if editable then
					playSound("Click")
					act("map", map.Name)
				end
			end)

			tile.Parent = grid
		end

		grid.Parent = configList
	end

	----

	local function makePlayerRow(parent, order, name, action, onAction)
		local row = templates.PlayerRow:Clone()
		row.LayoutOrder = order
		row.Visible = true
		setText(row.Player, name)
		row.Actions.Ban.Visible = false
		row.Actions.Unban.Visible = action == "unban"

		if action == "ban" then
			row.MouseEnter:Connect(function()
				row.Actions.Ban.Visible = true
				row.Stroke.Enabled = true
			end)

			row.MouseLeave:Connect(function()
				row.Actions.Ban.Visible = false
				row.Stroke.Enabled = false
			end)

			bindChip(row.Actions.Ban, onAction)
		elseif action == "unban" then
			bindChip(row.Actions.Unban, onAction)
		end

		row.Parent = parent
	end

	local function drawServer()
		clear(serverList)
		closeDropdown()

		if not state then
			return
		end

		local mode = openMode
		local order = 1
		local editable = mine()

		makeHeading(serverList, order, state.Mine and "My server" or (state.Host .. "'s server"),
			state.Broken and "couldn't reach the server" or (not state.Ready and "setting up" or nil))
		order += 1

		for _, setting in mode.Settings do
			makeSettingRow(serverList, order, setting, state.Settings[setting.Key], editable, function(value)
				act("setting", setting.Key, value)
			end)
			order += 1
		end

		makeHeading(serverList, order, "Online", state.Running and count(#state.Online, "player") or "server offline")
		order += 1

		for _, name in state.Online do
			local target = playersService:FindFirstChild(name)
			local canBan = editable and name ~= localPlayer.Name and name ~= state.Host

			makePlayerRow(serverList, order, name, canBan and "ban" or nil, function()
				if target then
					act("ban", target.UserId)
				end
			end)
			order += 1
		end

		if editable then
			makeHeading(serverList, order, "Banned", count(#state.Bans, "player"))
			order += 1

			for _, ban in state.Bans do
				makePlayerRow(serverList, order, ban.Name or "…", "unban", function()
					act("unban", ban.UserId)
				end)
				order += 1
			end
		end
	end

	----

	local function showPanel(name)
		panel = name
		lobbies.Visible = name == "list" and not (openMode and openMode.Static)
		roster.Visible = name == "roster"
		config.Visible = name == "config"
		server.Visible = name == "server"
		closeDropdown()
	end

	local function drawPanel()
		if panel == "roster" then
			drawRoster()
		elseif panel == "config" then
			drawConfig()
		elseif panel == "server" then
			drawServer()
		else
			drawList()
		end

		drawInfo()
	end

	-- back to the list from a session
	local function leaveSession()
		if viewedHostId then
			remote:FireServer("unview")
		end

		viewedHostId = nil
		state = nil
		countdownThread = nil
		showPanel("list")
		drawPanel()
	end

	local function viewSession(hostId)
		if not openMode then
			return
		end

		viewedHostId = hostId
		state = nil
		showPanel(openMode.Key == "Tourney" and "roster" or "server")
		remote:FireServer("view", openMode.Key, hostId)
		drawInfo()
	end

	----

	function library.IsOpen()
		return openMode ~= nil
	end

	-- the page's column labels
	local function drawColumns(mode)
		local labels = mode.Columns or { "Host", "Access", "Players" }

		for index, name in { "Host", "Access", "Players" } do
			local column = lobbies.Columns:FindFirstChild(name)

			if column then
				column.Text = spaced(labels[index])
			end
		end
	end

	-- GetFriendsOnlineAsync is client-only; the server sorts out where each
	-- friend is from what it returns
	local function askFriends()
		task.spawn(function()
			local fetched, online = pcall(localPlayer.GetFriendsOnlineAsync, localPlayer, 200)
			local entries = {}

			for _, entry in fetched and type(online) == "table" and online or {} do
				if type(entry) == "table" then
					table.insert(entries, {
						VisitorId = entry.VisitorId,
						UserName = entry.UserName,
						LastLocation = entry.LastLocation,
						PlaceId = entry.PlaceId,
						GameId = entry.GameId,
						LocationType = entry.LocationType,
					})
				end
			end

			if not fetched then
				warn("Lobby couldn't read online friends:", online)
			end

			remote:FireServer("friends", entries)
		end)
	end

	function library.Open(key)
		local mode = private.ByKey[key] or CLIENT_MODES[key]

		if not mode or openMode then
			return
		end

		openMode = mode
		rows, own, rejoin = {}, nil, nil
		selectedHostId = nil

		for _, frame in lobbyRows do
			frame:Destroy()
		end

		table.clear(lobbyRows)

		setText(lobbies.Heading, spaced(mode.Heading or ""))
		setText(lobbies.Empty, spaced(mode.Empty or ""))
		lobbies.Filters.Open.Label.Text = mode.Key == "Freeroam" and "RUNNING" or "OPEN"
		lobbies.Search.Input.Text = ""
		drawColumns(mode)

		showPanel("list")
		drawPanel()

		view.Visible = true

		if mode.Key == "Friends" then
			askFriends()

			-- the list refreshes itself while the page is open
			task.spawn(function()
				while openMode == mode do
					task.wait(FRIENDS_REFRESH)

					if openMode == mode then
						askFriends()
					end
				end
			end)
		elseif not mode.Client then
			remote:FireServer("open", key)
		end

		playSound("MapOpen")
	end

	function library.Close()
		if not openMode then
			return
		end

		if viewedHostId then
			leaveSession()
		end

		if not openMode.Client then
			remote:FireServer("close")
		end

		openMode = nil
		state = nil
		view.Visible = false

		if preview then
			preview:Stop()
			previewImages = nil
		end

		closeDropdown()
		playSound("MapClose")
		context.onClosed()
	end

	-- gamepad B and the back button: a session goes back to its list first
	function library.Back()
		if not openMode then
			return false
		end

		if viewedHostId then
			leaveSession()
		else
			library.Close()
		end

		return true
	end

	function library.JoinSelected()
		if not openMode or not selectedHostId then
			return
		end

		if openMode.Key == "Friends" then
			setStatus("joining")
			loading.Prepare(openMode.Name)
			remote:FireServer("follow", selectedHostId)
		elseif openMode.Client then
			return
		elseif selectedHostId == "rejoin" then
			setStatus("joining")
			loading.Prepare(openMode.Name)
			remote:FireServer("rejoin")
		elseif openMode.Key == "Tourney" then
			viewSession(selectedHostId)
		else
			viewedHostId = selectedHostId
			setStatus("joining")
			loading.Prepare(openMode.Name)
			act("join", here)
			viewedHostId = nil
		end
	end

	----

	-- the mode tiles, after the map cards
	local function drawCard(mode)
		local card = cards[mode.Key]
		local tally = counts[mode.Key] or {}
		local live = placesLive[mode.Key] == true

		card.ComingSoon.Visible = not live
		card.Button.Selectable = live
		card.Online.Visible = live

		if mode.Key == "Tourney" then
			setText(card.Online, string.format("%d queued  ·  %s", tally.Online or 0, plural(tally.Sessions or 0, "lobby", "lobbies")))
		else
			setText(card.Online, string.format("%d online  ·  %s", tally.Online or 0, count(tally.Sessions or 0, "server")))
		end
	end

	local function promptInvite()
		pcall(function()
			if socialService:CanSendGameInviteAsync(localPlayer) then
				socialService:PromptGameInvite(localPlayer)
			end
		end)
	end

	local hubCard = nil

	-- the hub tile at the front of the row: the logo and the page buttons
	local function makeHubCard()
		local template = templates:FindFirstChild("HubTile")

		if not template then
			return
		end

		hubCard = template:Clone()
		hubCard.Name = "Hub"
		hubCard.LayoutOrder = 0
		hubCard.Visible = true

		bindButton(hubCard.Buttons.Friends, function()
			context.openMode("Friends")
		end)

		bindButton(hubCard.Buttons.News, function()
			context.openMode("News")
		end)

		bindButton(hubCard.Buttons.Events, function()
			context.openMode("Events")
		end)

		hubCard.Parent = cardRow
	end

	local function makeCard(mode, order)
		local card = templates.ModeCard:Clone()
		card.Name = mode.Key
		card.LayoutOrder = order
		card.Visible = true

		setText(card.Title, spaced(mode.Name))
		drawChips(card.Platforms, mode)
		drawTags(card.Tags, mode)
		-- the old VIP cards' art, run over the whole card like they did
		card.Icon.Image = mode.Icon or ""
		card.Icon.AnchorPoint = Vector2.zero
		card.Icon.Position = UDim2.new()
		card.Icon.Size = UDim2.fromScale(1, 1)
		card.Icon.ScaleType = Enum.ScaleType.Crop

		local glow = card:FindFirstChild("HighlightShadow")

		card.Button.MouseEnter:Connect(function()
			local on = placesLive[mode.Key] == true
			card.HighlightBox.Visible = on

			if glow then
				glow.Enabled = on
			end
		end)

		card.Button.MouseLeave:Connect(function()
			card.HighlightBox.Visible = false

			if glow then
				glow.Enabled = false
			end
		end)

		card.Button.Activated:Connect(function()
			if placesLive[mode.Key] then
				context.openMode(mode.Key)
			end
		end)

		cards[mode.Key] = card
		card.Parent = cardRow
		drawCard(mode)
	end

	-- keeps the tiles after the last map card whenever the maps change
	function library.SyncCards(mapCount)
		if not hubCard then
			makeHubCard()
		end

		for index, mode in private.Modes do
			if not cards[mode.Key] then
				makeCard(mode, mapCount + index)
			else
				cards[mode.Key].LayoutOrder = mapCount + index
			end

			drawCard(mode)
		end
	end

	----

	remote.OnClientEvent:Connect(function(message, ...)
		if message == "list" then
			local key, list, ownRow = ...

			if openMode and openMode.Key == key then
				rows, own = list or {}, ownRow

				if panel == "list" then
					drawList()
				end

				if pendingFollow and key == "Tourney" and panel == "list" then
					for _, row in rows do
						if row.HostId == pendingFollow then
							pendingFollow = nil
							viewSession(row.HostId)

							break
						end
					end
				end
			end
		elseif message == "state" then
			local key, hostId, incoming = ...

			if openMode and openMode.Key == key and viewedHostId == hostId then
				if incoming then
					state = incoming
					countdownEnds = incoming.CountdownLeft and (os.clock() + incoming.CountdownLeft) or nil
					drawPanel()
				else
					-- the host left or locked us out
					leaveSession()
				end
			end
		elseif message == "friends" then
			local incoming = ...

			if openMode and openMode.Key == "Friends" then
				rows = {}

				for _, friend in incoming or {} do
					table.insert(rows, {
						HostId = friend.UserId,
						Host = friend.Name,
						Detail = friend.Detail,
						Access = friend.Where,
						AccessColor = friend.Where == "LOBBY" and GOLD or nil,
						Players = friend.Players,
						Max = friend.Max,
						PlayersText = friend.Players and string.format("%d / %d", friend.Players, friend.Max) or (friend.Joinable and "" or "—"),
						Full = not friend.Joinable,
						Joinable = friend.Joinable,
					})
				end

				own = nil
				drawList()
				drawInfo()
			end
		elseif message == "open" then
			-- back from a game mode: its page
			local key = ...

			if not openMode and (private.ByKey[key] or CLIENT_MODES[key]) then
				context.openMode(key)
			end
		elseif message == "follow" then
			-- a friend's JOIN sent us here: open their lobby once it's listed
			pendingFollow = ...

			if not openMode then
				context.openMode("Tourney")
			end
		elseif message == "rejoin" then
			rejoin = ...

			if openMode and panel == "list" then
				drawList()
			end
		elseif message == "counts" then
			local incoming, live = ...
			counts = incoming or {}
			placesLive = live or placesLive

			for _, mode in private.Modes do
				if cards[mode.Key] then
					drawCard(mode)
				end
			end

			if openMode and panel == "list" then
				drawInfo()
			end
		end
	end)

	----

	-- bindings
	bindButton(info.Buttons.Back, function()
		library.Back()
	end, false)

	bindButton(info.Buttons.Primary, function()
		if not openMode then
			return
		end

		if openMode.Key == "Friends" then
			promptInvite()
		elseif openMode.Client then
			return
		elseif panel == "list" then
			viewSession(localPlayer.UserId)
		elseif openMode.Key == "Tourney" and state then
			if state.Mine then
				act(state.StartButton == "cancel" and "cancel" or "start")
			else
				act("leave")
			end
		elseif state then
			setStatus("joining")
			loading.Prepare(openMode.Name)
			act("join", here)
		end
	end)

	bindButton(info.Buttons.Toggle, function()
		if panel == "roster" then
			showPanel("config")
		else
			showPanel("roster")
		end

		drawPanel()
	end)

	bindButton(footer.Join, library.JoinSelected)

	for _, visibility in private.Visibilities do
		local chip = info.Visibility:FindFirstChild(visibility:sub(1, 1):upper() .. visibility:sub(2))

		if chip then
			bindChip(chip, function()
				act("visibility", visibility)
			end)
		end
	end

	local invite = info.Visibility:FindFirstChild("Invite")

	if invite then
		bindChip(invite, promptInvite)
	end

	-- a friend's JOIN may have sent us here
	remote:FireServer("ready")

	bindChip(lobbies.Filters.Friends, function()
		scope = "friends"
		drawList()
	end)

	bindChip(lobbies.Filters.Public, function()
		scope = "all"
		drawList()
	end)

	bindChip(lobbies.Filters.Open, function()
		openOnly = not openOnly
		drawList()
	end)

	lobbies.Search.Input:GetPropertyChangedSignal("Text"):Connect(function()
		drawList()
	end)

	for _, scroller in { lobbyList, rosterList, configList, serverList } do
		context.edgeFade(scroller)
	end

	-- a join that settled (or failed) re-enables the buttons
	function library.OnStatus()
		if not openMode then
			return
		end

		if panel == "list" then
			drawList()
		elseif state then
			drawInfo()
		end
	end

	return library
end
