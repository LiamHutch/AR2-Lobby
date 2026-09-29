-- Builds StarterGui.Lobby in the open place. Paste into the Studio command bar.
-- Destroys and rebuilds Lobby if it exists; hand edits made in Studio are lost.
--
-- The map card is cloned from StarterGui.PickerDemo (the main menu's VIPHome
-- card) so it keeps the game's exact styling; the backdrop values come from
-- ReplicatedStorage.Interface.MainMenu.Master.Background in the game place.
-- PickerDemo is disabled, not deleted.
--
-- Names the client script binds to are listed in README.md ("UI contract").

local starterGui = game:GetService("StarterGui")

local picker = starterGui:FindFirstChild("PickerDemo")
assert(picker, "StarterGui.PickerDemo is needed as the card source")

local source = picker.Options.Bin.BetaMap

local OSWALD = "rbxasset://fonts/families/Oswald.json"
local TEXT = Color3.fromRGB(184, 184, 184)
local SUBTEXT = Color3.fromRGB(204, 204, 204)
local PANEL = Color3.fromRGB(24, 24, 24)
local ROW = Color3.fromRGB(40, 40, 40)

----

local function make(className, props, children)
	local object = Instance.new(className)

	for key, value in props do
		object[key] = value
	end

	for _, child in children or {} do
		child.Parent = object
	end

	return object
end

local function font(weight, style)
	return Font.new(OSWALD, weight, style or Enum.FontStyle.Normal)
end

local function numbers(points)
	local keys = {}

	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end

	return NumberSequence.new(keys)
end

local function colors(points)
	local keys = {}

	for _, point in points do
		table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2]))
	end

	return ColorSequence.new(keys)
end

local function shadow(zIndex)
	local object = source.Shadow:Clone()
	object.ZIndex = zIndex or 1

	return object
end

local function highlight(zIndex)
	local object = source.HighlightBox:Clone()
	object.Visible = false
	object.ZIndex = zIndex or 10

	return object
end

local function hitbox(zIndex)
	return make("ImageButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		ZIndex = zIndex or 20,
	})
end

----

local function buildBackground()
	local function grit(name, image, anchor, scale, transparency)
		return make("ImageLabel", {
			Name = name,
			AnchorPoint = anchor,
			Position = UDim2.fromScale(anchor.X, anchor.Y),
			Size = UDim2.fromScale(scale, scale),
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = Color3.new(0, 0, 0),
			ImageTransparency = transparency,
		}, {
			make("UISizeConstraint", { MaxSize = Vector2.new(1024, 1024) }),
		})
	end

	return make("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, {
		make("ImageLabel", {
			Name = "BackdropImage",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(47, 47, 47),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Image = "rbxassetid://103463374121990",
			ImageColor3 = Color3.fromRGB(156, 156, 156),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 1,
		}),

		make("Frame", {
			Name = "GradientDrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			make("UIGradient", {
				Rotation = 90,
				Transparency = numbers({
					{ 0, 0.49375 }, { 0.164368, 0.75 }, { 0.334483, 0.8625 }, { 0.514943, 0.8 },
					{ 0.721839, 0.64375 }, { 0.86092, 0.44375 }, { 1, 0 },
				}),
			}),
		}),

		make("Frame", {
			Name = "GradientFade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			make("UIGradient", {
				Rotation = 90,
				Color = colors({
					{ 0, Color3.fromRGB(100, 100, 100) },
					{ 0.5, Color3.fromRGB(102, 100, 86) },
					{ 1, Color3.fromRGB(50, 50, 50) },
				}),
				Transparency = numbers({ { 0, 0.3375 }, { 0.498851, 1 }, { 1, 0.30625 } }),
			}),
		}),

		make("Frame", {
			Name = "Grit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, {
			grit("BottomRight2", "rbxassetid://83808700820268", Vector2.new(1, 1), 1, 0),
			grit("BottomLeft2", "rbxassetid://97071793107351", Vector2.new(0, 1), 1, 0),
			grit("BottomRight1", "rbxassetid://111332206534538", Vector2.new(1, 1), 0.7, 0.79),
			grit("BottomLeft1", "rbxassetid://123577345537370", Vector2.new(0, 1), 0.7, 0.79),
		}),
	})
end

