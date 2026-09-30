-- Builds ReplicatedFirst.Lobby in the open place. Paste into the Studio command bar.
-- Destroys and rebuilds Lobby if it exists; hand edits made in Studio are lost.
--
-- Styling copies the game's main menu (ReplicatedStorage.Interface.MainMenu.Master
-- in the game place, mostly VIPHome.FreeroamWindow): Oswald Heavy headers,
-- bone text drawn twice for a drop shadow, gold-stroked grunge buttons, rows
-- that fade in from the left.
--
-- The gui lives in ReplicatedFirst because the lobby never spawns characters,
-- so StarterGui would never be copied in; the client script moves it into
-- PlayerGui itself.
--
-- Everything is laid out on a 1440x810 Stage that the client scales to fit.
-- Names the client script binds to are listed in CLAUDE.md ("UI contract").

local replicatedFirst = game:GetService("ReplicatedFirst")

local OSWALD = "rbxassetid://12187372847"
local SOURCE_SANS = "rbxasset://fonts/families/SourceSansPro.json"

local BONE = Color3.fromRGB(229, 226, 219)
local GOLD = Color3.fromRGB(202, 188, 131)
local GREY = Color3.fromRGB(177, 177, 177)
local PANEL = Color3.fromRGB(27, 27, 27)
local BLACK = Color3.new(0, 0, 0)

local SHADOW = "rbxassetid://1677877208"
local HIGHLIGHT = "rbxassetid://6116907099"
local GRUNGE = "rbxassetid://104544475726279"
local TORN_EDGE = "rbxassetid://129891927624984"
local BACK_ICON = "rbxassetid://90333380641559"
local REFRESH_ICON = "" -- none in the game yet; a text glyph stands in

local STAGE = Vector2.new(1440, 810)

----

local function make(className, props, children)
	local object = Instance.new(className)

	for key, value in props do
		object[key] = value
	end

	-- children may be instances or lists of them
	for _, child in children or {} do
		if typeof(child) == "Instance" then
			child.Parent = object
		else
			for _, nested in child do
				nested.Parent = object
			end
		end
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

local function ordered(object, order)
	object.LayoutOrder = order

	return object
end

-- a Frame named `name` holding `Text` and its black `Shadow` copy, offset down
-- and right like every label in the game. Set both through the client's setText.
local function text(name, boxProps, labelProps, offset)
	local auto = boxProps.AutomaticSize or Enum.AutomaticSize.None

	labelProps.Name = "Text"
	labelProps.BackgroundTransparency = 1
	labelProps.AutomaticSize = auto
	labelProps.Size = labelProps.Size or (auto == Enum.AutomaticSize.None and UDim2.fromScale(1, 1) or UDim2.new())
	labelProps.ZIndex = 2

	local label = make("TextLabel", labelProps)
	local shadow = label:Clone()
	shadow.Name = "Shadow"
	shadow.RichText = false
	shadow.TextColor3 = BLACK
	shadow.TextTransparency = 0.75
	shadow.TextStrokeTransparency = 1
	shadow.Position = label.Position + UDim2.fromOffset(offset, offset)
	shadow.ZIndex = 1

	boxProps.Name = name
	boxProps.BackgroundTransparency = 1

	return make("Frame", boxProps, { shadow, label })
end

local function shadow(transparency)
	return make("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 30, 1, 30),
		BackgroundTransparency = 1,
		Image = SHADOW,
		ImageColor3 = BLACK,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(30, 30, 30, 30),
		ZIndex = 0,
	})
end

local function highlight()
	return make("ImageLabel", {
		Name = "HighlightBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundTransparency = 1,
		Image = HIGHLIGHT,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(13, 13, 13, 13),
		Visible = false,
		ZIndex = 8,
	})
end

local function hitbox()
	return make("ImageButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		ZIndex = 10,
	})
end

-- the game's button: black frame, 2px mitred stroke, tinted grunge, soft
-- shadow, highlight box on hover, clear ImageButton on top
local function button(name, size, stroke, tint, content)
	return make("Frame", {
		Name = name,
		Size = size,
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = stroke,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		make("ImageLabel", {
			Name = "Backdrop",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, 2, 1, 2),
			BackgroundTransparency = 1,
			Image = GRUNGE,
			ImageColor3 = tint,
			ImageTransparency = 0.7,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(1048, 1048),
			ZIndex = 1,
		}),

		shadow(0.7),
		content,
		highlight(),
		hitbox(),
	})
