export type Flag = {
    [string]: any
}

export type Flags = {
    CompressionLevel: (number) -> Flag,

    CFrameSerializeMethod: {
        Attributes: boolean,
        Bytes: boolean,
        BytesLossy: boolean
    },
}


local function CreateCallFlag(key, default)
    return setmetatable({
        [key] = default
    }, {
        __call = function(self, value)
            self[key] = value
            return self
        end
    })
end

local function CreateOptionFlag(key, default)
    return setmetatable({
        [key] = default
    }, { 
        __index = function(self, idx)
            self[key] = idx
            return self
        end
    })
end


local _Flags = {
    CompressionLevel = CreateCallFlag("CompressionLevel", 7),
    CFrameSerializeMethod = CreateOptionFlag("CFrameSerializeMethod", "Bytes")
}

local Default = {
    CompressionLevel = 7,
    CFrameSerializeMethod = "Bytes"
}


local Flags: Flags = setmetatable({}, { 
    __index = function(self, key) 
        local existingFlag = _Flags[key]
        local meta = getmetatable(existingFlag) or {}
  
        local call = meta.__call
        local index = meta.__index

        return setmetatable(
            table.clone(Default), 
            {
                __call = call,
                __index = index,

                __add = function(flags, newFlag)
                    for key, value in newFlag do
                        flags[key] = value
                    end

                    return flags
                end
            }
        )
    end
})

return Flags