local function buildMapCard()
	local card = source:Clone()
	card.Name = "MapCard"
	card.Size = UDim2.fromScale(1, 1)
	card.SizeConstraint = Enum.SizeConstraint.RelativeYY
	card.LayoutOrder = 0

	card.TextLabel.Name = "Title"
	card.Status.Visible = false
	card.ComingSoon.Visible = false
	card.HighlightBox.Visible = false

	card.Locked:Destroy()
	card.ImageLabel:Destroy()

	-- map art sits over the patterned background and fades to black under the title
	make("ImageLabel", {
		Name = "Art",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 4,
		Parent = card,
	}, {
		make("UIGradient", {
			Rotation = 90,
			Color = colors({
				{ 0, Color3.new(1, 1, 1) },
				{ 0.45, Color3.new(1, 1, 1) },
				{ 1, Color3.fromRGB(26, 26, 26) },
			}),
		}),
	})

	make("TextLabel", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.78, -6),
		Size = UDim2.fromScale(1, 0.07),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Regular, Enum.FontStyle.Italic),
		TextScaled = true,
		TextColor3 = SUBTEXT,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Text = "",
		Visible = false,
		ZIndex = 5,
		Parent = card,
	})

	-- floating pill under the card
	make("Frame", {
		Name = "Servers",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 16),
		Size = UDim2.new(0.5, 0, 0, 30),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = card,
	}, {
		shadow(1),

		make("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),

		make("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Medium),
			TextSize = 15,
			TextColor3 = TEXT,
			Text = "S E R V E R S",
			ZIndex = 3,
		}),

		highlight(10),
		hitbox(20),
	})

	return card
end

local function buildServerRow()
	return make("Frame", {
		Name = "ServerRow",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
	}, {
		make("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = ROW,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 1,
		}),

		make("TextLabel", {
			Name = "Players",
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 18,
			TextColor3 = TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "0 / 0",
			ZIndex = 2,
		}),

		make("TextLabel", {
			Name = "Uptime",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Regular, Enum.FontStyle.Italic),
			TextSize = 16,
			TextColor3 = SUBTEXT,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "0m",
			ZIndex = 2,
		}),

		highlight(10),
		hitbox(20),
	})
end

local function buildServersPanel()
	return make("Frame", {
		Name = "Servers",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 440, 0.62, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, {
		shadow(1),

		make("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 2,
		}),

		make("TextLabel", {
			Name = "Title",
			Position = UDim2.fromOffset(20, 14),
			Size = UDim2.new(1, -80, 0, 30),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Bold),
			RichText = true,
			TextSize = 26,
			TextColor3 = TEXT,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
			ZIndex = 3,
		}),

		make("TextButton", {
			Name = "Close",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 14),
			Size = UDim2.fromOffset(30, 30),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 20,
			TextColor3 = TEXT,
			Text = "X",
			ZIndex = 4,
		}),

		(function()
			local object = highlight(5)
			object.Name = "CloseHighlight"
			object.AnchorPoint = Vector2.new(0.5, 0.5)
			object.Position = UDim2.new(1, -29, 0, 29)
			object.Size = UDim2.fromOffset(40, 40)

			return object
		end)(),

		make("ScrollingFrame", {
			Name = "List",
			Position = UDim2.fromOffset(14, 58),
			Size = UDim2.new(1, -28, 1, -72),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = TEXT,
			ZIndex = 3,
		}, {
			make("UIListLayout", {
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),

			-- room for the highlight box, which overhangs each row by 5px
			make("UIPadding", {
				PaddingTop = UDim.new(0, 5),
				PaddingBottom = UDim.new(0, 5),
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 8),
			}),
		}),

		make("TextLabel", {
			Name = "Empty",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 20),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Regular, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = SUBTEXT,
			TextTransparency = 0.3,
			Text = "N O   S E R V E R S",
			Visible = false,
			ZIndex = 3,
		}),
	})
end

----

local existing = starterGui:FindFirstChild("Lobby")

if existing then
	existing:Destroy()
end

make("ScreenGui", {
	Name = "Lobby",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = starterGui,
}, {
	buildBackground(),

	make("Frame", {
		Name = "Maps",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -24),
		Size = UDim2.new(1, -64, 0.4, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		make("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 400) }),

		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 24),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}),

	buildServersPanel(),

	make("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -48),
		Size = UDim2.fromOffset(400, 26),
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
		TextSize = 20,
		TextColor3 = TEXT,
		Text = "",
		Visible = false,
		ZIndex = 4,
	}),

	make("Folder", { Name = "Templates" }, {
		buildMapCard(),
		buildServerRow(),
	}),
})

picker.Enabled = false

print("Lobby UI built")
