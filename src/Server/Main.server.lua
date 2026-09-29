local directory = require(script.Parent.Directory)
local teleports = require(script.Parent.Teleports)

directory:Start()
teleports:Start(directory)
