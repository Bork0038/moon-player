local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")

local ParseHierarchy = require("@self/Hierarchy")
local Stream = require("./Stream")
local Enums = require("./Enums")
local Flags = require("./Flags")

local PropertyType = Enums.PropertyType
local Tree = script.tree

local function packf16(v: number, min: number, max: number): number
    return math.round((v - min) / (max - min) * 65535)
end

local function cfToQuat(cf: CFrame): (number, number, number, number)
    local m = { cf:GetComponents() }
    local trace = m[4] + m[8] + m[12]

    local rw = math.sqrt(math.max(0, 1 + trace)) / 2
    local rx = math.sqrt(math.max(0, 1 + m[4]  - m[8]  - m[12])) / 2
    local ry = math.sqrt(math.max(0, 1 - m[4]  + m[8]  - m[12])) / 2
    local rz = math.sqrt(math.max(0, 1 - m[4]  - m[8]  + m[12])) / 2

    rx = math.sign(m[11] - m[9])  * rx
    ry = math.sign(m[5]  - m[11]) * ry
    rz = math.sign(m[9]  - m[5])  * rz

    return rx, ry, rz, rw
end

local Serializer = {}


function Serializer.new(
	save: StringValue, 
	flags: Flags.Flags?
)
	local self = setmetatable({
		save = save,
		data = HttpService:JSONDecode(save.Value),
		flags = flags or Flags + {},
		
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

function Serializer:writeCFrame(stream, cframe)
	local serializeMethod = self.flags.CFrameSerializeMethod

	if serializeMethod == "Attributes" then
		local id = self:fetchIdFromCompressionDictionary("cframes", tostring(cframe))
		self.realValues[tostring(cframe)] = cframe

		stream:writeu32(id)
	elseif serializeMethod == "Bytes" or serializeMethod == "BytesLossy" then
		local pos = cframe.Position
		local rx, ry, rz, rw = cfToQuat(cframe)

		if rw < 0 then 
			rx, ry, rz = -rx, -ry, -rz 
		end

		stream:writef32(pos.X)
		stream:writef32(pos.Y)
		stream:writef32(pos.Z)

		if serializeMethod == "Bytes" then
			stream:writef32(rx)
			stream:writef32(ry)
			stream:writef32(rz)
		else
			stream:writeu16(packf16(rx, -1, 1))
			stream:writeu16(packf16(ry, -1, 1))
			stream:writeu16(packf16(rz, -1, 1))
		end
	end
end

function Serializer:writePropertyValueToStream(stream, value)
	local valueType = typeof(value)

	if valueType == "boolean" then
		stream:writeu8(PropertyType.Bool)
		stream:writebool(value)
	elseif valueType == "string" then
		local id = self:fetchIdFromCompressionDictionary("strings", value)

		stream:writeu8(PropertyType.String)
		stream:writeu16(id)
	elseif valueType == "CFrame" then
		stream:writeu8(PropertyType.CFrame)
		self:writeCFrame(stream, value)
	elseif valueType == "Instance" then
		local id = self:fetchIdFromCompressionDictionary("objects", value)

		stream:writeu8(PropertyType.ObjectValue)
		stream:writeu16(id)
	elseif valueType == "number" or valueType == "Color3" or valueType == "Vector3" then
		local id = self:fetchIdFromCompressionDictionary("values", tostring(value))
		self.realValues[tostring(value)] = value

		stream:writeu8(PropertyType.Value)
		stream:writeu16(id)
	else
		warn("invalid type", valueType, value)
	end
end

function Serializer:writeValueToStream(stream, value)
	local valueType = typeof(value)

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
		warn("unknown type", valueType)
	end
end

function Serializer:writeStringId(stream, name)
	stream:writeu16(
		self:fetchIdFromCompressionDictionary("strings", name)
	)
end

function Serializer:encodeStream(stream)
	local compressedBuffer = EncodingService:CompressBuffer(
		stream:tobuffer(),
		Enum.CompressionAlgorithm.Zstd,
		self.flags.CompressionLevel
	)
	
	return buffer.tostring(
		EncodingService:Base64Encode(compressedBuffer)
	)
end


function Serializer:fetchIdFromCompressionDictionary(target, value)
	local targetDictionary = self.compressionDictionaries[target]
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

function Serializer:initHierarchy()
	local hierarchy = ParseHierarchy(self.data, self.save)

	self.frameBuffer = hierarchy.frameBuffer
	self.targets = hierarchy.tree
	self.markers = hierarchy.markers
	self.defaults = hierarchy.defaults
end

function Serializer:tagInstances()
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



function Serializer:Build()
	self:buildHierarchyStream()
	self:buildMarkerBuffer()
	self:buildDefaults()
	
	self:buildFrameBuffer()
	self:buildDictBuffer()

	if self.enableCFrameDictionary then
		self:buildCFrameRegistry()
	end
	
	self.tree.Value = HttpService:JSONEncode(self.data)

	return self.tree
end


function Serializer:buildDefaults()
	local stream = Stream.new(nil, 512)
	
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

function Serializer:buildFrameBuffer()
	local sequence = {}
	for id in self.frameBuffer do
		table.insert(sequence, tonumber(id))
	end
	
	table.sort(sequence)
	
	local stream = Stream.new()
	for _, id in sequence do
		local frame = self.frameBuffer[tostring(id)]
		local id = assert(tonumber(id))
		local count = 0
		
		for _ in frame do
			count += 1
		end
		
		stream:writeu16(id)
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

					local ease = propData.ease
					stream:writebool(not not ease)

					if ease then
						self:writeStringId(stream, ease.type)					
						self:writePropertyValueToStream(stream, ease.target)
						
						if ease.params then
							stream:createMarker("PARAM_COUNT", 1)
							
							local count = 0
							for name, value in ease.params do
								count += 1
								
								self:writeStringId(stream, name)
								self:writePropertyValueToStream(stream, value)
							end
							
							stream:seekMarker("PARAM_COUNT")
							stream:writeu8(count)
							stream:resume()
						end
					end
				end
			end
		end
	end
	
	local sequenceStream = Stream.new()
	sequenceStream:writeu16(#sequence)
	
	for _, id in sequence do
		sequenceStream:writeu16(id)
	end
	
	self.tree.sequence.Value = self:encodeStream(sequenceStream)
	self.tree.frames.Value = self:encodeStream(stream)
end

function Serializer:buildHierarchyStream()
	local stream = Stream.new(nil, 512)

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

function Serializer:buildCFrameRegistry()
	for cframe, id in self.compressionDictionaries.cframes.data do
		local realCFrame = self.realValues[cframe]
		local bucketIndex = math.floor(id / 1000)

		if not self.tree.cframes:FindFirstChild(bucketIndex) then
			local newEntry = Instance.new("Configuration")
			newEntry.Name = bucketIndex
			newEntry.Parent = self.tree.cframes
		end

		self.tree.cframes[bucketIndex]:SetAttribute(tostring(id), realCFrame)
	end
end

function Serializer:buildDictBuffer()
	local stream = Stream.new()
	
	local objectDict = self.compressionDictionaries.objects
	local stringDict = self.compressionDictionaries.strings
	local valueDict = self.compressionDictionaries.values

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
		local currentObj = obj
		local tbl = {}
		
		while currentObj ~= game and currentObj do
			tbl = {
				`{currentObj.ClassName}[Name="{currentObj.Name}"]`, 
				unpack(tbl)
			}
			
			currentObj = currentObj.Parent
		end
		
		stream:writeu16(id)
		stream:writestring(table.concat(tbl, " > "), 16)
	end
	
	self.tree.dict.Value = self:encodeStream(stream)
end

function Serializer:serializeMarkerTrack(stream, track)
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

function Serializer:buildMarkerBuffer()
	local stream = Stream.new(nil, 512)
	
	self:serializeMarkerTrack(stream, self.markers.finish)
	self:serializeMarkerTrack(stream, self.markers.start)
	
	self.tree.markers.Value = self:encodeStream(stream)
end

return Serializer