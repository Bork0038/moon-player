--!optimize 2
const FlagBase = require("./FlagBase")

const Flags = {
    CompressionLevel = FlagBase.CreateCallFlag("CompressionLevel", 7),
    DisableRuntimeLengthEncoding = { RuntimeLengthEncoding = false },
    EnableRelativeCFrameOffset = { RelativeCFrameOffset = true },

    CFrameSerializeMethod = FlagBase.CreateOptionFlag("CFrameSerializeMethod", "Bytes", { 
        Attributes = {
            CFrameSerializeMethod = "Attributes", 
            CFrameRotSizeT = 4, 
            CFramePosSizeT = 4, 
        },

        Bytes = function(posT: string, rotT: string): { [string]: any }
            return { 
                CFrameSerializeMethod = "Bytes", 
                CFramePosSizeT = (tonumber(posT:sub(2)) or 32) / 8,
                CFrameRotSizeT = (tonumber(rotT:sub(2)) or 32) / 8,
            }
        end
    }),
}

const Default = {
    RuntimeLengthEncoding = true,
    RelativeCFrameOffset = false,
    CompressionLevel = 7,
    CFrameSerializeMethod = "Bytes",
    CFrameRotSizeT = 4, 
    CFramePosSizeT = 4,
}


return FlagBase.BuildFlags(Flags, Default)