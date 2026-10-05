-- Builds ReplicatedFirst.Lobby in the open place. Paste into the Studio command bar.
-- Destroys and rebuilds Lobby if it exists; hand edits made in Studio are lost,
-- except Lobby.Background, which is kept as is (it's the game's menu backdrop,
-- art-directed in Studio). REBUILD_ONLY below swaps in just the named pieces
-- (Picker, ModeView, Dropdown, Invite, Templates) and keeps everything else.
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

-- nil rebuilds everything. { "Picker", "ModeView", "Dropdown", "Invite", "Templates" }
-- keeps the Lobby that's there and only replaces Stage.Picker, Stage.ModeView,
-- Stage.Dropdown (and its shield), Stage.Invite and the private-server
-- templates, so hand edits elsewhere survive; drop a name to leave that part
-- alone too
local REBUILD_ONLY = nil

local OSWALD = "rbxassetid://12187372847"
local SOURCE_SANS = "rbxasset://fonts/families/SourceSansPro.json"

local BONE = Color3.fromRGB(229, 226, 219)
local GOLD = Color3.fromRGB(202, 188, 131)
-- Play's gold, brighter than the game's so the main action stands out
local PLAY_GOLD = Color3.fromRGB(236, 210, 120)
local GREY = Color3.fromRGB(177, 177, 177)
local PANEL = Color3.fromRGB(27, 27, 27)
local NAV = Color3.fromRGB(18, 18, 21) -- the game's nav bar
local EDGE = Color3.fromRGB(98, 94, 90) -- the game's floating-panel outline
local AMBER = Color3.fromRGB(227, 166, 74) -- warnings, Kick
local BLOCKED = Color3.fromRGB(214, 92, 74) -- the blocked-platform red, Ban
local BLACK = Color3.new(0, 0, 0)

local SHADOW = "rbxassetid://1677877208"
local HIGHLIGHT = "rbxassetid://6116907099"
local GRUNGE = "rbxassetid://104544475726279"
local TORN_EDGE = "rbxassetid://129891927624984"
local BACK_ICON = "rbxassetid://90333380641559"
local TOGGLE_ICON = "rbxassetid://5912368763" -- the host's settings/teams switch
-- the game's loading-screen logo, 892x292; its drop shadow is baked into
-- the asset, a UIShadow blurs badly on it
local LOGO = "rbxassetid://81852070951145"

local STAGE = Vector2.new(1440, 810)

-- the game's header spacing (its spaceOut): a hair space (U+200A) between
-- every character, so words end up split by hair, space, hair. Full spaces
-- look far too wide
local HAIR = utf8.char(0x200A)

local function spaced(text)
	local characters = {}

	for _, code in utf8.codes(text:upper()) do
		table.insert(characters, utf8.char(code))
	end

	return table.concat(characters, HAIR)
end

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

-- a real drop shadow under the soft halo, so floating things sit off the
-- background: deep for cards and the preview, shallow for buttons and chips
local function lift(deep)
	return make("UIShadow", {
		Name = "DropShadow",
		Color = BLACK,
		Transparency = deep and 0.4 or 0.55,
		BlurRadius = UDim.new(0, deep and 28 or 12),
		Offset = UDim2.fromOffset(0, deep and 10 or 4),
		Spread = UDim2.new(),
	})
end

-- a scrolling frame inside a CanvasGroup, the game's trick for lists that
-- fade into the background at their edges; the client drives the UIGradient
-- as it scrolls. props place the group; the frame fills it
local function edgeFade(props, scroller)
	props.Name = "EdgeFade"
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0

	scroller.AnchorPoint = Vector2.zero
	scroller.Position = UDim2.new()
	scroller.Size = UDim2.fromScale(1, 1)

	return make("CanvasGroup", props, { make("UIGradient", {}), scroller })
end

-- the highlight's line sits ~13px inside its edge; small things pass a
-- smaller sliceScale or the line lands in the middle of them
local function highlight(sliceScale)
	return make("ImageLabel", {
		Name = "HighlightBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 10, 1, 10),
		BackgroundTransparency = 1,
		Image = HIGHLIGHT,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(13, 13, 13, 13),
		SliceScale = sliceScale or 1,
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
		lift(),
		content,
		highlight(),
		hitbox(),
	})
end

-- gold by default; pass BONE for the plain white ones (Join, the card's Play)
local function textButton(name, size, label, color)
	color = color or GOLD

	return button(name, size, color, color == BONE and BONE or Color3.fromRGB(255, 193, 138), text("Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 0.8),
		ZIndex = 3,
	}, {
		FontFace = font(Enum.FontWeight.Heavy),
		TextScaled = true,
		TextColor3 = color,
		Text = label,
	}, 4))
end

local function iconButton(name, icon)
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
		-- no icon art: a ring with a gap, drawn so it doesn't depend on a font
		content = make("Frame", {
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			make("Frame", {
				Name = "Ring",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.42, 0.42),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, {
				make("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				make("UIStroke", { Color = BONE, Thickness = 3 }, {
					make("UIGradient", {
						Rotation = 45,
						Transparency = numbers({ { 0, 0 }, { 0.62, 0 }, { 0.63, 1 }, { 1, 1 } }),
					}),
				}),
			}),
		})
	end

	return button(name, UDim2.fromOffset(60, 60), BONE, BONE, content)
end

-- shown next to Play for maps that need a password
local function passwordField()
	return make("Frame", {
		Name = "Password",
		Size = UDim2.fromOffset(136, 60),
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
		lift(),

		make("TextBox", {
			Name = "Input",
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, -24, 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 18,
			TextColor3 = BONE,
			PlaceholderText = spaced("Password"),
			PlaceholderColor3 = Color3.fromRGB(120, 118, 114),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			ZIndex = 3,
		}),

		highlight(),
	})
end

