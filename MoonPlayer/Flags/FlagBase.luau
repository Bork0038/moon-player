--!optimize 2
export type Flag = typeof(setmetatable(
    {}::{ 
        [string]: any,    
    },
    {}::{
        __add: (Flag, Flag) -> Flag
    }
))

const FlagBase = {}

function FlagBase.CreateCallFlag(key: string, default: any)
    const self = {
		[key] = default
	}
	
	return function(value: any)
		self[key] = value
		return setmetatable(self, {
            __add = function(flags: { [string]: any }, newFlag: { [string]: any }): { [string]: any }
                for key, value in newFlag do
                    flags[key] = value
                end

                return flags
            end
        })
	end
end

function FlagBase.CreateOptionFlag(key: string, default: any, options: { [string]: any })
    return setmetatable({
        [key] = default
    }, { 
        __index = function(self: any, idx: string)
            const opt = options[idx]
            if not opt then
                return self
            end

            if typeof(opt) == "function" then
                return function(...)
                    const optData = opt(...)

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

function FlagBase.BuildFlags(flags: { [string]: any }, default: { [string]: any })
    return setmetatable({}, { 
        __index = function(self: any, key: string)
            const existingFlag = flags[key]
            if typeof(existingFlag) == "function" then
                return existingFlag
            end
            
            const meta = getmetatable(existingFlag) or {}
    
            const call = meta.__call
            const index = meta.__index

            return setmetatable(
                table.clone(existingFlag or default), 
                {
                    __call = call,
                    __index = index,

                    __add = function(flags: { [string]: any }, newFlag: { [string]: any }): { [string]: any }
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