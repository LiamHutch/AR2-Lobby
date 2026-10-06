-- Map art slideshows that move smoothly. A GUI image can only move in whole
-- pixels, so slow pans step; here each image is a Decal on a flat part in a
-- ViewportFrame and the camera moves over it, which renders sub-pixel. That
-- also allows real camera moves: drifts, push-ins and slight skews.
--
-- The map art is shot for this: every image is 1024x576 with its subject in
-- the undarkened centre, and the darkened edges are room to move into. The
-- frame shows the focal area and the moves stay inside the image. A show can
-- take other art (the picker cards' own CardImages) with its own shape and
-- focal area; art with no margins to spare only pushes in and drifts a little.

local tweenService = game:GetService("TweenService")
local contentProvider = game:GetService("ContentProvider")

local library = {}
library.__index = library

----

local ASPECT = 16 / 9 -- the map images are 1024x576; a show can be given another
library.ASPECT = ASPECT

-- the undarkened focal area, as a share of the image's width and height
local FOCUS_WIDTH = 0.83
local FOCUS_HEIGHT = 0.78

-- below this much room to shift sideways, a show skips its sideways moves
-- (drift across, skew swing), which would show past the image's edges
local MIN_SHIFT = 0.01

-- how much of the spare margin a move may use, and a cap so portrait crops
-- (lots of spare width) still move gently
local MARGIN_USE = 0.8
local MAX_SHIFT = 0.11

-- how much of each move is used: lower is slower panning and zooming over
-- the same time, 1 is the full range the margins allow
local TRAVEL = 0.55

local FOV = 20
local SKEW = math.rad(3) -- how far the camera swings off-axis on skew moves

local FADE = TweenInfo.new(1.2, Enum.EasingStyle.Sine)

----

-- [image] = true once it's downloaded (or failed: no point waiting on it again)
local loaded = {}

local function markLoaded(content)
	loaded[content] = true
end

-- downloads images in the background so shows never wait on them
function library.Preload(images)
	local missing = {}

	for _, image in images do
		if not loaded[image] and not table.find(missing, image) then
			table.insert(missing, image)
		end
	end

	if #missing > 0 then
		task.spawn(function()
			pcall(contentProvider.PreloadAsync, contentProvider, missing, markLoaded)
		end)
	end
end

-- yields until the image is downloaded
local function waitFor(image)
	if not loaded[image] then
		pcall(contentProvider.PreloadAsync, contentProvider, { image }, markLoaded)
		loaded[image] = true
	end
end

----

local function makeLayer(container, zIndex, aspect)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Slide"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	-- flat, full-bright: the decal shows its own colours
	viewport.Ambient = Color3.new(1, 1, 1)
	viewport.LightColor = Color3.new(0, 0, 0)
	viewport.ImageTransparency = 1
	viewport.ZIndex = zIndex

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- the image plane: centred on the origin, facing +Z (its Back face)
	local part = Instance.new("Part")
	part.Anchored = true
	part.Size = Vector3.new(aspect, 1, 0.02)
	part.CFrame = CFrame.new()
	part.Color = Color3.new(1, 1, 1)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = viewport

	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Back
	decal.Parent = part

	viewport.Parent = container

	return { viewport = viewport, camera = camera, decal = decal }
end

----

-- container: the GuiObject to fill (it should clip). options:
--   interval  seconds per image
--   zIndex    the lower of the two layers' ZIndex
--   delay     seconds before the first change, to stagger several shows
--   seed      varies the order of moves between shows
--   onChange  called with the index whenever the showing image changes
--   aspect    the images' width / height; default 16:9, the map art
--   focus     { width, height } share of each image to keep in frame;
--             default the map art's undarkened centre, { 1, 1 } for art with
--             no margins
function library.new(container, options)
	local self = setmetatable({}, library)

	self.container = container
	self.aspect = options.aspect or ASPECT
	self.focusWidth = options.focus and options.focus[1] or FOCUS_WIDTH
	self.focusHeight = options.focus and options.focus[2] or FOCUS_HEIGHT
	self.interval = options.interval or 6
	self.delay = options.delay or 0
	self.onChange = options.onChange
	self.random = Random.new(options.seed or os.clock() * 1000)
	self.images = {}
	self.index = 0
	self.token = 0

	local base = options.zIndex or 1
	self.front = makeLayer(container, base + 1, self.aspect)
	self.back = makeLayer(container, base, self.aspect)
	self.base = base

	return self
end

-- how the camera frames the image for the container's shape: distance, and
-- how far a move may shift the view each way
function library:frame()
	local size = self.container.AbsoluteSize
	local aspect = self.aspect
	local ratio = size.Y > 0 and size.X / size.Y or aspect

	-- show the focal area; a frame wider than it shows its full width instead
	local visibleHeight = math.min(self.focusHeight, aspect * self.focusWidth / ratio)
	local visibleWidth = visibleHeight * ratio

	local distance = (visibleHeight / 2) / math.tan(math.rad(FOV / 2))
	local spareX = (aspect - visibleWidth) / 2
	local spareY = (1 - visibleHeight) / 2

	return distance, math.min(spareX * MARGIN_USE, MAX_SHIFT), math.min(spareY * MARGIN_USE, MAX_SHIFT)
end

-- a start and end camera for one shot. Zoom only ever moves closer, so the
-- frame never shows past the image's edges
function library:move()
	local distance, shiftX, shiftY = self:frame()
	local random = self.random
	local side = random:NextNumber() < 0.5 and -1 or 1

	shiftX *= TRAVEL
	shiftY *= TRAVEL

	local function camera(x, y, zoom, skew)
		zoom = 1 - (1 - zoom) * TRAVEL
		skew *= TRAVEL

		local position = Vector3.new(x + distance * math.tan(skew), y, distance * zoom)

		return CFrame.lookAt(position, Vector3.new(x, y, 0))
	end

	-- 1 and 3 move sideways; art with no room that way only pushes or rises
	local kind = shiftX < MIN_SHIFT and (random:NextNumber() < 0.5 and 2 or 4) or random:NextInteger(1, 4)

	if kind == 1 then
		-- drift across, easing in slightly
		local y = random:NextNumber(-0.4, 0.4) * shiftY

		return camera(-shiftX * side, y, 1, 0), camera(shiftX * side, -y, 0.97, 0)
	elseif kind == 2 then
		-- push in toward a point off-centre
		local x = random:NextNumber(-0.5, 0.5) * shiftX
		local y = random:NextNumber(-0.5, 0.5) * shiftY

		return camera(0, 0, 1, 0), camera(x, y, 0.9, 0)
	elseif kind == 3 then
		-- swing: pan across while the camera slides the other way, so the
		-- image skews slightly in perspective
		return camera(-shiftX * 0.7 * side, 0, 0.98, SKEW * side), camera(shiftX * 0.7 * side, 0, 0.98, -SKEW * side)
	end

	-- rise or fall through the frame
	local x = random:NextNumber(-0.4, 0.4) * shiftX

	return camera(x, -shiftY * side, 0.98, 0), camera(-x, shiftY * side, 0.95, 0)
end

-- fades image `index` in over the current one and starts its move. Yields
-- until the image is downloaded; returns false if the show moved on meanwhile
function library:show(index, instant, token)
	local image = self.images[index]

	if not image then
		return false
	end

	if not loaded[image] then
		waitFor(image)

		if token ~= self.token then
			return false
		end

		-- it would have popped in blank, so fade it instead
		instant = false
	end

	local incoming, outgoing = self.back, self.front
	local from, to = self:move()

	self.index = index

	incoming.decal.Texture = image
	incoming.viewport.ZIndex = self.base + 1
	outgoing.viewport.ZIndex = self.base
	incoming.camera.CFrame = from

	-- the move outlasts the interval so the image is still moving as it fades out
	tweenService
		:Create(incoming.camera, TweenInfo.new(self.interval + FADE.Time + 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = to })
		:Play()

	if instant then
		incoming.viewport.ImageTransparency = 0
	else
		incoming.viewport.ImageTransparency = 1
		tweenService:Create(incoming.viewport, FADE, { ImageTransparency = 0 }):Play()
	end

	self.front, self.back = incoming, outgoing

	if self.onChange then
		self.onChange(index)
	end

	return true
end

-- shows `index` and moves on every interval until the images change, the
-- show stops, or someone picks an image
function library:run(index, instant, firstWait)
	self.token += 1

	local token = self.token

	task.spawn(function()
		if not self:show(index, instant, token) then
			return
		end

		local wait = firstWait or self.interval

		while true do
			task.wait(wait)
			wait = self.interval

			if token ~= self.token then
				return
			end

			self:show(#self.images > 1 and self.index % #self.images + 1 or self.index, false, token)
		end
	end)
end

function library:SetImages(images)
	self.images = images
	self.index = 0

	self.front.viewport.ImageTransparency = 1
	self.back.viewport.ImageTransparency = 1

	if #images == 0 then
		self:Stop()

		return
	end

	-- so the later images are ready before their turn
	library.Preload(images)

	self:run(1, true, self.interval + self.delay)
end

-- jump to an image; the timer starts over from it
function library:Show(index)
	if index ~= self.index and self.images[index] then
		self:run(index)
	end
end

function library:Stop()
	self.token += 1
end

function library:Destroy()
	self:Stop()
	self.front.viewport:Destroy()
	self.back.viewport:Destroy()
end

return library