-- filters the server list as you type (name, id, region or host)
local function searchField()
	return make("Frame", {
		Name = "Search",
		Position = UDim2.fromOffset(0, 58),
		Size = UDim2.fromOffset(300, 32),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Transparency = 0.6,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		lift(),

		make("TextBox", {
			Name = "Input",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 15,
			TextColor3 = BONE,
			PlaceholderText = spaced("Search"),
			PlaceholderColor3 = Color3.fromRGB(120, 118, 114),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			ZIndex = 3,
		}),
	})
end

-- Play and PlayPool keep their width until the row runs out, then shrink
-- evenly to share it. Their labels get side room so a long one ("PLAY
-- CONSOLE") doesn't scale up against the stroke when the row is shared
local function flexible(object)
	make("UIFlexItem", { FlexMode = Enum.UIFlexMode.Shrink, Parent = object })
	object.Label.Size = UDim2.new(1, -40, 0.62, 0)

	return object
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

-- the lobby's backdrop: the game's main menu one (MainMenu.Master.Background)
-- as art-directed in Studio. Only used when the place doesn't have one; keep
-- it in step with the place's copy when that's edited
local function buildBackground()
	local function grit(name, image, anchor, scale, transparency, zIndex)
		return make("ImageLabel", {
			Name = name,
			AnchorPoint = anchor,
			Position = UDim2.fromScale(anchor.X, anchor.Y),
			Size = UDim2.fromScale(scale, scale),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = BLACK,
			ImageTransparency = transparency,
			ZIndex = zIndex,
		}, {
			make("UISizeConstraint", { MaxSize = Vector2.new(1024, 1024) }),
		})
	end

	return make("Frame", {
		Name = "Background",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(61, 61, 61),
		BorderSizePixel = 0,
	}, {
		make("Frame", {
			Name = "GradientDrop",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 1,
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
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 2,
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

		-- the game fades this photo in at runtime; the lobby leaves it hidden
		make("ImageLabel", {
			Name = "BackdropImage",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://103463374121990",
			ImageColor3 = Color3.fromRGB(156, 156, 156),
			ImageTransparency = 1,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 1,
		}),

		make("ImageLabel", {
			Name = "ContentBackdrop",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://131272931454517",
			ImageColor3 = Color3.fromRGB(61, 61, 61),
			ImageTransparency = 0.3,
			ZIndex = 3,
		}, {
			make("UIGradient", {
				Color = colors({
					{ 0, Color3.fromRGB(100, 100, 100) },
					{ 0.5, Color3.fromRGB(102, 100, 86) },
					{ 1, Color3.fromRGB(50, 50, 50) },
				}),
				Transparency = numbers({ { 0, 0.5 }, { 0.135632, 0.33125 }, { 0.864, 0.331 }, { 1, 0.5 } }),
			}),
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
			Name = "Grit",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, {
			grit("BottomRight2", "rbxassetid://83808700820268", Vector2.new(1, 1), 1, 0, 3),
			grit("BottomLeft2", "rbxassetid://97071793107351", Vector2.new(0, 1), 1, 0, 3),
			grit("BottomRight1", "rbxassetid://111332206534538", Vector2.new(1, 1), 0.7, 0.79, 2),
			grit("BottomLeft1", "rbxassetid://123577345537370", Vector2.new(0, 1), 0.7, 0.79, 2),
		}),
	})
end

----

local function buildPicker()
	-- the bottom screen: under MapView and ModeView whatever the child order
	return make("Frame", {
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 0,
	}, {
		-- the game's logo, top right, well away from Roblox's buttons in the
		-- top-left corner
		make("ImageLabel", {
			Name = "Logo",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -64, 0, 20),
			Size = UDim2.fromOffset(244, 80),
			BackgroundTransparency = 1,
			Image = LOGO,
			ScaleType = Enum.ScaleType.Fit,
		}),

		edgeFade({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, -10),
			Size = UDim2.new(1, 0, 0, 560),
		}, make("ScrollingFrame", {
			Name = "Maps",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ScrollingDirection = Enum.ScrollingDirection.X,
			-- a thin bar under the cards, shown once there are more maps than fit
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = BONE,
			ScrollBarImageTransparency = 0.6,
			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
		}, {
			-- left-aligned: the client centres the row with the padding while
			-- it fits (centring here would push overflowing cards out of reach)
			list(Enum.FillDirection.Horizontal, 27, {
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			make("UIPadding", {
				PaddingLeft = UDim.new(0, 64),
				PaddingRight = UDim.new(0, 64),
			}),
		})),

		-- the hub pages, a static footer under the row (Status sits below it)
		make("Frame", {
			Name = "Footer",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -64),
			Size = UDim2.new(1, -128, 0, 45),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 12, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
			ordered(textButton("Friends", UDim2.fromOffset(240, 45), "FIND FRIENDS", PLAY_GOLD), 1),
			ordered(textButton("News", UDim2.fromOffset(170, 45), "NEWS", BONE), 2),
			ordered(textButton("Events", UDim2.fromOffset(170, 45), "EVENTS", BONE), 3),
		}),
	})
end

local function spacer(order, height)
	return make("Frame", {
		Name = "Spacer" .. order,
		LayoutOrder = order,
		Size = UDim2.fromOffset(1, height),
		BackgroundTransparency = 1,
	})
end

-- the top of an Info column: Title, Counts and Blurb, shared by the map and
-- mode views so they read the same
local function infoHeader()
	return {
		text("Title", { LayoutOrder = 1, Size = UDim2.fromOffset(600, 70) }, {
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
			Size = UDim2.fromOffset(600, 38),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 14, { VerticalAlignment = Enum.VerticalAlignment.Bottom }),

			text("Online", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 38) }, {
				FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
				TextSize = 30,
				TextColor3 = GREY,
				Size = UDim2.fromOffset(0, 38),
				Text = "",
			}, 2),

			text("Servers", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 32) }, {
				FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
				TextSize = 23,
				TextColor3 = BONE,
				TextTransparency = 0.45,
				Size = UDim2.fromOffset(0, 32),
				Text = "",
			}, 2),
		}),

		text("Blurb", { LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.fromOffset(580, 0) }, {
			FontFace = Font.new(SOURCE_SANS, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
			TextSize = 21,
			TextColor3 = BONE,
			TextTransparency = 0.3,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.fromOffset(580, 0),
			Text = "",
		}, 2),
	}
