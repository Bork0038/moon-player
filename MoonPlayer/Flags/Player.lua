local FlagBase = require("./FlagBase")

local Flags = {
    DisableStrictMode = { StrictMode = false },
    LogUnresolvedInstances = { LogUnresolvedInstances = true },

    Duration = FlagBase.CreateCallFlag("Duration", -1),
    FrameAdvance = FlagBase.CreateCallFlag("FrameAdvance", 30),

    InstanceOverrides = FlagBase.CreateCallFlag("InstanceOverrides", {})
}

local Default = {
    StrictMode = true,
    LogUnresolvedInstances = false,
    
    Duration = -1,
    FrameAdvance = 30,

    InstanceOverrides = {}
}

return FlagBase.BuildFlags(Flags, Default)