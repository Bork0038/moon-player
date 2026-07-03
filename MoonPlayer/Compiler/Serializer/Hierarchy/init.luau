--!optimize 2
const LogService = game:GetService("LogService")

const StaticProps = require("../../StaticProps")
const EQ = require("@self/EQ")

const CONSTANT_INTERPS = {
	["Instance"] = true,
	["boolean"] = true,
	["string"] = true,
	["nil"] = true,
}

const VALUE_HANDLERS = {
	EnumType = function(inst: any, baseValue: any): any
		return Enum[inst.Value][baseValue]
	end,

	Vector2 = function(inst: Instance, baseValue: any): Vector2
		return Vector2.new(baseValue.X, baseValue.Y)
	end,

	ColorSequence = function(inst: Instance, baseValue: any): ColorSequence
		return ColorSequence.new(baseValue)
	end,

	NumberSequence = function(inst: Instance, baseValue: any): NumberSequence
		return NumberSequence.new(baseValue)
	end,

	NumberRange = function(inst: Instance, baseValue: any): NumberRange
		return NumberRange.new(baseValue)
	end
}

const function readValue(value: any): any
	if not value:IsA("ValueBase") then
		return value:GetAttribute("Value")
	end

	const baseValue = value.Value
	for name, handler in VALUE_HANDLERS do
		const inst = value:FindFirstChild(name)

		if inst then
			return handler(inst, baseValue)
		end
	end

	return baseValue
end

const function optimizeKeyframes(frames: {any}, isStatic: any?): { any }
	const optimized = {}

	local idx = 1
	while idx <= #frames do
		const currentFrame = frames[idx]

		while idx <= #frames do
			const nextFrame = frames[idx + 1]
			if not nextFrame then
				break 
			end 

			const diff = nextFrame.startTime - currentFrame.startTime
			const isValueSame = EQ(nextFrame.value, currentFrame.value)

			if diff < 1 or not isValueSame or currentFrame.eases then
				break
			end 

			if nextFrame.eases then
				currentFrame.count += diff - 1
				break
			end 
			
			currentFrame.count += diff
			idx += 1
		end 

		table.insert(optimized, currentFrame)
		idx += 1
	end 
	
	return optimized
end

const function parseKeyframes(keyframesInst: Instance, instance: Instance, disableOptimization: boolean): { any }
	const packs = keyframesInst:QueryDescendants(">Folder")

	const packInstances = {}
	const keyframes = {}
	
	const isStatic = StaticProps[instance.ClassName]
		and StaticProps[instance.ClassName][keyframesInst.Name]

	local isConstant = false

	for _, inst in packs do
		const packId = tonumber(inst.Name)
		packInstances[packId] = inst 

		const values = assert(
			inst:FindFirstChild("Values"), 
			"keyframe pack has no values"
		)

		const eases = inst:FindFirstChild("Eases")
		local valueModifier 
		
		for name, handler in VALUE_HANDLERS do
			if values:FindFirstChild(name) then
				valueModifier = handler
			end
		end

		for _, keyframe in values:GetChildren() do
			const frameIdx =  tonumber(keyframe.Name)
			if not frameIdx then
				continue
			end

			local easeData

			if eases then 
				const ease = eases:FindFirstChild(keyframe.Name)

				if ease then
					const easeType = ease:FindFirstChild("Type")
					const easeParams = ease:FindFirstChild("Params")
					
					const params = {}

					if easeParams then
						for _, child in easeParams:GetChildren() do
							params[child.Name] = readValue(child)
						end
					end

					easeData = {
						type = easeType.Value,
						params = params
					}
				end
			end 

			local value = readValue(keyframe)

			if CONSTANT_INTERPS[typeof(value)] then
				isConstant = true
			end 

			if valueModifier then
				value = valueModifier(keyframe, value)
			end

			table.insert(keyframes, {
				pack = packId,
				idx = frameIdx,
				startFrame = frameIdx + packId,

				static = isStatic or isConstant,
				isConstant = isConstant,
				
				eases = easeData,
				value = value,
				count = 1
			})
		end 
	end
	
	table.sort(keyframes, function(a: any, b: any): boolean
		return a.pack + a.idx < b.pack + b.idx
	end)

	const frames = {}

	while true do
		const currentFrame = table.remove(keyframes, 1)
		if not currentFrame then
			break
		end

		const nextFrame = keyframes[1]
		if nextFrame then
			const diff = nextFrame.startFrame - currentFrame.startFrame
			const isValueSame = EQ(nextFrame.value, currentFrame.value)

			if not currentFrame.static then
				if diff >= 1 and currentFrame.eases and not isValueSame then
					currentFrame.eases.target = nextFrame.value
					currentFrame.count += diff - 1

				elseif diff > 1 and not currentFrame.eases and not isValueSame then
					currentFrame.eases = {
						target = nextFrame.value,
						type = "Linear",
						params = {
							Direction = "In"
						}
					}

					currentFrame.count += diff - 1
				end
			end 

			if isValueSame and currentFrame.isConstant then
				table.remove(keyframes, 1)
			end
		end

		if currentFrame.eases and (not currentFrame.eases.target or currentFrame.static) then
			currentFrame.eases = nil
		end

		table.insert(frames, {
			startTime = currentFrame.startFrame,
			value = currentFrame.value,
			static = isStatic,
			count = currentFrame.count,
			ease = currentFrame.eases
		})
	end

	if disableOptimization or isStatic then
		return frames 
	end 

	return optimizeKeyframes(frames)