end

-- the slideshow box; the client's slideshow adds its viewports to Clip (ZIndex 1-2)
local function buildPreview(order)
	return make("Frame", {
		Name = "Preview",
		LayoutOrder = order,
		Size = UDim2.fromOffset(600, 338),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
	}, {
		shadow(0.5),
		lift(true),

		make("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = PANEL,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 1,
		}, {
			make("UIStroke", {
				Color = EDGE,
				Thickness = 2,
				LineJoinMode = Enum.LineJoinMode.Miter,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),


			-- keeps the picker readable on bright shots
			make("Frame", {
				Name = "Shade",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 56),
				BackgroundColor3 = BLACK,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, {
				make("UIGradient", {
					Rotation = 90,
					Transparency = numbers({ { 0, 1 }, { 1, 0.45 } }),
				}),
			}),

			-- one PreviewDot per image, made by the client
			make("Frame", {
				Name = "Dots",
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -6),
				Size = UDim2.new(1, -24, 0, 26),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, {
				list(Enum.FillDirection.Horizontal, 2, {
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
			}),
		}),
	})
end

local function buildInfo()
	return make("Frame", {
		Name = "Info",
		Position = UDim2.fromOffset(64, 40),
		Size = UDim2.fromOffset(600, 740),
		BackgroundTransparency = 1,
	}, {
		list(Enum.FillDirection.Vertical, 10),
		infoHeader(),

		make("Frame", {
			Name = "Stats",
			LayoutOrder = 4,
			Size = UDim2.fromOffset(600, 52),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 30),
		}),

		make("Frame", {
			Name = "Platforms",
			LayoutOrder = 5,
			Size = UDim2.fromOffset(600, 26),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
		}),

		text("Notice", { LayoutOrder = 6, Size = UDim2.fromOffset(600, 22), Visible = false }, {
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 17,
			TextColor3 = Color3.fromRGB(227, 166, 74),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 1),

		spacer(7, 4),
		buildPreview(8),
		spacer(9, 6),

		make("Frame", {
			Name = "Buttons",
			LayoutOrder = 10,
			Size = UDim2.fromOffset(600, 60),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 12),
			ordered(iconButton("Back", BACK_ICON), 1),
			ordered(flexible(textButton("Play", UDim2.fromOffset(355, 60), "PLAY", PLAY_GOLD)), 2),
			-- this platform's own servers; the client shows it where there are some
			(function()
				local object = ordered(flexible(textButton("PlayPool", UDim2.fromOffset(355, 60), "PLAY CONSOLE", PLAY_GOLD)), 3)
				object.Visible = false

				return object
			end)(),
			ordered(passwordField(), 4),
		}),
	})
end

-- fixed width: an auto-sized chip grows to fit its highlight when that shows
local function sortChip(name, label, order, width)
	return make("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(width, 30),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Transparency = 0.8,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		lift(),

		make("TextLabel", {
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 14,
			TextColor3 = BONE,
			TextTransparency = 0.5,
			Text = label,
			ZIndex = 2,
		}),

		highlight(0.45),
		hitbox(),
	})
end

-- a sortChip at another size, for the small row chips (Join, Kick, Ban) and
-- the settings value; order 0 for ones placed by hand
local function chip(name, label, width, height, textSize, order)
	local object = sortChip(name, label, order or 0, width)
	object.Size = UDim2.fromOffset(width, height)
	object.Label.TextSize = textSize

	return object
end

local function column(name, label, position, size, align)
	return make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		FontFace = font(Enum.FontWeight.SemiBold),
		TextSize = 13,
		TextColor3 = BONE,
		TextTransparency = 0.55,
		TextXAlignment = align or Enum.TextXAlignment.Left,
		Text = label,
	})
end

-- the browser's row list, for an edgeFade: bare scroller, 4px between rows.
-- extra goes to the list layout (the panes right-align their rows)
local function listScroller(extra)
	return make("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 0,
		ScrollBarImageTransparency = 1,
	}, {
		list(Enum.FillDirection.Vertical, 4, extra),

		-- room for the highlight box, which overhangs rows by 5px
		make("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
		}),
	})
end

local function emptyText(label)
	return text("Empty", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 200),
		Size = UDim2.fromOffset(400, 30),
		Visible = false,
	}, {
		FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
		TextSize = 22,
		TextColor3 = BONE,
		TextTransparency = 0.5,
		Text = label,
	}, 2)
end

-- the picked row's name and details, with Join on the right
local function buildFooter()
	return make("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 80),
		BackgroundTransparency = 1,
	}, {
		text("ServerName", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, -230, 0, 38) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 32,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, 4),

		text("Meta", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, -230, 0, 24) }, {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			RichText = true, -- an outdated version shows in amber
			Text = "",
		}, 2),

		(function()
			local object = textButton("Join", UDim2.fromOffset(200, 60), "JOIN", BONE)
			object.AnchorPoint = Vector2.new(1, 0.5)
			object.Position = UDim2.fromScale(1, 0.5)

			return object
		end)(),
	})
end

