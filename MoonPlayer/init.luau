--!optimize 2
const Compiler = require("@self/Compiler")
const Player = require("@self/Player")
const Types = require("@self/Types")
const Flags = require("@self/Flags")

const MoonPlayer = {
	Compiler = Compiler,
	Player = Player,
	Flags = Flags
}

return (MoonPlayer :: any) :: Types.MoonPlayer