end

const function insertMarker(markers: any, frame: number, identifier: number, name: string, kfMarkers: any): ()
	local markerData = markers[frame]
	if not markerData then
		markerData = {}
		markers[frame] = markerData
	end

	if not markerData[identifier] then
		markerData[identifier] = {
			[name] = kfMarkers
		}
	else 
		markerData[identifier] = kfMarkers
	end
end

const function parseKFMarkers(track: Instance): { [string]: string }
	const kf = track:FindFirstChild("KFMarkers")
	const markers = {}
	
	if kf then
		for _, val in kf:QueryDescendants("StringValue > StringValue#Val") do
			const name = val.Parent.Value
			const value = val.Value

			markers[name] = value
		end
	end

	return markers
end

const function offsetValueByDefault(value: any, propName: string, default: any, realInstance: Instance, relativeOffset: boolean): any
	if relativeOffset == false then
		return value
	end

	if propName == "CFrame" and not realInstance:IsA("Attachment") then
		return default:Inverse() * value
	elseif propName == "Position" then
		return value - default
	end

	return value
end

const function ParseHierarchy(data: any, save: StringValue, disableOptimization: boolean, relativeOffset: boolean, resolver: any)
	const frameBuffer = {}
	const defaults = {}
	const tree = {}
	
	const markers = {
		start = {},
		finish = {}
	}
	
	for idx, item in data.Items do
		const identifier = item.Identifier
		const itemData = {
			Identifier = identifier
		}
		
		const frame = save:FindFirstChild(idx)
		
		const rig = frame:FindFirstChild("Rig")
		const markerTrack = frame:FindFirstChild("MarkerTrack")

		const realInstance = resolver:resolveInstance(item.Path)
		if not realInstance then
			return LogService:Error("[MoonPlayer/Compiler/Serializer/Hierarchy]: failed to resolve {path}", {path = table.concat(item.Path.InstanceNames, ".")})
		end

		if rig and item.Path.ItemType == "Rig" then
			const jointsHier = resolver:resolveJoints(realInstance)
			
			const joints = rig:QueryDescendants(">#_joint")
			const jointData = {}
		
			for _, joint in joints do
				const jointId = joint:GetAttribute("Identifier")
				
				const hier = joint:FindFirstChild("_hier").Value
				local default = joint:FindFirstChild("default")
				const keyframes = joint:FindFirstChild("_keyframes")

				if default then
					default = readValue(default)
					
					defaults[tostring(jointId)] = {
						Transform = default
					}
				end
				
				if keyframes then
					const hierJoint = jointsHier[hier]
					if not hierJoint then
						return LogService:Error("[MoonPlayer/Compiler/Serializer/Hierarchy]: failed to resolve {hier}", {hier = hier})
					end

					const isMotor6D = hierJoint:IsA("Motor6D")
					for _, keyframe in parseKeyframes(keyframes, hierJoint, disableOptimization) do
						local value = keyframe.value
						local frameData = frameBuffer[tostring(keyframe.startTime)]
						
						if not frameData then
							frameData = {}
							frameBuffer[tostring(keyframe.startTime)] = frameData
						end
						
						if isMotor6D then
							value = value:Inverse()

							if keyframe.ease then
								keyframe.ease.target = keyframe.ease.target:Inverse()
							end
						end
						
						frameData[tostring(jointId)] = {
							{
								props = {
									Transform = {
										value = value,
										ease = keyframe.ease,
									}
								},
								
								propCount = 1,
								count = keyframe.count	
							}
						}
					end
				end
				
				jointData[tostring(jointId)] = {
					hier = hier,
					default = default
				}
			end
			
			itemData.JointCount = #joints
			itemData.Joints = jointData
		else 
			for _, child in frame:QueryDescendants(">Folder:not(#MarkerTrack)") do
				const default = child:FindFirstChild("default")
				const propName = child.Name
				local defaultValue

				local instDefaults = defaults[tostring(identifier)]
				if not instDefaults then
					instDefaults = {}
					defaults[tostring(identifier)] = instDefaults
				end

				if default then
					defaultValue = readValue(default) 
					instDefaults[child.Name] = defaultValue
				else 
					local success, defaultPropValue = pcall(function(...)
						return child[propName]
					end)

					if success then
						defaultValue = defaultPropValue
						instDefaults[child.Name] = defaultPropValue 
					end
				end

				for _, keyframe in parseKeyframes(child, realInstance, disableOptimization) do
					local frameData = frameBuffer[tostring(keyframe.startTime)]
					if not frameData then
						frameData = {}
						frameBuffer[tostring(keyframe.startTime)] = frameData
					end
					
					local existingFrameData = frameData[tostring(identifier)]
					if not existingFrameData then
						existingFrameData = {}
						frameData[tostring(identifier)] = existingFrameData
					end
					
					if keyframe.ease then
						keyframe.ease.target = offsetValueByDefault(
							keyframe.ease.target,
							propName,
							defaultValue,
							realInstance,
							relativeOffset
						)
					end 

					const prop = {
						props = {
							[child.Name] = {
								ease = keyframe.ease,
								value = offsetValueByDefault(
									keyframe.value,
									propName,
									defaultValue,
									realInstance,
									relativeOffset
								)
							}
						},

						propCount = 1,
						count = keyframe.count	
					}
					
					table.insert(existingFrameData, prop)
				end
				
			end
		end
		
		if markerTrack then
			for _, track in markerTrack:GetChildren() do
				const startFrame = assert(tonumber(track.Name))
				const width = assert(track:FindFirstChild("width")).Value
				const name = assert(track:FindFirstChild("name")).Value
				const kfMarkers = parseKFMarkers(track)

				insertMarker(markers.start, startFrame, identifier, name, kfMarkers)
				
				if width > 0 then
					const finishFrame = math.min(startFrame + width, data.Information.Length)

					insertMarker(markers.finish, finishFrame, identifier, name, kfMarkers)
				end
			end
		end
		
		tree[tostring(identifier)] = itemData
	end
	
	return {
		markers = markers,
		defaults = defaults,
		frameBuffer = frameBuffer,
		tree = tree
	}
end

return ParseHierarchy