end

local function textButton(name, size, label)
	return button(name, size, GOLD, Color3.fromRGB(255, 193, 138), text("Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.8),
		ZIndex = 3,
	}, {
		FontFace = font(Enum.FontWeight.Heavy),
		TextScaled = true,
		TextColor3 = GOLD,
		Text = label,
	}, 4))
end

local function iconButton(name, icon, glyph)
	local content

	if icon ~= "" then
		content = make("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = icon,
			ImageColor3 = BONE,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(21, 21, 21, 21),
			ZIndex = 3,
		})
	else
		content = text("Icon", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.7, 0.7),
			ZIndex = 3,
		}, {
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = BONE,
			Text = glyph,
		}, 2)
	end

	return button(name, UDim2.fromOffset(60, 60), BONE, BONE, content)
end

-- shown next to Play for maps that need a password
local function passwordField()
	return make("Frame", {
		Name = "Password",
		Size = UDim2.fromOffset(160, 60),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Transparency = 0.6,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		shadow(0.7),

		make("TextBox", {
			Name = "Input",
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 18,
			TextColor3 = BONE,
			PlaceholderText = "P A S S W O R D",
			PlaceholderColor3 = Color3.fromRGB(120, 118, 114),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			ZIndex = 3,
		}),

		highlight(),
	})
end

local function list(direction, padding, extra)
	local props = {
		FillDirection = direction,
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}

	for key, value in extra or {} do
		props[key] = value
	end

	return make("UIListLayout", props)
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
			ImageColor3 = BLACK,
			ImageTransparency = transparency,
		}, {
			make("UISizeConstraint", { MaxSize = Vector2.new(1024, 1024) }),
		})
	end

	return make("Frame", {
		Name = "Background",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		make("ImageLabel", {
			Name = "BackdropImage",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(47, 47, 47),
			BorderSizePixel = 0,
			Image = "rbxassetid://103463374121990",
			ImageColor3 = Color3.fromRGB(156, 156, 156),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 1,
		}),

		-- the open map's tiny Backdrop image, upscaled so it reads as a blur
		make("ImageLabel", {
			Name = "Bleed",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "",
			ImageColor3 = Color3.fromRGB(110, 110, 110),
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 2,
		}),

		make("Frame", {
			Name = "GradientDrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 3,
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
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 4,
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
			ZIndex = 5,
		}, {
			grit("BottomRight2", "rbxassetid://83808700820268", Vector2.new(1, 1), 1, 0),
			grit("BottomLeft2", "rbxassetid://97071793107351", Vector2.new(0, 1), 1, 0),
			grit("BottomRight1", "rbxassetid://111332206534538", Vector2.new(1, 1), 0.7, 0.79),
			grit("BottomLeft1", "rbxassetid://123577345537370", Vector2.new(0, 1), 0.7, 0.79),
		}),
	})
end

----