local function buildBrowser()
	return make("Frame", {
		Name = "Browser",
		Position = UDim2.fromOffset(704, 52),
		Size = UDim2.fromOffset(STAGE.X - 48 - 704, 710),
		BackgroundTransparency = 1,
	}, {
		text("Heading", { Size = UDim2.fromOffset(320, 50) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 44,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = spaced("Servers"),
		}, 4),

		make("Frame", {
			Name = "Sorts",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 10),
			Size = UDim2.fromOffset(340, 30),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
			sortChip("Players", "PLAYERS", 1, 96),
			sortChip("Newest", "NEWEST", 2, 88),
			sortChip("Region", "REGION", 3, 88),
		}),

		searchField(),

		-- only your platform's own servers; hidden on PC
		(function()
			local object = sortChip("Filter", "CONSOLE ONLY", 0, 150)
			object.AnchorPoint = Vector2.new(1, 0)
			object.Position = UDim2.new(1, 0, 0, 59)
			object.Visible = false

			return object
		end)(),

		-- same offsets as ServerRow's cells, inside the list's 6px padding
		make("Frame", {
			Name = "Columns",
			Position = UDim2.fromOffset(6, 100),
			Size = UDim2.new(1, -12, 0, 18),
			BackgroundTransparency = 1,
		}, {
			column("Server", spaced("Server"), UDim2.fromOffset(14, 0), UDim2.new(1, -410, 1, 0)),
			column("Region", spaced("Region"), UDim2.new(1, -386, 0, 0), UDim2.new(0, 170, 1, 0)),
			column("Uptime", spaced("Uptime"), UDim2.new(1, -206, 0, 0), UDim2.new(0, 90, 1, 0)),
			column("Players", spaced("Players"), UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), Enum.TextXAlignment.Right),
		}),

		edgeFade({
			Position = UDim2.fromOffset(0, 124),
			Size = UDim2.new(1, 0, 1, -124 - 96),
		}, listScroller()),

		emptyText(spaced("No Servers")),
		buildFooter(),
	})
end

-- the VIP window's backdrop: fades in from the left, torn right edge. Darker
-- than the game's so the server list reads over busy map art. It starts
-- under the preview and eases in slowly, solid by the list's left edge (704)
local function buildPanel()
	return make("Frame", {
		Name = "Panel",
		Position = UDim2.fromOffset(380, 28),
		Size = UDim2.fromOffset(STAGE.X - 24 - 380, STAGE.Y - 56),
		BackgroundColor3 = NAV,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, {
		make("UIGradient", {
			Transparency = numbers({ { 0, 1 }, { 0.08, 0.93 }, { 0.16, 0.72 }, { 0.24, 0.35 }, { 0.31, 0 }, { 1, 0 } }),
		}),

		make("ImageLabel", {
			Name = "TornEdge",
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 10, 1, 0),
			BackgroundTransparency = 1,
			Image = TORN_EDGE,
			ImageColor3 = NAV,
			ImageTransparency = 0.25,
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

-- the mode view's one gold action: auto-width, a plus drawn from two bars so
-- it doesn't depend on icon art
local function inviteChip()
	local object = sortChip("Invite", "INVITE", 5, 104)
	object.Stroke.Color = GOLD
	object.Stroke.Transparency = 0.4
	object.Label.TextColor3 = GOLD
	object.Label.TextTransparency = 0.1
	-- the label leaves room for the plus on its left
	object.Label.Position = UDim2.fromOffset(12, 0)
	object.Label.Size = UDim2.new(1, -12, 1, 0)

	local function bar(name, width, height)
		return make("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(width, height),
			BackgroundColor3 = GOLD,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end

	-- a plus drawn from two bars, so it needs no icon art
	make("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = object,
	}, {
		bar("Across", 12, 2),
		bar("Down", 2, 12),
	})

	return object
end

local function buildModeInfo()
	return make("Frame", {
		Name = "Info",
		Position = UDim2.fromOffset(64, 40),
		Size = UDim2.fromOffset(600, 740),
		BackgroundTransparency = 1,
	}, {
		list(Enum.FillDirection.Vertical, 10),
		infoHeader(),

		make("Frame", {
			Name = "Platforms",
			LayoutOrder = 4,
			Size = UDim2.fromOffset(600, 26),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
		}),

		-- who can join the host's session; the client shows it to the host
		make("Frame", {
			Name = "Visibility",
			LayoutOrder = 5,
			Size = UDim2.fromOffset(600, 30),
			BackgroundTransparency = 1,
			Visible = false,
		}, {
			list(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
			sortChip("Private", "PRIVATE", 1, 96),
			sortChip("Friends", "FRIENDS", 2, 96),
			sortChip("Public", "PUBLIC", 3, 96),

			make("Frame", {
				Name = "Divider",
				LayoutOrder = 4,
				Size = UDim2.fromOffset(2, 22),
				BackgroundColor3 = BONE,
				BackgroundTransparency = 0.8,
				BorderSizePixel = 0,
			}),

			inviteChip(),
		}),

		spacer(6, 4),
		buildPreview(7),
		spacer(8, 6),

		make("Frame", {
			Name = "Buttons",
			LayoutOrder = 9,
			Size = UDim2.fromOffset(600, 60),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 12),
			ordered(iconButton("Back", BACK_ICON), 1),
			ordered(flexible(textButton("Primary", UDim2.fromOffset(355, 60), "HOST A MATCH", PLAY_GOLD)), 2),
			-- the host's settings/teams switch; smaller art than Back's, so it's inset
			(function()
				local object = ordered(iconButton("Toggle", TOGGLE_ICON), 3)
				object.Icon.AnchorPoint = Vector2.new(0.5, 0.5)
				object.Icon.Position = UDim2.fromScale(0.5, 0.5)
				object.Icon.Size = UDim2.fromScale(0.6, 0.6)
				object.Visible = false

				return object
			end)(),
		}),
	})
end

-- the session browser: the Browser's layout with lobby columns
local function buildLobbies()
	return make("Frame", {
		Name = "Lobbies",
		Position = UDim2.fromOffset(704, 52),
		Size = UDim2.fromOffset(STAGE.X - 48 - 704, 710),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		text("Heading", { Size = UDim2.fromOffset(320, 50) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 44,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = spaced("Lobbies"),
		}, 4),

		make("Frame", {
			Name = "Filters",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 10),
			Size = UDim2.fromOffset(300, 30),
			BackgroundTransparency = 1,
		}, {
			list(Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
			sortChip("Friends", "FRIENDS", 1, 96),
			sortChip("Public", "PUBLIC", 2, 96),
			sortChip("Open", "OPEN", 3, 88),
		}),

		searchField(),

		-- same offsets as SessionRow's cells, inside the list's 6px padding
		make("Frame", {
			Name = "Columns",
			Position = UDim2.fromOffset(6, 100),
			Size = UDim2.new(1, -12, 0, 18),
			BackgroundTransparency = 1,
		}, {
			column("Host", spaced("Host"), UDim2.fromOffset(14, 0), UDim2.new(1, -300, 1, 0)),
			column("Access", spaced("Access"), UDim2.new(1, -290, 0, 0), UDim2.new(0, 120, 1, 0)),
			column("Players", spaced("Players"), UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), Enum.TextXAlignment.Right),
		}),

		edgeFade({
			Position = UDim2.fromOffset(0, 124),
			Size = UDim2.new(1, 0, 1, -124 - 96),
		}, listScroller()),

		emptyText(spaced("No Lobbies")),
		buildFooter(),
	})
end

-- a right-hand pane the client fills with template clones (all 460 wide),
-- kept against the right edge so they line up under each other
local function buildPane(name)
	return make("Frame", {
		Name = name,
		Position = UDim2.fromOffset(704, 52),
		Size = UDim2.fromOffset(STAGE.X - 48 - 704, 710),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		edgeFade({
			Size = UDim2.fromScale(1, 1),
		}, listScroller({ HorizontalAlignment = Enum.HorizontalAlignment.Right })),
	})
end

-- the private-server screen: a mode's info on the left, one of four panes on
-- the right (the client shows one at a time)
local function buildModeView()
	return make("Frame", {
		Name = "ModeView",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		buildPanel(),
		buildModeInfo(),
		buildLobbies(),
		buildPane("Roster"),
		buildPane("Config"),
		buildPane("Server"),
	})
end

-- the settings menu: the client parks it under the chip that opened it and
-- fills it with DropdownItem clones. Above every screen
local function buildDropdown()
	return make("Frame", {
		Name = "Dropdown",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(170, 0),
		BackgroundColor3 = Color3.fromRGB(12, 12, 12),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Transparency = 0.45,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		lift(true),
		list(Enum.FillDirection.Vertical, 0),
	})
end

-- a clear button over the whole stage, just under the dropdown: pressing
-- anywhere else closes it
-- an invite from a friend in another (or this) lobby server, above the
-- status line: who and to what, with accept and dismiss
local function buildInvite()
	return make("Frame", {
		Name = "Invite",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -56),
		Size = UDim2.fromOffset(700, 64),
		-- solid: it has to read over whatever's behind it
		BackgroundColor3 = NAV,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 40,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = GOLD,
			Transparency = 0.4,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		lift(true),

		text("Text", { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -236, 1, 0), ZIndex = 41 }, {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 20,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, 2),

		(function()
			local chip = sortChip("Accept", "ACCEPT", 1, 100)
			chip.AnchorPoint = Vector2.new(1, 0.5)
			chip.Position = UDim2.new(1, -120, 0.5, 0)
			chip.ZIndex = 41
			chip.Stroke.Color = GOLD
			chip.Stroke.Transparency = 0.3
			chip.Label.TextColor3 = GOLD
			chip.Label.TextTransparency = 0

			return chip
		end)(),

		(function()
			local chip = sortChip("Dismiss", "DISMISS", 2, 100)
			chip.AnchorPoint = Vector2.new(1, 0.5)
			chip.Position = UDim2.new(1, -12, 0.5, 0)
			chip.ZIndex = 41

			return chip
		end)(),
	})
end

local function buildDropdownShield()
	return make("ImageButton", {
		Name = "DropdownShield",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
		ZIndex = 49,
	})
end

----

local function chipTemplate()
	return make("Frame", {
		Name = "PlatformChip",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		-- only shown on the chip for the platform you're on
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Transparency = 1,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		lift(),
		make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
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
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 13,
			TextColor3 = BONE,
			RichText = true,
			Text = "",
		}),
	})
