local FRAME_ADVANCE = 30
local FRAME_ADVANCE_HZ = Enum.StepFrequency.Hz30


local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Interpolator = require("./Interpolator")
local ApplyProp = require("@self/ApplyProp")
local EaseFuncs = require("./EaseFuncs")
local Compiler = require("./Compiler")

local SequentialReader = Compiler.SequentialReader
local Deserializer = Compiler.Deserializer

local PlayingTracks = {}
local IGNORED_DEFAULTS = { "Emit" }

local Player = {}


function Player.new(track, instanceOverrides)
	local Data = HttpService:JSONDecode(track.Value)

	local self = setmetatable({
		Data = Data,
		Deserializer = Deserializer.new(track, instanceOverrides),
		Reader = nil,

		FrameRate = Data.Information.FrameRate or 60,
		Length = Data.Information.Length,

		CurrentFrame = -1,
		CurrentAdvance = 0,
		TimePosition = 0,

		FrameAdvance = {},
		FrameState = {},
		
		MarkerSequence = {},
		PartAttachments = {},

		MarkerCallbacks = {},
		FinishedCallbacks = {},
		FrameCallbacks = {}
	}, { __index = Player })

	return self
end


function Player:Stop()
	PlayingTracks[self] = nil
	self:_restore()
end

function Player:Resume()
	PlayingTracks[self] = true
end

function Player:Play()
	self:_buildMarkerSequence()
	self:_restore()
	self:_advance()
	
	PlayingTracks[self] = true
end

function Player:SetDuration(duration)
    local originalFrameRate = self.Data.Information.FrameRate or 60
    local originalLength = self.Data.Information.Length
    local originalDuration = originalLength / originalFrameRate

    self.FrameRate = originalFrameRate * (originalDuration / duration)
end

function Player:ReplaceInstance(original, new)
	return self.Deserialize:overrideInstance(original, new)
end


function Player:OnMarkerReached(name, callback)
	self.MarkerCallbacks[name] = callback
end

function Player:OnFinished(callback)
	self.FinishedCallbacks[callback] = true
end

function Player:OnFrameReached(frame, callback)
	self.FrameCallbacks[tostring(frame)] = callback
end

function Player:_buildMarkerSequence()
	local sequence = {}

	for frameId in self.Deserializer.markers do
		table.insert(sequence, tonumber(frameId))
	end

	table.sort(sequence)
	self.MarkerSequence = {}
end


function Player:_restore()
	self.Reader = SequentialReader.new(self.Deserializer)	

	self.PartAttachments = {}
	self.FrameState = {}
	self.FrameAdvance = {}
	self.MarkerSequence = {}

	self.CurrentAdvance = 0
	self.CurrentFrame = -1
	self.TimePosition = 0
	
	local instanceOverride = self.Deserializer.targetOverrides
	local instances = self.Deserializer.targets
	
	for instanceId, props in self.Deserializer.defaults do
		local realInstance = instanceOverride[instanceId] 
			or instances[instanceId]
		
		for name, value in props do 
			if table.find(IGNORED_DEFAULTS, name) then
				continue
			end

			ApplyProp(realInstance, name, value, self)
		end
	end
end


function Player:_advance()
	local state = self.FrameState
	local advance = self.FrameAdvance 
	local reader = self.Reader

	while self.CurrentAdvance ~= self.CurrentFrame + FRAME_ADVANCE do
		local currentFrame = self.CurrentAdvance

		local newPoints = reader:requestFrame()
		if newPoints then
			for inst, props in newPoints do
				if not state[inst] then
					state[inst] = {}
				end

				for _, propData in props do
					for _, prop in propData.props do
						local entry = {
							duration = propData.duration,
							prop = prop
						}

						if prop.ease then
							entry.originalDuration = propData.duration	
						end

						state[inst][prop.name] = entry
					end
				end
			end	
		end

		local frameBuffer = {}
		for instanceId, props in state do 
			local instanceEntry = {}

			for name, valueData in props do
				local prop = valueData.prop
				local ease = prop.ease 

				if ease then
					local easeFunc = EaseFuncs.Get({
						Type = ease.type,
						Params = ease.params
					})

					local progress = (valueData.originalDuration - valueData.duration)
					local delta = easeFunc(progress / valueData.originalDuration)
					local interpolate = Interpolator.get(ease.target)

					instanceEntry[name] = interpolate(prop.value, ease.target, delta)
				else 
					instanceEntry[name] = prop.value
				end

				valueData.duration -= 1
				if valueData.duration == 0 then
					props[name] = nil
				end
			end

			frameBuffer[instanceId] = instanceEntry
		end

		advance[tostring(currentFrame)] = frameBuffer
		self.CurrentAdvance += 1
	end
end

local function emitMarkers(track, frameId)
	local markers = track.Deserializer.markers[frameId]
	if not markers then
		return 
	end

	local instanceOverride = track.Deserializer.targetOverrides
	local instances = track.Deserializer.targets

	for markerType, markers in markers do
		for instanceId, markerList in markers do
			local realInstance = instanceOverride[instanceId] 
				or instances[instanceId]
			
			for marker, kfMarkers in markerList do
				local callback = track.MarkerCallbacks[marker]
				
				if callback then
					task.spawn(
						callback,
						realInstance,
						markerType == "finish",
						kfMarkers
					)
				end
			end
		end
	end
end

local function update(delta)
	for track in PlayingTracks do
		local currentFrame = math.floor(track.TimePosition * track.FrameRate)
		local lastFrame = track.CurrentFrame

		delta = math.min(delta, 1 / track.FrameRate)

		if currentFrame > track.Length then
			for callback in track.FinishedCallbacks do
				task.spawn(callback)
			end
			
			PlayingTracks[track] = nil
			continue
		end
		
		if lastFrame == currentFrame then
			track.TimePosition += delta
			continue
		end

		local frameId = tostring(currentFrame)

		local frame = track.FrameAdvance[frameId]

		local frameCallback = track.FrameCallbacks[frameId]
		if frameCallback then
			task.spawn(frameCallback)
		end

		local instanceOverride = track.Deserializer.targetOverrides
		local instances = track.Deserializer.targets
		
		if frame then			
			for instanceId, props in frame do
				local realInstance = instanceOverride[instanceId] 
					or instances[instanceId]

				if realInstance then
					for name, value in props do
						ApplyProp(realInstance, name, value, track)
					end
				else
					warn("failed to play track, unknown instance", instanceId)
					PlayingTracks[track] = nil
				end
			end
		end
		
		for inst, attach in track.PartAttachments do
			inst.CFrame = attach.CFrame
		end
	
		while true do
			local marker = track.MarkerSequence[1]

			if typeof(marker) ~= "number" or currentFrame < marker then
				break
			end

			emitMarkers(track, tostring(marker))
			table.remove(track.MarkerSequence, 1)
		end
		
		track.FrameAdvance[tostring(lastFrame)] = nil
		track.CurrentFrame = currentFrame
		track.TimePosition += delta
	end
end

local function framePregen(delta)
	for track in PlayingTracks do
		if track.CurrentAdvance == track.CurrentFrame + FRAME_ADVANCE then
			continue
		end

		track:_advance()
	end
end

RunService:BindToRenderStep("UPDATE_MOON", Enum.RenderPriority.Camera.Value, update)
RunService:BindToSimulation(framePregen, FRAME_ADVANCE_HZ, Enum.RenderPriority.Camera.Value + 2)


return Player