local function buildPicker()
	return make("Frame", {
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		make("ScrollingFrame", {
			Name = "Maps",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 580),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
		}, {
			list(Enum.FillDirection.Horizontal, 36, {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			make("UIPadding", {
				PaddingLeft = UDim.new(0, 64),
				PaddingRight = UDim.new(0, 64),
			}),
		}),
	})
end

local function buildInfo()
	local function spacer(order, height)
		return make("Frame", {
			Name = "Spacer" .. order,
			LayoutOrder = order,
			Size = UDim2.fromOffset(1, height),
			BackgroundTransparency = 1,
		})
	end

	return make("Frame", {
		Name = "Info",
		Position = UDim2.fromOffset(64, 60),
		Size = UDim2.fromOffset(600, 720),
		BackgroundTransparency = 1,
	}, {
		list(Enum.FillDirection.Vertical, 10),

		text("Title", { LayoutOrder = 1, Size = UDim2.fromOffset(600, 64) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextScaled = true,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText = true,
			Text = "",
		}, 4),

		make("Frame", {
			Name = "Counts",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(600, 34),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 14, { VerticalAlignment = Enum.VerticalAlignment.Bottom }),

			text("Online", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 34) }, {
				FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
				TextSize = 26,
				TextColor3 = GREY,
				Size = UDim2.fromOffset(0, 34),
				Text = "",
			}, 2),

			text("Servers", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30) }, {
				FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
				TextSize = 20,
				TextColor3 = BONE,
				TextTransparency = 0.45,
				Size = UDim2.fromOffset(0, 30),
				Text = "",
			}, 2),
		}),

		text("Blurb", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(560, 0) }, {
			FontFace = Font.new(SOURCE_SANS, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
			TextSize = 19,
			TextColor3 = BONE,
			TextTransparency = 0.3,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(560, 0),
			Text = "",
		}, 2),

		make("Frame", {
			Name = "Stats",
			LayoutOrder = 4,
			Size = UDim2.fromOffset(600, 46),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 30),
		}),

		make("Frame", {
			Name = "Platforms",
			LayoutOrder = 5,
			Size = UDim2.fromOffset(600, 24),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
		}),

		text("Notice", { LayoutOrder = 6, Size = UDim2.fromOffset(600, 20), Visible = false }, {
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 15,
			TextColor3 = Color3.fromRGB(227, 166, 74),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 1),

		spacer(7, 4),

		make("Frame", {
			Name = "Preview",
			LayoutOrder = 8,
			Size = UDim2.fromOffset(512, 288),
			BackgroundTransparency = 1,
		}, {
			shadow(0.5),

			-- ImageA/ImageB crossfade; the client pans them inside the clip
			make("Frame", {
				Name = "Clip",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = PANEL,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 1,
			}, {
				make("ImageLabel", {
					Name = "ImageA",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1.12, 1.12),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Crop,
					Image = "",
					ZIndex = 1,
				}),

				make("ImageLabel", {
					Name = "ImageB",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1.12, 1.12),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Crop,
					Image = "",
					ImageTransparency = 1,
					ZIndex = 2,
				}),
			}),
		}),

		spacer(9, 12),

		make("Frame", {
			Name = "Buttons",
			LayoutOrder = 10,
			Size = UDim2.fromOffset(600, 60),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 16),
			ordered(iconButton("Back", BACK_ICON, "<"), 1),
			ordered(textButton("Play", UDim2.fromOffset(283, 60), "PLAY"), 2),
			ordered(iconButton("Refresh", REFRESH_ICON, "↻"), 3),
			ordered(passwordField(), 4),
		}),
	})
end

local function sortChip(name, label, order)
	return make("Frame", {
		Name = name,
		LayoutOrder = order,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 3) }),
		make("UIStroke", { Name = "Stroke", Color = BONE, Transparency = 0.8, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),

		-- the padding lives on the label: on the chip it would shrink the highlight too
		make("TextLabel", {
			Name = "Label",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 12,
			TextColor3 = BONE,
			TextTransparency = 0.5,
			Text = label,
			ZIndex = 2,
		}, {
			make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		}),

		highlight(),
		hitbox(),
	})
end