end

-- a thin bar with a finger-sized hit area around it
local function dotTemplate()
	return make("ImageButton", {
		Name = "PreviewDot",
		Size = UDim2.fromOffset(40, 26),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
		ZIndex = 5,
	}, {
		make("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(30, 4),
			BackgroundColor3 = BONE,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			ZIndex = 5,
		}),
	})
end

local function statTemplate()
	return make("Frame", {
		Name = "StatItem",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 52),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		list(Enum.FillDirection.Vertical, 2),

		text("Label", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 18) }, {
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 14,
			TextColor3 = BONE,
			TextTransparency = 0.55,
			Size = UDim2.fromOffset(0, 18),
			Text = "",
		}, 1),

		text("Value", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 30) }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 24,
			TextColor3 = BONE,
			Size = UDim2.fromOffset(0, 30),
			Text = "",
		}, 2),
	})
end

local function cardTemplate()
	return make("Frame", {
		Name = "MapCard",
		Size = UDim2.fromOffset(405, 480),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = EDGE,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		shadow(0.5),
		lift(true),

		make("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 1,
		}, {
			-- the client's slideshow adds its viewports here (ZIndex 0-1), under the Fade
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

		(function()
			local object = text("Title", { Position = UDim2.new(0, 21, 1, -170), Size = UDim2.new(1, -42, 0, 46), ZIndex = 2 }, {
				FontFace = font(Enum.FontWeight.Heavy),
				TextScaled = true,
				TextColor3 = BONE,
				TextXAlignment = Enum.TextXAlignment.Left,
				RichText = true,
				Text = "",
			}, 4)

			-- a heavier shadow than elsewhere: the card art runs bright behind it
			object.Shadow.TextTransparency = 0.5

			return object
		end)(),

		text("Online", { Position = UDim2.new(0, 21, 1, -114), Size = UDim2.new(1, -42, 0, 26), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = GREY,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 2),

		-- the map's Tags, filled from Templates.Tag
		make("Frame", {
			Name = "Tags",
			Position = UDim2.new(0, 21, 1, -80),
			Size = UDim2.new(1, -42, 0, 24),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
		}),

		make("Frame", {
			Name = "Platforms",
			Position = UDim2.new(0, 21, 1, -46),
			Size = UDim2.new(1, -42, 0, 26),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			list(Enum.FillDirection.Horizontal, 8),
			-- the shared chips, drawn a little smaller so five clear Play
			make("UIScale", { Scale = 0.85 }),
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
				Text = spaced("Coming Soon"),
			}, 2),
		}),

		highlight(),
		hitbox(),

		-- a glow round the card; the client enables it with the highlight box
		make("UIShadow", {
			Name = "HighlightShadow",
			Color = Color3.fromRGB(252, 255, 159),
			Transparency = 0.72,
			BlurRadius = UDim.new(0, 20),
			Offset = UDim2.new(),
			Spread = UDim2.new(),
			Enabled = false,
		}),

		-- one tap into a game, over the card's own hitbox
		(function()
			local object = textButton("Play", UDim2.fromOffset(126, 45), "PLAY", BONE)
			object.AnchorPoint = Vector2.new(1, 1)
			object.Position = UDim2.new(1, -21, 1, -20)
			object.ZIndex = 11
			object.Visible = false

			return object
		end)(),
	})
