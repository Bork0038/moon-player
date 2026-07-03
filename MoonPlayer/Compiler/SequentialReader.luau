--!optimize 2
const LogService = game:GetService("LogService")

const Stream = require("./Stream")

const Reader = {}

function Reader.new(deserializer: any)
	const frameBuffer = Stream.new(
		deserializer.frameBuffer:tobuffer()
	)
	
	const self = setmetatable({
		currentFrame = -1,
		sequence = table.clone(deserializer.sequence),
		deserializer = deserializer,
		
		frameBuffer = frameBuffer,
		
	}, { __index = Reader })
	
	
	return self
end

function Reader:processNextFrame()
	const stream = self.frameBuffer 
	const nextFrame = stream:readu16()
	
	if nextFrame ~= self.currentFrame then
		stream.read -= 2 
		LogService:Warn("[MoonPlayer/Compiler/SequentialReader]: expected frame {expected}, got {got}", {expected = self.currentFrame, got = nextFrame})
		
		return
	end
	
	const frame = {}
	for _ = 1, stream:readu16() do
		const instanceId = stream:readu16()
		const props = {}
		
		for _ = 1, stream:readu16() do
			const propList = {
				duration = stream:readu16(),
				props = {}
			}
			
			for _ = 1, stream:readu8() do
				const name = assert(self.deserializer.strings[stream:readu16()])
				const value = self.deserializer:deserializeValue(stream)
				
				const prop = {
					name = name,
					value = value
				}
				
				if stream:readbool() then
					const easeType = assert(self.deserializer.strings[stream:readu16()])
					const target = self.deserializer:deserializeValue(stream)
					
					const params = {}
					for _ = 1, stream:readu8() do
						const key = assert(self.deserializer.strings[stream:readu16()])
						const paramValue = self.deserializer:deserializeValue(stream)

						params[key] = paramValue
					end
					
					prop.ease = {
						type = easeType,
						target = target,
						params = params 
					}
				end
				
				table.insert(propList.props, prop)
			end
			
			table.insert(props, propList)
		end
		
		frame[tostring(instanceId)] = props
	end
	
	return frame
end

function Reader:requestFrame()
	if #self.sequence == 0 then
		return
	end
	
	self.currentFrame += 1

	const nextFrame = self.sequence[1]
	if nextFrame == self.currentFrame then
		table.remove(self.sequence, 1)
		
		return self:processNextFrame()
	end

	return
end

return Reader