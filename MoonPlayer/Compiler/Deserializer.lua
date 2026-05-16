local EncodingService = game:GetService("EncodingService")
local HttpService = game:GetService("HttpService")

local Resolver = require("./Resolver")
local Stream = require("./Stream")
local Enums = require("./Enums")

local PropertyType = Enums.PropertyType

local MARKER_TYPES = { "finish", "start" } -- do not reorder these

local function unpackf16(u: number, min: number, max: number): number
    return u / 65535 * (max - min) + min
end


local Deserializer = {}

function Deserializer.new(save, overrides)
	local data = HttpService:JSONDecode(save.Value)

	local self = setmetatable({
		data = data,
		save = save,
		flags = data.Information.Flags,
		
		strings = {},
		values = {},
		objects = {},
		cframes = {},
		
		targets = {},
		targetOverrides = {},
		
		defaults = {},

		instanceOverrides = overrides or {},
		
		markers = {
			finish = {},
			start = {}
		}
	}, { __index = Deserializer })
	
	self:deserializeDictionaries()
	self:deserializeSequence()
	self:deserializeMarkers()
	self:deserializeHierarchy()
	self:deserializeDefaults()
	
	self.frameBuffer = self:decompressBuffer(save.frames)
	
	return self 
end

function Deserializer:overrideInstance(original, new)
	for id, instance in self.targets do
		if instance == original or instance:GetFullName() == original then
			self.targetOverrides[id] = new
		end
	end
end

function Deserializer:decompressBuffer(buf)
	local decodedBuffer = EncodingService:Base64Decode(
		buffer.fromstring(buf.Value)
	)
	
	return Stream.new(
		EncodingService:DecompressBuffer(
			decodedBuffer, 
			Enum.CompressionAlgorithm.Zstd
		)
	)
end

function Deserializer:deserializeGenericValue(stream, valueType)
	local valueType = valueType or stream:readu8()

	if valueType == PropertyType.Bool then
		return stream:readbool()
	elseif valueType == PropertyType.Number then
		return stream:readf64()
	elseif valueType == PropertyType.Color3 then
		return Color3.new(
			stream:readf32(),
			stream:readf32(),
			stream:readf32()
		)
	elseif valueType == PropertyType.Vector3 then
		return stream:readvector3()	
	elseif valueType == PropertyType.Nil then
		return nil
	else 
		warn(debug.traceback())
		warn("unknown value type", valueType)
	end
end

function Deserializer:deserializeValue(stream)
	local valueType = stream:readu8()

	if valueType == PropertyType.CFrame then
		local serializeMethod = self.flags.CFrameSerializeMethod

		if serializeMethod == "Attributes" then
			local cframeId = stream:readu32()
			
			return self.cframes[math.floor(cframeId / 1000)]:GetAttribute(tostring(cframeId)), cframeId
		else 
			local x = stream:readf32()
			local y = stream:readf32()
			local z = stream:readf32()

			local rx, ry, rz
			if serializeMethod == "Bytes" then
				rx = stream:readf32()
				ry = stream:readf32()
				rz = stream:readf32()
			elseif serializeMethod == "BytesLossy" then
				rx = unpackf16(stream:readu16(), -1, 1)
				ry = unpackf16(stream:readu16(), -1, 1)
				rz = unpackf16(stream:readu16(), -1, 1)
			end

			local rw = math.sqrt(math.max(0, 1 - rx * rx - ry * ry - rz * rz))

			return CFrame.new(x, y, z, rx, ry, rz, rw)
		end
	elseif valueType == PropertyType.String then
		return self.strings[stream:readu16()]
	elseif valueType == PropertyType.ObjectValue then
		return self.objects[stream:readu16()]
	elseif valueType == PropertyType.Value then
		return self.values[stream:readu16()]
	end

	return self:deserializeGenericValue(stream, valueType)
end