end

local function tagTemplate()
	return make("Frame", {
		Name = "Tag",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BONE,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		lift(),
		make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),

		make("TextLabel", {
			Name = "Label",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.Bold),
			TextSize = 13,
			TextColor3 = BONE,
			Text = "",
		}),
	})
end

-- a row cell: a text box the client fills, left aligned unless told otherwise
local function cell(name, position, size, props, offset)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.Text = ""

	return text(name, { Position = position, Size = size, ZIndex = 2 }, props, offset)
end

-- fades in from the left like the game's player-list slots
local function rowFade()
	return make("UIGradient", {
		Transparency = numbers({ { 0, 1 }, { 0.082, 0.681 }, { 0.262, 0.244 }, { 1, 0 } }),
	})
end

-- off until the client marks the row (picked, or the one you're in)
local function rowStroke()
	return make("UIStroke", {
		Name = "Stroke",
		Color = EDGE,
		Thickness = 2,
		LineJoinMode = Enum.LineJoinMode.Miter,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Enabled = false,
	})
end

local function rowTemplate()
	return make("ImageButton", {
		Name = "ServerRow",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = BONE,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
	}, {
		rowFade(),
		rowStroke(),

		cell("Server", UDim2.fromOffset(14, 5), UDim2.new(1, -410, 0, 28), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 2),

		cell("Id", UDim2.fromOffset(14, 34), UDim2.new(1, -410, 0, 18), {
			FontFace = font(Enum.FontWeight.Regular),
			TextSize = 15,
			TextColor3 = BONE,
			TextTransparency = 0.58,
			TextTruncate = Enum.TextTruncate.AtEnd,
			RichText = true, -- an outdated version shows in amber
		}, 1),

		cell("Region", UDim2.new(1, -386, 0, 0), UDim2.new(0, 170, 1, 0), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.3,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 2),

		cell("Uptime", UDim2.new(1, -206, 0, 0), UDim2.new(0, 90, 1, 0), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.3,
		}, 2),

		cell("Players", UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, 2),

		highlight(),
	})
end

---- private-server templates (the ModeView's clones)

-- a MapCard for a game mode: narrower, no Play, vector art where the map
-- card has a slideshow. Built from the card so the two can't drift apart
local function modeCardTemplate()
	local object = cardTemplate()
	object.Name = "ModeCard"
	object.Size = UDim2.fromOffset(240, 480)
	object.Play:Destroy()

	local function place(child, y, height)
		child.Position = UDim2.new(0, 18, 1, y)
		child.Size = UDim2.new(1, -36, 0, height)
	end

	place(object.Title, -170, 39)
	place(object.Online, -114, 23)
	place(object.Tags, -80, 24)
	place(object.Platforms, -46, 26)
	object.Online.Text.TextSize = 20
	object.Online.Shadow.TextSize = 20

	-- the client sets Image; after Clip so it draws over the Fade
	make("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(165, 165),
		BackgroundTransparency = 1,
		Image = "",
		ImageColor3 = BONE,
		ImageTransparency = 0.86,
		ZIndex = 1,
		Parent = object,
	})

	return object
end

local function sessionRowTemplate()
	return make("ImageButton", {
		Name = "SessionRow",
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = BONE,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
	}, {
		rowFade(),
		rowStroke(),

		-- the host and its tag share a baseline, so the tag follows a name of
		-- any length
		make("Frame", {
			Name = "Line",
			Position = UDim2.fromOffset(14, 5),
			Size = UDim2.new(1, -300, 0, 28),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			list(Enum.FillDirection.Horizontal, 10, { VerticalAlignment = Enum.VerticalAlignment.Bottom }),

			text("Host", { LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28) }, {
				FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
				TextSize = 22,
				TextColor3 = BONE,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Size = UDim2.fromOffset(0, 28),
				Text = "",
			}, 2),

			text("Tag", { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 28) }, {
				FontFace = font(Enum.FontWeight.Bold),
				TextSize = 12,
				TextColor3 = GOLD,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				Size = UDim2.fromOffset(0, 28),
				Text = "",
			}, 1),
		}),

		cell("Detail", UDim2.fromOffset(14, 34), UDim2.new(1, -300, 0, 18), {
			FontFace = font(Enum.FontWeight.Regular),
			TextSize = 15,
			TextColor3 = BONE,
			TextTransparency = 0.58,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 1),

		cell("Access", UDim2.new(1, -290, 0, 0), UDim2.new(0, 120, 1, 0), {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.3,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, 2),

		cell("Players", UDim2.new(1, -104, 0, 0), UDim2.new(0, 90, 1, 0), {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, 2),

		highlight(),
	})
end

-- a pane entry with no background: Readout, TeamHeader, SectionHeading, TeamEdit
local function paneFrame(name, height, children)
	return make("Frame", {
		Name = name,
		Size = UDim2.fromOffset(460, height),
		BackgroundTransparency = 1,
		Visible = false,
	}, children)
end

-- a pane row with the server row's wash: Slot, SettingRow, PlayerRow
local function paneRow(name, height, transparency, stroked, children)
	return make("Frame", {
		Name = name,
		Size = UDim2.fromOffset(460, height),
		BackgroundColor3 = BONE,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		rowFade(),
		stroked and rowStroke() or {},
		children,
	})
end

-- a team's colour, solid on the right and gone by the left; the client tints it
local function band()
	return make("Frame", {
		Name = "Band",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		make("UIGradient", {
			Name = "Fade",
			Transparency = numbers({ { 0, 1 }, { 0.45, 0.55 }, { 1, 0 } }),
		}),
	})
end

-- a chip anchored to the right of a pane row
local function rowChip(name, label, width, height, textSize, inset)
	local object = chip(name, label, width, height, textSize)
	object.AnchorPoint = Vector2.new(1, 0.5)
	object.Position = UDim2.new(1, -inset, 0.5, 0)
	object.ZIndex = 2

	return object
end

-- a coloured chip: the sortChip's washed-out stroke and label would hide the colour
local function tint(object, color)
	object.Stroke.Color = color
	object.Stroke.Transparency = 0.4
	object.Label.TextColor3 = color
	object.Label.TextTransparency = 0.1

	return object
end

-- a big figure with a caption under it
local function readoutTemplate()
	return paneFrame("Readout", 62, {
		text("Big", { Size = UDim2.fromOffset(460, 32) }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 28,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, 2),

		text("Small", { Position = UDim2.fromOffset(0, 34), Size = UDim2.fromOffset(460, 24) }, {
			FontFace = Font.new(SOURCE_SANS, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, 1),
	})
end

local function teamHeaderTemplate()
	return paneFrame("TeamHeader", 42, {
		band(),

		text("Title", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -200, 1, 0), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 30,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 2),

		text("Count", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -84, 0.5, 0),
			Size = UDim2.fromOffset(90, 20),
			ZIndex = 2,
		}, {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 16,
			TextColor3 = BONE,
			TextTransparency = 0.25,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		}, 1),

		rowChip("Join", "JOIN", 66, 26, 13, 8),
	})
