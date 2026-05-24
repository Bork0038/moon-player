local Compiler = require("@self/Compiler")
local Player = require("@self/Player")
local Types = require("@self/Types")
local Flags = require("@self/Flags")

local MoonPlayer = {
	Compiler = Compiler,
	Player = Player,
	Flags = Flags
}

return MoonPlayer :: Types.MoonPlayer