local function buildBrowser()
	local function column(name, label, position, size, align)
		return make("TextLabel", {
			Name = name,
			Position = position,
			Size = size,
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 12,
			TextColor3 = BONE,
			TextTransparency = 0.55,
			TextXAlignment = align or Enum.TextXAlignment.Left,
			Text = label,
		})
	end

	return make("Frame", {
		Name = "Browser",
		Position = UDim2.fromOffset(STAGE.X - 48 - 620, 60),
		Size = UDim2.fromOffset(620, 720),
		BackgroundTransparency = 1,
	}, {
		text("Heading", { Size = UDim2.fromOffset(320, 44) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 40,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "S E R V E R S",
		}, 4),

		make("Frame", {
			Name = "Sorts",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 12),
			Size = UDim2.fromOffset(300, 26),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
			sortChip("Players", "P L A Y E R S", 1),
			sortChip("Newest", "N E W E S T", 2),
			sortChip("Region", "R E G I O N", 3),
		}),

		-- same offsets as ServerRow's cells, inside the list's 6px padding
		make("Frame", {
			Name = "Columns",
			Position = UDim2.fromOffset(6, 62),
			Size = UDim2.new(1, -12, 0, 16),
			BackgroundTransparency = 1,
		}, {
			column("Server", "S E R V E R", UDim2.fromOffset(14, 0), UDim2.new(1, -350, 1, 0)),
			column("Region", "R E G I O N", UDim2.new(1, -328, 0, 0), UDim2.new(0, 110, 1, 0)),
			column("Uptime", "U P T I M E", UDim2.new(1, -206, 0, 0), UDim2.new(0, 90, 1, 0)),
			column("Players", "P L A Y E R S", UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), Enum.TextXAlignment.Right),
		}),

		make("ScrollingFrame", {
			Name = "List",
			Position = UDim2.fromOffset(0, 84),
			Size = UDim2.new(1, 0, 1, -84 - 92),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 0,
		}, {
			list(Enum.FillDirection.Vertical, 4),

			-- room for the highlight box, which overhangs rows by 5px
			make("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 6),
				PaddingRight = UDim.new(0, 6),
			}),
		}),

		text("Empty", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 200),
			Size = UDim2.fromOffset(400, 30),
			Visible = false,
		}, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			TextTransparency = 0.5,
			Text = "N O   S E R V E R S",
		}, 2),

		make("Frame", {
			Name = "Footer",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 76),
			BackgroundTransparency = 1,
		}, {
			text("ServerName", { Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(390, 36) }, {
				FontFace = font(Enum.FontWeight.Heavy),
				TextSize = 30,
				TextColor3 = BONE,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "",
			}, 4),

			text("Meta", { Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(390, 22) }, {
				FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
				TextSize = 16,
				TextColor3 = BONE,
				TextTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "",
			}, 2),

			(function()
				local object = textButton("Join", UDim2.fromOffset(200, 60), "JOIN")
				object.AnchorPoint = Vector2.new(1, 0.5)
				object.Position = UDim2.fromScale(1, 0.5)

				return object
			end)(),
		}),
	})
end

-- the VIP window's backdrop: fades in from the left, torn right edge
local function buildPanel()
	return make("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(STAGE.X - 24 - 800, 0),
		Size = UDim2.fromOffset(800, STAGE.Y),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
	}, {
		make("UIGradient", {
			Transparency = numbers({ { 0, 1 }, { 0.26, 1 }, { 0.44, 0 }, { 1, 0 } }),
		}),

		make("ImageLabel", {
			Name = "TornEdge",
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 10, 1, 0),
			BackgroundTransparency = 1,
			Image = TORN_EDGE,
			ImageColor3 = BLACK,
			ImageTransparency = 0.8,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(10, 420),
		}),
	})
end

local function buildMapView()
	return make("Frame", {
		Name = "MapView",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		buildPanel(),
		buildInfo(),
		buildBrowser(),
	})
end

----

local function chipTemplate()
	return make("Frame", {
		Name = "PlatformChip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		make("UICorner", { CornerRadius = UDim.new(0, 3) }),
		make("UIStroke", { Name = "Stroke", Color = BONE, Transparency = 0.7, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		list(Enum.FillDirection.Horizontal, 5, { VerticalAlignment = Enum.VerticalAlignment.Center }),

		make("ImageLabel", {
			Name = "Icon",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Image = "",
			ImageColor3 = BONE,
			Visible = false,
		}),

		make("TextLabel", {
			Name = "Label",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 12,
			TextColor3 = BONE,
			RichText = true,
			Text = "",
		}),
	})
end

local function statTemplate()
	return make("Frame", {
		Name = "StatItem",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		list(Enum.FillDirection.Vertical, 2),

		text("Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16) }, {
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 12,
			TextColor3 = BONE,
			TextTransparency = 0.55,
			Size = UDim2.fromOffset(0, 16),
			Text = "",
		}, 1),

		text("Value", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 26) }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 21,
			TextColor3 = BONE,
			Size = UDim2.fromOffset(0, 26),
			Text = "",
		}, 2),
	})
end