end

-- a player's place on a team
local function slotTemplate()
	local kick = tint(rowChip("Kick", "KICK", 56, 22, 12, 6), AMBER)
	kick.Visible = false

	return paneRow("Slot", 30, 0.93, true, {
		text("Player", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.Medium),
			TextSize = 18,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 1),

		kick,
	})
end

local function sectionHeadingTemplate()
	return paneFrame("SectionHeading", 50, {
		text("Title", { Size = UDim2.fromOffset(460, 50) }, {
			FontFace = font(Enum.FontWeight.Heavy),
			TextSize = 36,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = "",
		}, 4),

		text("Note", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.fromOffset(300, 20) }, {
			FontFace = font(Enum.FontWeight.Medium, Enum.FontStyle.Italic),
			TextSize = 18,
			TextColor3 = BONE,
			TextTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 2),
	})
end

-- a setting and its value; the client opens the Dropdown from the chip
local function settingRowTemplate()
	local value = rowChip("Value", "", 170, 28, 16, 4)
	value.Stroke.Transparency = 0.45
	value.Label.FontFace = font(Enum.FontWeight.SemiBold)
	value.Label.TextXAlignment = Enum.TextXAlignment.Left
	value.Label.TextTruncate = Enum.TextTruncate.AtEnd
	value.Label.TextTransparency = 0.1
	-- on the label, not the chip, so the highlight and hitbox keep its full size
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 28), Parent = value.Label })

	-- the back arrow turned to point down
	make("ImageLabel", {
		Name = "Chevron",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundTransparency = 1,
		Image = BACK_ICON,
		ImageColor3 = BONE,
		ImageTransparency = 0.4,
		ScaleType = Enum.ScaleType.Fit,
		Rotation = -90,
		ZIndex = 2,
		Parent = value,
	})

	return paneRow("SettingRow", 30, 0.95, false, {
		text("Label", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -190, 1, 0), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.Medium),
			TextSize = 19,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 1),

		value,
	})
end

-- a team's name and colour, for the host
local function teamEditTemplate()
	return paneFrame("TeamEdit", 72, {
		band(),

		make("Frame", {
			Name = "NameBox",
			Position = UDim2.fromOffset(12, 8),
			Size = UDim2.fromOffset(240, 30),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			make("UIStroke", {
				Name = "Stroke",
				Color = BONE,
				Transparency = 0.5,
				Thickness = 2,
				LineJoinMode = Enum.LineJoinMode.Miter,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),

			make("TextBox", {
				Name = "Input",
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -20, 1, 0),
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				FontFace = font(Enum.FontWeight.Heavy),
				TextSize = 20,
				TextColor3 = BONE,
				PlaceholderText = spaced("Team name"),
				PlaceholderColor3 = Color3.fromRGB(120, 118, 114),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = "",
				ZIndex = 3,
			}),
		}),

		-- filled with Swatch clones
		make("Frame", {
			Name = "Swatches",
			Position = UDim2.fromOffset(12, 46),
			Size = UDim2.new(1, -24, 0, 18),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			list(Enum.FillDirection.Horizontal, 4),
		}),
	})
end

