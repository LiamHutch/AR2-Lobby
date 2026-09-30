local directory = require(script.Parent.Directory)
local teleports = require(script.Parent.Teleports)
local vipForward = require(script.Parent.VipForward)

-- a paid VIP server forwards everyone to the host's own server instead of
-- running the browser
if not vipForward:Start(directory) then
	directory:Start()
	teleports:Start(directory)
end
