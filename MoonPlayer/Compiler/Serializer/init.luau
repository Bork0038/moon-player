--!optimize 2
const EncodingService = game:GetService("EncodingService")
const HttpService = game:GetService("HttpService")
const LogService = game:GetService("LogService")

const ParseHierarchy = require("@self/Hierarchy")
const Resolver = require("./Resolver")
const Stream = require("./Stream")
const Enums = require("./Enums")
const Flags = require("../Flags")
const Types = require("../Types")

const PropertyType = Enums.PropertyType
const Tree = script.tree

const Serializer = {}


function Serializer.new(
	save: StringValue, 
	flags: Flags.Flag?
)
	const self = setmetatable({
		save = save,
		data = HttpService:JSONDecode(save.Value),
		flags = flags and Flags.Serializer.Default + flags or Flags.Serializer.Default,
		resolver = Resolver.new({}, {}),
		
		tree = Tree:Clone(),
		realValues = {},
		
		cframeDuplicates = 0,
		compressionDictionaries = {
			strings = { count = 0, data = {} },
			cframes = { count = 0, data = {} },
			objects = { count = 0, data = {} },
			values  = { count = 0, data = {} },
		}
	}, { __index = Serializer })
	
	self.data.Information.Flags = self.flags

	self:tagInstances()
	self:initHierarchy()	
	
	return self 
end

function Serializer:writeCFrame(stream: any, cframe: CFrame): ()
	const serializeMethod = self.flags.CFrameSerializeMethod

	if serializeMethod == "Attributes" then
		const id = self:fetchIdFromCompressionDictionary("cframes", tostring(cframe))
		self.realValues[tostring(cframe)] = cframe

		stream:writeu32(id)
	elseif serializeMethod == "Bytes" then
		stream:writeCFrame(self.flags.CFramePosSizeT, self.flags.CFrameRotSizeT, cframe)
	end
end