function Deserializer:deserializeDictionaries()
	local strings = {}
	local values = {}
	local objects = {}
	local cframes = {}
	
	local stream = self:decompressBuffer(self.save.dict)


	for _, child in self.save.cframes:GetChildren() do
		cframes[tonumber(child.Name)] = child
	end
	
	for _ = 1, stream:readu16() do
		local id = stream:readu16()
		
		strings[id] = stream:readstring(16)
	end
	
	for _ = 1, stream:readu16() do
		local id = stream:readu16()
		local value = self:deserializeGenericValue(stream)
		
		values[id] = value
	end
	
	for _ = 1, stream:readu16() do
		local id = stream:readu16()
		local query = stream:readstring(16)
		
		local inst = game:QueryDescendants(query)[1]
		if not inst then
			warn("fail to resolve object", query)
			continue
		end
		
		objects[id] = inst
	end
	
	self.objects = objects
	self.cframes = cframes
	self.strings = strings
	self.values = values
end

function Deserializer:deserializeSequence()
	local stream = self:decompressBuffer(self.save.sequence)
	
	local sequence = {}
	for _ = 1, stream:readu16() do
		table.insert(sequence, stream:readu16())
	end
	
	self.sequence = sequence
end

function Deserializer:deserializeDefaults()
	local stream = self:decompressBuffer(self.save.defaults)
	local defaults = {}
	
	for _ = 1, stream:readu16() do
		local instanceId = stream:readu16()
		local props = {}
		
		for _=  1, stream:readu8() do
			local name = self.strings[stream:readu16()]
			local value = self:deserializeValue(stream)
			
			props[name] = value
		end
		
		defaults[tostring(instanceId)] = props
	end
	
	self.defaults = defaults
end

function Deserializer:deserializeMarkers()
	local stream = self:decompressBuffer(self.save.markers)

	local markers = {}
	for _, markerType in MARKER_TYPES do
		for _ = 1, stream:readu16() do
			local frameId = stream:readu16()
			local frame = markers[tostring(frameId)]

			if not frame then
				frame = {}
				markers[tostring(frameId)] = frame
			end

			local markerData = frame[markerType]
			if not markerData then
				markerData = {}
				frame[markerType] = markerData
			end

			for _ =  1, stream:readu16() do
				local id = stream:readu16()
				local data = {}

				for _ = 1, stream:readu16() do
					local name = stream:readstring(8)
					local kfMarkers = {}

					for _ = 1, stream:readu8() do
						local kfMarkerName = stream:readstring(8)	
						local kfMarkerValue = stream:readstring(16)

						kfMarkers[kfMarkerName] = kfMarkerValue
					end

					data[name] = kfMarkers
				end

				markerData[tostring(id)] = data
			end
		end		
	end

	self.markers = markers
end

function Deserializer:deserializeHierarchy()
	local stream = self:decompressBuffer(self.save.hierarchy)
	
	local targets = {}
	for _, item in self.data.Items do
		local concatPath = table.concat(item.Path.InstanceNames, ".")
		local overridenInstance = self.instanceOverrides[concatPath]
		
		if not overridenInstance then
			overridenInstance = Resolver.resolveAnimPath(item.Path)
			
			if not overridenInstance then
				warn("failed to resolve", item.Path)
			end
		end
		
		targets[tostring(item.Identifier)] = overridenInstance
	end
	
	for _ = 1, stream:readu16() do
		local rootId = stream:readu16()
		local root = assert(targets[tostring(rootId)])
		
		local jointCount = stream:readu16()
		if jointCount > 0 then 
			local jointsHier, findJointSmart = Resolver.resolveJoints(root)
			
			for _ = 1, jointCount do
				local jointId = stream:readu16()
				local hier = stream:readstring(16)
				local jointData = jointsHier[hier] or (findJointSmart and findJointSmart(hier)) or nil
				
				if jointData and jointData.Joint then
					targets[tostring(jointId)] = jointData.Joint
				else 
					warn("failed to resolve joint", hier)
				end
			end
		end
	end
	
	self.targets = targets
end

return Deserializer