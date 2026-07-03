--!optimize 2
const SequentialReader = require("@self/SequentialReader")
const Deserializer = require("@self/Deserializer")
const Serializer = require("@self/Serializer")
const Flags = require("./Flags")

return {
	SequentialReader = SequentialReader,
	Deserializer = Deserializer,
	Serializer = Serializer,
	Flags = Flags.Serializer,
}