local function cardTemplate()
	return make("Frame", {
		Name = "MapCard",
		Size = UDim2.fromOffset(380, 520),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		make("UIStroke", { Name = "Stroke", Color = Color3.fromRGB(98, 94, 90), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		shadow(0.5),

		make("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 1,
		}, {
			make("ImageLabel", {
				Name = "Art",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Crop,
				Image = "",
				ZIndex = 1,
			}),

			make("Frame", {
				Name = "Fade",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(12, 12, 12),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				make("UIGradient", {
					Rotation = 90,
					Transparency = numbers({ { 0, 1 }, { 0.45, 1 }, { 1, 0.05 } }),
				}),
			}),
		}),

		text("Title", { Position = UDim2.new(0, 24, 1, -128), Size = UDim2.new(1, -48, 0, 44), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextScaled = true,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			RichText = true,
			Text = "",
		}, 4),

		text("Online", { Position = UDim2.new(0, 24, 1, -80), Size = UDim2.new(1, -48, 0, 28), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = GREY,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 2),

		make("Frame", {
			Name = "Platforms",
			Position = UDim2.new(0, 24, 1, -44),
			Size = UDim2.new(1, -48, 0, 24),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
		}),

		make("Frame", {
			Name = "ComingSoon",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
		}, {
			text("Label", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.new(1, 0, 0, 30),
			}, {
				FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
				TextSize = 24,
				TextColor3 = BONE,
				TextTransparency = 0.3,
				Text = "C O M I N G   S O O N",
			}, 2),
		}),

		highlight(),
		hitbox(),
	})
end

local function rowTemplate()
	local function cell(name, position, size, props, offset)
		props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
		props.Text = ""

		return text(name, { Position = position, Size = size, ZIndex = 2 }, props, offset)
	end

	return make("ImageButton", {
		Name = "ServerRow",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
	}, {
		-- fades in from the left like the game's player-list slots
		make("UIGradient", {
			Transparency = numbers({ { 0, 1 }, { 0.082, 0.681 }, { 0.262, 0.244 }, { 1, 0 } }),
		}),
		make("UICorner", { CornerRadius = UDim.new(0, 2) }),
		make("UIStroke", { Name = "Stroke", Color = Color3.fromRGB(62, 67, 68), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Enabled = false }),

		cell("Server", UDim2.fromOffset(14, 4), UDim2.new(1, -350, 0, 26), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 20,
			TextColor3 = BONE,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 2),

		cell("Id", UDim2.fromOffset(14, 30), UDim2.new(1, -350, 0, 16), {
			FontFace = font(Enum.FontWeight.Regular),
			TextSize = 13,
			TextColor3 = BONE,
			TextTransparency = 0.58,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 1),

		cell("Region", UDim2.new(1, -328, 0, 0), UDim2.new(0, 110, 1, 0), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 16,
			TextColor3 = BONE,
			TextTransparency = 0.3,
		}, 2),

		cell("Uptime", UDim2.new(1, -206, 0, 0), UDim2.new(0, 90, 1, 0), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 16,
			TextColor3 = BONE,
			TextTransparency = 0.3,
		}, 2),

		cell("Players", UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 20,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, 2),

		highlight(),
	})
end

----

local existing = replicatedFirst:FindFirstChild("Lobby")

if existing then
	existing:Destroy()
end

-- the gui keeps clear of Roblox's own buttons; the client stretches just the
-- Background back out to the whole screen
make("ScreenGui", {
	Name = "Lobby",
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = replicatedFirst,
}, {
	buildBackground(),

	-- everything else is laid out at 1440x810; the client sets Scale to fit
	make("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STAGE.X, STAGE.Y),
		BackgroundTransparency = 1,
	}, {
		make("UIScale", { Name = "Scale" }),

		buildPicker(),
		buildMapView(),

		text("Status", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(600, 30),
			Visible = false,
		}, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			Text = "",
		}, 2),
	}),

	-- a Folder doesn't stop its GuiObjects rendering, so the templates are
	-- hidden and the client shows its clones
	make("Folder", { Name = "Templates" }, {
		cardTemplate(),
		rowTemplate(),
		statTemplate(),
		chipTemplate(),

		-- gamepad selection ring, same art as the hover highlight
		(function()
			local object = highlight()
			object.Name = "Selection"

			return object
		end)(),
	}),
})

print("Lobby UI built")
