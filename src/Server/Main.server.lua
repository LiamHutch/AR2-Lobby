local playersService = game:GetService("Players")

local directory = require(script.Parent.Directory)
local teleports = require(script.Parent.Teleports)
local vipForward = require(script.Parent.VipForward)

-- the lobby is UI only, so no one ever gets a character. CharacterAutoLoads
-- is off in the project; this also catches anything that calls LoadCharacter
playersService.CharacterAutoLoads = false

local function noCharacter(client)
	client.CharacterAdded:Connect(function(character)
		task.defer(character.Destroy, character)
	end)
end

playersService.PlayerAdded:Connect(noCharacter)

for _, client in playersService:GetPlayers() do
	noCharacter(client)
end

-- a paid VIP server forwards everyone to the host's own server instead of
-- running the browser
if not vipForward:Start(directory) then
	directory:Start()
	teleports:Start(directory)
end