function Serializer:writePropertyValueToStream(stream: any, value: any): ()
	const valueType = typeof(value)

	if valueType == "boolean" then
		stream:writeu8(PropertyType.Bool)
		stream:writebool(value)
	elseif valueType == "string" then
		const id = self:fetchIdFromCompressionDictionary("strings", value)

		stream:writeu8(PropertyType.String)
		stream:writeu16(id)
	elseif valueType == "CFrame" then
		stream:writeu8(PropertyType.CFrame)
		self:writeCFrame(stream, value)
	elseif valueType == "Instance" then
		const id = self:fetchIdFromCompressionDictionary("objects", value)

		stream:writeu8(PropertyType.ObjectValue)
		stream:writeu16(id)
	elseif valueType == "number" or valueType == "Color3" or valueType == "Vector3" then
		const id = self:fetchIdFromCompressionDictionary("values", tostring(value))
		self.realValues[tostring(value)] = value

		stream:writeu8(PropertyType.Value)
		stream:writeu16(id)
	elseif valueType == "ColorSequence" then
		stream:writeu8(PropertyType.ColorSequence)

		const keypoints = value.Keypoints
		
		if #keypoints == 2 and keypoints[1].Value == keypoints[2].Value then
			keypoints[2] = nil
		end
		
		stream:writeu8(#keypoints)

		for _, keypoint  in keypoints do
			stream:writef16(keypoint.Time)

			const color = keypoint.Value
			stream:writef32(color.R)
			stream:writef32(color.G)
			stream:writef32(color.B)
		end
	elseif valueType == "NumberSequence" then
		stream:writeu8(PropertyType.NumberSequence)

		const keypoints = value.Keypoints

		if #keypoints == 2 and keypoints[1].Value == keypoints[2].Value and keypoints[1].Envelope == 0 then
			keypoints[2] = nil
		end 

		stream:writeu8(#keypoints)
		for _, keypoint in keypoints do
			stream:writef32(keypoint.Time)
			stream:writef32(keypoint.Value)
			stream:writef32(keypoint.Envelope)
		end
	else
		LogService:Warn("[MoonPlayer/Compiler/Serializer]: invalid type {valueType} for value {value}\n{traceback}", {
			valueType = valueType,
			value = value,
			traceback = debug.traceback(),
		})
	end
end

function Serializer:writeValueToStream(stream: any, value: any): ()
	const valueType = typeof(value)

	if valueType == "number" then
		stream:writeu8(PropertyType.Number)
		stream:writef64(value)
	elseif valueType == "Color3" then
		stream:writeu8(PropertyType.Color3)

		stream:writef32(value.R);
		stream:writef32(value.G);
		stream:writef32(value.B);
	elseif valueType == "Vector3" then
		stream:writeu8(PropertyType.Vector3)
		stream:writevector3(value)
	else 
		LogService:Warn("[MoonPlayer/Compiler/Serializer]: unknown type {valueType}", {valueType = valueType})
	end
end

function Serializer:writeStringId(stream: any, name: string): ()
	stream:writeu16(
		self:fetchIdFromCompressionDictionary("strings", name)
	)
end

function Serializer:encodeStream(stream: any): string
	const compressedBuffer = EncodingService:CompressBuffer(
		stream:tobuffer(),
		Enum.CompressionAlgorithm.Zstd,
		self.flags.CompressionLevel
	)
	
	return buffer.tostring(
		EncodingService:Base64Encode(compressedBuffer)
	)
end

function Serializer:encodeStreamToParts(stream: any): { StringValue }
	const compressedBuffer = EncodingService:CompressBuffer(
		stream:tobuffer(),
		Enum.CompressionAlgorithm.Zstd,
		self.flags.CompressionLevel
	)

	const buf = EncodingService:Base64Encode(compressedBuffer)
	const totalSize = buffer.len(buf)

	const chunkSize = 175 * 1024 
	const chunks = table.create(math.ceil(totalSize / chunkSize))

	local offset = 0
	while offset < totalSize do
		const size = math.min(chunkSize, totalSize - offset)

		const chunk = buffer.create(size)
		buffer.copy(chunk, 0, buf, offset, size)

		chunks[#chunks + 1] = chunk
		offset += size
	end

	const out = {}

	for i = 1, #chunks do
		const value = Instance.new("StringValue")
		value.Value = buffer.tostring(chunks[i])
		value.Name = tostring(i)

		table.insert(out, value)
	end

	return out
end

function Serializer:fetchIdFromCompressionDictionary(target: string, value: any): number
	const targetDictionary = self.compressionDictionaries[target]
	local existingId = targetDictionary.data[value]

	if not existingId then
		existingId = targetDictionary.count
		targetDictionary.data[value] = existingId

		targetDictionary.count += 1
	else 
		if target == "cframes" then
			self.cframeDuplicates += 1
		end
	end

	return existingId
end

function Serializer:initHierarchy(): ()
	const hierarchy = ParseHierarchy(
		self.data,
		self.save,
		not self.flags.RuntimeLengthEncoding,
		self.flags.RelativeCFrameOffset,
		self.resolver
	)

	self.frameBuffer = hierarchy.frameBuffer
	self.targets = hierarchy.tree
	self.markers = hierarchy.markers
	self.defaults = hierarchy.defaults
end

function Serializer:tagInstances(): ()
	local id = 1
	
	for _, item in self.data.Items do
		item.Identifier = id 
		id += 1
	end

	for _, child in self.save:QueryDescendants("#Rig > #_joint") do
		child:SetAttribute("Identifier", id)
		id += 1
	end
end



function Serializer:Build(): Types.MoonSave
	self:buildHierarchyStream()
	self:buildMarkerBuffer()
	self:buildDefaults()
	
	self:buildFrameBuffer()
	self:buildDictBuffer()

	if self.flags.CFrameSerializeMethod == "Attributes" then
		self:buildCFrameRegistry()
	end
	
	self.tree.Value = HttpService:JSONEncode(self.data)

	return self.tree
end


function Serializer:buildDefaults(): ()
	const stream = Stream.new(nil, 512)
	
	local count = 0 
	
	stream:createMarker("COUNT", 2)
	for instanceId, props in self.defaults do
		stream:writeu16(tonumber(instanceId))
		stream:createMarker("PROP_COUNT", 1)
		
		local propCount = 0
		for name, value in props do
			self:writeStringId(stream, name)
			self:writePropertyValueToStream(stream, value)
			
			propCount += 1
		end
		
		stream:seekMarker("PROP_COUNT")
		stream:writeu8(propCount)
		stream:resume()

		count += 1
	end
	
	stream:seekMarker("COUNT")
	stream:writeu16(count)
	stream:resume()
	
	self.tree.defaults.Value = self:encodeStream(stream)
end

function Serializer:buildFrameBuffer(): ()
	const sequence = {}
	for id in self.frameBuffer do
		table.insert(sequence, tonumber(id))
	end
	
	table.sort(sequence)
	
	const stream = Stream.new()
	for _, id in sequence do
		const frame = self.frameBuffer[tostring(id)]
		const frameId = assert(tonumber(id))
		local count = 0

		for _ in frame do
			count += 1
		end

		stream:writeu16(frameId)
		stream:writeu16(count)
		
		for instanceId, state in frame do
			stream:writeu16(tonumber(instanceId))
			stream:writeu16(#state)
			
			for _, prop in state do
				stream:writeu16(prop.count)	
				stream:writeu8(prop.propCount)
				
				for name, propData in prop.props do	
					self:writeStringId(stream, name)
					self:writePropertyValueToStream(stream, propData.value)

					const ease = propData.ease
					stream:writebool(not not ease)

					if ease then
						self:writeStringId(stream, ease.type)					
						self:writePropertyValueToStream(stream, ease.target)
						
						if ease.params then
							stream:createMarker("PARAM_COUNT", 1)
							
							local paramCount = 0
							for name, value in ease.params do
								paramCount += 1

								self:writeStringId(stream, name)
								self:writePropertyValueToStream(stream, value)
							end

							stream:seekMarker("PARAM_COUNT")
							stream:writeu8(paramCount)
							stream:resume()
						end
					end
				end
			end
		end
	end
	
	const sequenceStream = Stream.new()
	sequenceStream:writeu16(#sequence)
	
	for _, id in sequence do
		sequenceStream:writeu16(id)
	end
	
	for _, part in self:encodeStreamToParts(stream) do
		part.Parent = self.tree.frames
	end

	self.tree.sequence.Value = self:encodeStream(sequenceStream)
end

function Serializer:buildHierarchyStream(): ()
	const stream = Stream.new(nil, 512)

	stream:createMarker("TARGET_COUNT", 2)

	local targetCount = 0
	for _, item in self.targets do
		stream:writeu16(item.Identifier)
		stream:createMarker("COUNT", 2)
		
		local count = 0
		for jointId, data in item.Joints or {} do
			count += 1
			
			stream:writeu16(tonumber(jointId))
			stream:writestring(data.hier, 16)
		end
		
		stream:seekMarker("COUNT")
		stream:writeu16(count)
		stream:resume()
		
		targetCount += 1
	end
	
	stream:seekMarker("TARGET_COUNT")
	stream:writeu16(targetCount)
	stream:resume()
	
	self.tree.hierarchy.Value = self:encodeStream(stream)
end

function Serializer:buildCFrameRegistry(): ()
	for cframe, id in self.compressionDictionaries.cframes.data do
		const realCFrame = self.realValues[cframe]
		const bucketIndex = math.floor(id / 1000)

		if not self.tree.cframes:FindFirstChild(bucketIndex) then
			const newEntry = Instance.new("Configuration")
			newEntry.Name = bucketIndex
			newEntry.Parent = self.tree.cframes
		end

		self.tree.cframes[bucketIndex]:SetAttribute(tostring(id), realCFrame)
	end
end

function Serializer:buildDictBuffer(): ()
	const stream = Stream.new()
	
	const objectDict = self.compressionDictionaries.objects
	const stringDict = self.compressionDictionaries.strings
	const valueDict = self.compressionDictionaries.values

	stream:writeu16(stringDict.count)
	for str, id in stringDict.data do
		stream:writeu16(id)
		stream:writestring(str, 16)
	end

	stream:writeu16(valueDict.count)
	for value, id in valueDict.data do
		stream:writeu16(id)

		self:writeValueToStream(stream, self.realValues[value])
	end
	
	stream:writeu16(objectDict.count)
	for obj, id in objectDict.data do
		stream:writeu16(id)
		stream:createMarker("COUNT", 1)

		local currentObj = obj
		local count = 0

		while currentObj ~= game and currentObj do
			stream:writestring(currentObj.Name, 8)
			stream:writestring(currentObj.ClassName, 8)

			currentObj = currentObj.Parent
			count += 1
		end

		stream:seekMarker("COUNT")
		stream:writeu8(count)
		stream:resume()
	end
	
	self.tree.dict.Value = self:encodeStream(stream)
end

function Serializer:serializeMarkerTrack(stream: any, track: any): ()
	local frameCount = 0
	
	stream:createMarker("COUNT", 2)
	
	for frameId, markers in track do
		stream:writeu16(frameId)
		stream:createMarker(`{frameId}`, 2)

		local count = 0
		for inst, markers in markers do
			count += 1

			stream:writeu16(inst)
			stream:createMarker("MARKER_COUNT", 2)

			local markerCount = 0 
			for name, kfMarkers in markers do
				stream:writestring(name, 8)
				stream:createMarker("KF_MARKER_COUNT", 1)

				local kfMarkerCount = 0
				for name, data in kfMarkers do
					stream:writestring(name, 8)
					stream:writestring(data, 16)

					kfMarkerCount += 1		
				end

				stream:seekMarker("KF_MARKER_COUNT")
				stream:writeu8(kfMarkerCount)
				stream:resume()

				markerCount += 1
			end

			stream:seekMarker("MARKER_COUNT")
			stream:writeu16(markerCount)
			stream:resume()
		end

		stream:seekMarker(`{frameId}`)
		stream:writeu16(count)
		stream:resume()
		
		frameCount += 1
	end
	
	stream:seekMarker("COUNT")
	stream:writeu16(frameCount)
	stream:resume()
	stream:clearMarkers()
end

function Serializer:buildMarkerBuffer(): ()
	const stream = Stream.new(nil, 512)
	
	self:serializeMarkerTrack(stream, self.markers.finish)
	self:serializeMarkerTrack(stream, self.markers.start)
	
	self.tree.markers.Value = self:encodeStream(stream)
end

return Serializer