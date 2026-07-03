--!optimize 2
const FlagBase = require("./FlagBase")

const Flags = {
    DisableStrictMode = { StrictMode = false },
    LogUnresolvedInstances = { LogUnresolvedInstances = true },

    Duration = FlagBase.CreateCallFlag("Duration", -1),
    FrameAdvance = FlagBase.CreateCallFlag("FrameAdvance", 30),

    InstanceOverrides = FlagBase.CreateCallFlag("InstanceOverrides", {}),
    InstanceExclusions = FlagBase.CreateCallFlag("InstanceExclusions", {})
}

const Default = {
    StrictMode = true,
    LogUnresolvedInstances = false,
    
    Duration = -1,
    FrameAdvance = 30,

    InstanceOverrides = {},
    InstanceExclusions = {}
}

return FlagBase.BuildFlags(Flags, Default)