-- a team colour to pick; the client sets the colour and brightens the stroke
-- on the picked one
local function swatchTemplate()
	return make("ImageButton", {
		Name = "Swatch",
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = BLACK,
			Transparency = 0.5,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- grows with its MapTile clones
local function mapTilesTemplate()
	return make("Frame", {
		Name = "MapTiles",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(460, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, {
		make("UIGridLayout", {
			Name = "Grid",
			-- two across: three made the names too small to read
			CellSize = UDim2.fromOffset(226, 110),
			CellPadding = UDim2.fromOffset(8, 8),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		}),
	})
end

-- a map to pick; dimmed until picked, when the client brightens it
local function mapTileTemplate()
	return make("ImageButton", {
		Name = "MapTile",
		Size = UDim2.fromOffset(226, 110),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		ImageColor3 = Color3.fromRGB(150, 150, 150),
		ScaleType = Enum.ScaleType.Crop,
		Visible = false,
	}, {
		make("UIStroke", {
			Name = "Stroke",
			Color = EDGE,
			Transparency = 0.6,
			Thickness = 2,
			LineJoinMode = Enum.LineJoinMode.Miter,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		-- keeps the name readable on bright art
		make("Frame", {
			Name = "Shade",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = BLACK,
			BorderSizePixel = 0,
		}, {
			make("UIGradient", {
				Rotation = 90,
				Transparency = numbers({ { 0, 1 }, { 1, 0.25 } }),
			}),
		}),

		text("Title", { Position = UDim2.new(0, 10, 1, -34), Size = UDim2.new(1, -20, 0, 28), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 22,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
		}, 2),

		-- the pick order, on its own black tag so it reads over any art
		make("Frame", {
			Name = "Pick",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.fromOffset(44, 22),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		}, {
			make("UIStroke", {
				Name = "Stroke",
				Color = GOLD,
				Thickness = 2,
				LineJoinMode = Enum.LineJoinMode.Miter,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),

			make("TextLabel", {
				Name = "Text",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				FontFace = font(Enum.FontWeight.Bold),
				TextSize = 13,
				TextColor3 = GOLD,
				Text = "",
				ZIndex = 3,
			}),
		}),

		highlight(0.6),
	})
end

-- a player on the host's server, with moderation chips the client shows as it fits
local function playerRowTemplate()
	return paneRow("PlayerRow", 34, 0.95, true, {
		text("Player", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -160, 1, 0), ZIndex = 2 }, {
			FontFace = font(Enum.FontWeight.Medium),
			TextSize = 19,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "",
		}, 1),

		make("Frame", {
			Name = "Actions",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(150, 22),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			list(Enum.FillDirection.Horizontal, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
			tint(chip("Ban", "BAN", 48, 22, 12, 1), BLOCKED),

			(function()
				local object = chip("Unban", "UNBAN", 62, 22, 12, 2)
				object.Stroke.Transparency = 0.4

				return object
			end)(),
		}),
	})
end

-- one choice in the Dropdown; the client fills the background on hover
local function dropdownItemTemplate()
	return make("ImageButton", {
		Name = "DropdownItem",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = BONE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Image = "",
		Visible = false,
	}, {
		make("TextLabel", {
			Name = "Label",
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			FontFace = font(Enum.FontWeight.SemiBold),
			TextSize = 16,
			TextColor3 = BONE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			ZIndex = 2,
		}),
	})
end

-- listed once so a partial rebuild swaps exactly the set a full build adds
local function modeTemplates()
	return {
		modeCardTemplate(),
		sessionRowTemplate(),
		readoutTemplate(),
		teamHeaderTemplate(),
		slotTemplate(),
		sectionHeadingTemplate(),
		settingRowTemplate(),
		teamEditTemplate(),
		swatchTemplate(),
		mapTilesTemplate(),
		mapTileTemplate(),
		playerRowTemplate(),
		dropdownItemTemplate(),
	}
end

----

local existing = replicatedFirst:FindFirstChild("Lobby")

-- a partial rebuild: swap in the private-server pieces and leave the rest of
-- the gui, hand edits included, alone
if REBUILD_ONLY then
	assert(existing, "REBUILD_ONLY needs a built Lobby; run once with it nil first")

	local stage = existing.Stage
	local only = {}

	for _, part in REBUILD_ONLY do
		only[part] = true
	end

	local function swap(parent, objects)
		for _, object in objects do
			local old = parent:FindFirstChild(object.Name)

			if old then
				old:Destroy()
			end

			object.Parent = parent
		end
	end

	if only.Picker then
		swap(stage, { buildPicker() })
	end

	if only.ModeView then
		swap(stage, { buildModeView() })
	end

	if only.Dropdown then
		swap(stage, { buildDropdown(), buildDropdownShield() })
	end

	if only.Invite then
		swap(stage, { buildInvite() })
	end

	-- siblings with the same ZIndex draw in child order, so these go back to
	-- the end in the full build's order: over the screens
	for _, name in { "Status", "Invite", "Dropdown", "DropdownShield" } do
		local object = stage:FindFirstChild(name)

		if object then
			object.Parent = nil
			object.Parent = stage
		end
	end

	-- the map card too: the mode card is built from it
	if only.Templates then
		swap(existing.Templates, { cardTemplate() })
		swap(existing.Templates, modeTemplates())

		-- retired templates an older build left behind
		for _, name in { "HubTile" } do
			local old = existing.Templates:FindFirstChild(name)

			if old then
				old:Destroy()
			end
		end
	end

	print("Lobby UI rebuilt: " .. table.concat(REBUILD_ONLY, ", "))

	return
end

-- keep the place's own backdrop; it's art-directed in Studio
local keptBackground = existing and existing:FindFirstChild("Background")

if keptBackground then
	keptBackground.Parent = nil
end

if existing then
	existing:Destroy()
end

-- full screen so the background runs under Roblox's top bar; the client
-- keeps the Stage below it (an inset ScreenGui clips its background)
make("ScreenGui", {
	Name = "Lobby",
	ScreenInsets = Enum.ScreenInsets.None,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = replicatedFirst,
}, {
	keptBackground or buildBackground(),

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
		buildModeView(),

		text("Status", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(600, 30),
			Visible = false,
		}, {
			FontFace = font(Enum.FontWeight.SemiBold, Enum.FontStyle.Italic),
			TextSize = 24,
			TextColor3 = BONE,
			Text = "",
		}, 2),

		buildInvite(),

		buildDropdown(),
		buildDropdownShield(),
	}),

	-- a Folder doesn't stop its GuiObjects rendering, so the templates are
	-- hidden and the client shows its clones
	make("Folder", { Name = "Templates" }, {
		cardTemplate(),
		tagTemplate(),
		rowTemplate(),
		statTemplate(),
		chipTemplate(),
		dotTemplate(),

		-- gamepad selection ring, same art as the hover highlight
		(function()
			local object = highlight()
			object.Name = "Selection"

			return object
		end)(),

		modeTemplates(),
	}),
})

print("Lobby UI built")
