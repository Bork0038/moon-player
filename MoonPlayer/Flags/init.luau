--!optimize 2
const FlagBase = require("@self/FlagBase")

export type Flag = FlagBase.Flag

export type PlayerFlags = {
    DisableStrictMode: FlagBase.Flag,
    LogUnresolvedInstances: FlagBase.Flag,

    Duration: (number) -> FlagBase.Flag,
    FrameAdvance: (number) -> FlagBase.Flag,

    InstanceOverrides: ({ [string]: Instance }) -> FlagBase.Flag,
    InstanceExclusions: ({ string }) -> FlagBase.Flag,

    Default: FlagBase.Flag
}


export type SerializerFlags = {
    CompressionLevel: (number) -> FlagBase.Flag,
    DisableRuntimeLengthEncoding: FlagBase.Flag,
    EnableRelativeCFrameOffset: FlagBase.Flag,

    CFrameSerializeMethod: {
        Attributes: boolean,
        Bytes: (
            PositionFormat: "F16" | "F32" | "F64", 
            RotationFormat: "F16" | "F32" | "F64"
        ) -> FlagBase.Flag
    },

    Default: FlagBase.Flag
}

export type Flags = {
    Player: PlayerFlags,
    Serializer: SerializerFlags
}

return {
    Player = require("@self/Player"),
    Serializer = require("@self/Serializer")
} :: Flags