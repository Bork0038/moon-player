export type Flag = typeof(setmetatable(
    {}::{ 
        [string]: any,    
    },
    {}::{
        __add: (Flag, Flag) -> Flag
    }
))

local FlagBase = {}

function FlagBase.CreateCallFlag(key, default)
    local self = {
		[key] = default
	}
	
	return function(value)
		self[key] = value
		return self
	end
end

function FlagBase.CreateOptionFlag(key, default, options)
    return setmetatable({
        [key] = default
    }, { 
        __index = function(self, idx)
            local opt = options[idx]
            if not opt then
                return self
            end

            if typeof(opt) == "function" then
                return function(...)
                    local optData = opt(...)

                    if typeof(optData) == "table" then
                        for key, value in optData do    
                            self[key] = value
                        end
                    end

                    return self
                end
            end

            for key, value in opt do    
                self[key] = value
            end

            return self
        end
    })
end

function FlagBase.BuildFlags(flags, default)
    return setmetatable({}, { 
        __index = function(self, key) 
            local existingFlag = flags[key]
            if typeof(existingFlag) == "function" then
                return existingFlag
            end
            
            local meta = getmetatable(existingFlag) or {}
    
            local call = meta.__call
            local index = meta.__index

            return setmetatable(
                table.clone(existingFlag or default), 
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
end

return FlagBase