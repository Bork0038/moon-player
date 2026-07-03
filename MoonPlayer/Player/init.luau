--!optimize 2
const FRAME_ADVANCE_HZ = Enum.StepFrequency.Hz15


const HttpService = game:GetService("HttpService")
const LogService = game:GetService("LogService")
const RunService = game:GetService("RunService")

const Interpolator = require("./Interpolator")
const ApplyProp = require("@self/ApplyProp")
const EaseFuncs = require("./EaseFuncs")
const Compiler = require("./Compiler")
const Flags = require("./Flags")
const Signal = require("./Signal")
const Types = require("./Types")

const SequentialReader = Compiler.SequentialReader
const Deserializer = Compiler.Deserializer

const PlayingTracks = {}
const IGNORED_DEFAULTS = { "Emit", "CFrame" }

const Player = {}


function Player.new(track: Types.MoonSave, flags: Flags.Flag?)
	const Data = HttpService:JSONDecode(track.Value)
	local playerFlags = Flags.Player.Default

	if flags then
		playerFlags += flags
	end

	const self = setmetatable({
		Data = Data,
		Deserializer = Deserializer.new(track, playerFlags),
		Reader = nil,

		OriginalFrameRate = Data.Information.FrameRate or 60,
		FrameRate = Data.Information.FrameRate or 60,
		Length = Data.Information.Length,

		CurrentFrame = -1,
		CurrentAdvance = 0,
		TimePosition = 0,

		FrameAdvance = {},
		FrameState = {},
		
		MarkerSequence = {},
		PartAttachments = {},

		Finished = Signal.new(),
		MarkerSignals = {},
		FrameSignals = {},
		ClassNames = {},
		JointCFrames = {},

		Flags = playerFlags,
	}, { __index = Player })

	self:_handleBaseFlags()

	return self
end

function Player:Stop(): ()
	PlayingTracks[self] = nil
	self:_restore()
end

function Player:Resume(): ()
	PlayingTracks[self] = true
end

function Player:Destroy(): ()
	PlayingTracks[self] = nil

	self.Finished:Destroy()

	for _, signal in self.MarkerSignals do
		signal:Destroy()
	end

	for _, signal in self.FrameSignals do
		signal:Destroy()
	end

	table.clear(self.MarkerSignals)
	table.clear(self.FrameSignals)
end

function Player:Play(): ()
	self:_restore()

	self:_buildMarkerSequence()
	self:_advance()
	self:_setClassNames()
	
	PlayingTracks[self] = true
end

function Player:SetDuration(duration: number): ()
    const originalFrameRate = self.OriginalFrameRate
    const originalLength = self.Data.Information.Length
    const originalDuration = originalLength / originalFrameRate

    self.FrameRate = originalFrameRate * (originalDuration / duration)
	self.Flags.FrameAdvance = math.max(
		self.Flags.FrameAdvance,
		self.FrameRate / originalFrameRate
	)
end

function Player:ReplaceInstance(original: Instance | string, new: Instance): ()
	return self.Deserializer:overrideInstance(original, new)
end


type PlayerImpl = typeof(Player.new(nil :: any, nil :: any))
type SignalMapName = "MarkerSignals" | "FrameSignals"

const function getOrCreateSignal<T...>(player: PlayerImpl, mapName: SignalMapName, key: string): Signal.Signal<T...>
	const map = (player :: any)[mapName]

	local signal = map[key]
	if not signal then
		signal = Signal.new()
		map[key] = signal
	end

	return signal :: Signal.Signal<T...>
end

function Player:GetMarkerReachedSignal(name: string): Signal.Signal<Instance, boolean, { [string]: string }>
	return getOrCreateSignal(self, "MarkerSignals", name)
end

function Player:GetFrameReachedSignal(frame: number): Signal.Signal<()>
	return getOrCreateSignal(self, "FrameSignals", tostring(frame))
end

function Player:OnMarkerReached(name: string, callback: (Instance, boolean, { [string]: string }) -> ()): RBXScriptConnection
	return self:GetMarkerReachedSignal(name):Connect(callback)
end

function Player:OnFinished(callback: () -> ()): RBXScriptConnection
	return self.Finished:Connect(callback)
end

function Player:OnFrameReached(frame: number, callback: () -> ()): RBXScriptConnection
	return self:GetFrameReachedSignal(frame):Connect(callback)
end

function Player:_buildMarkerSequence(): ()
	const sequence = {}

	for frameId in self.Deserializer.markers do
		table.insert(sequence, tonumber(frameId))
	end

	table.sort(sequence)
	self.MarkerSequence = sequence
end


function Player:_restore()
	self.Reader = SequentialReader.new(self.Deserializer)	

	self.PartAttachments = {}
	self.FrameState = {}
	self.FrameAdvance = {}
	self.MarkerSequence = {}
	self.ClassNames = {}
	self.JointCFrames = {}

	self.CurrentAdvance = 0
	self.CurrentFrame = -1
	self.TimePosition = 0
	
	const instanceOverride = self.Deserializer.targetOverrides
	const instances = self.Deserializer.targets
	
	for instanceId, props in self.Deserializer.defaults do
		const realInstance = instanceOverride[instanceId] 
			or instances[instanceId]
		
		if not realInstance then
			if self.Flags.StrictMode then
				return LogService:Error('[MoonPlayer/Player]: failed to restore track to default instance "{instanceId}" is missing', {instanceId = instanceId})
			end

			if self.Flags.LogUnresolvedInstances then
				LogService:Warn('[MoonPlayer/Player]: failed to resolve instance: "{instanceId}"', {instanceId = instanceId})
			end

			continue
		end 

		if realInstance:IsA("BasePart") then
			self.JointCFrames[instanceId] = realInstance.CFrame
		end

		for name, value in props do 
			if table.find(IGNORED_DEFAULTS, name) then
				continue
			end

			ApplyProp(realInstance, realInstance.ClassName, name, value, self)
		end
	end

	return nil
end

function Player:_setClassNames(): ()
	const classNames = {}

	const instanceOverride = self.Deserializer.targetOverrides
	const instances = self.Deserializer.targets

	for id, instance in instances do
		classNames[id] = instance.ClassName
	end

	for id, instance in instanceOverride do
		classNames[id] = instance.ClassName
	end

	self.ClassNames = classNames
end

function Player:_handleBaseFlags(): ()
	const flags = self.Flags 

	if flags.Duration ~= -1 then
		self:SetDuration(flags.Duration)
	end
end

function Player:_checkApplyPropTransformer(instanceId: string, name: string, value: any): any
	const serializerFlags = self.Data.Information.Flags
	if serializerFlags and serializerFlags.RelativeCFrameOffset == false then
		return value
	end

	if name == "CFrame" then
		const cframe = self.JointCFrames[instanceId]
		if not cframe then
			return value
		end 

		return cframe * value
	elseif name == "Position" then
		const cframe = self.JointCFrames[instanceId]
		if not cframe then
			return value
		end 

		return value + cframe.Position
	end 

	return value
end

function Player:_advance(): ()
	const state = self.FrameState
	const advance = self.FrameAdvance 
	const reader = self.Reader
	
	while self.CurrentAdvance ~= self.CurrentFrame + self.Flags.FrameAdvance do
		const currentFrame = self.CurrentAdvance

		const newPoints = reader:requestFrame()
		if newPoints then
			for inst, props in newPoints do
				if not state[inst] then
					state[inst] = {}
				end

				for _, propData in props do
					for _, prop in propData.props do
						const entry = {
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

		const frameBuffer = {}
		
		for instanceId, props in state do 
			if table.find(self.Deserializer.unresolvedInstances, instanceId) then
				continue
			end 
			
			const instanceEntry = {}

			for name, valueData in props do
				const prop = valueData.prop
				const ease = prop.ease 
				const value = self:_checkApplyPropTransformer(instanceId, name, prop.value)

				if ease then
					const easeFunc = EaseFuncs.Get({
						Type = ease.type,
						Params = ease.params
					})

					const progress = (valueData.originalDuration - valueData.duration)
					const delta = easeFunc(progress / valueData.originalDuration)
					const target = self:_checkApplyPropTransformer(instanceId, name, ease.target)

					const interpolate = Interpolator.get(target)

					instanceEntry[name] = interpolate(value, target, delta)
				else 
					instanceEntry[name] = value
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

const function emitMarkers(track: any, frameId: string): ()
	const markers = track.Deserializer.markers[frameId]
	if not markers then
		return 
	end

	const instanceOverride = track.Deserializer.targetOverrides
	const instances = track.Deserializer.targets

	for markerType, subMarkers in markers do
		for instanceId, markerList in subMarkers do
			const realInstance = instanceOverride[instanceId] 
				or instances[instanceId]
			
			for marker, kfMarkers in markerList do
				const signal = track.MarkerSignals[marker]

				if signal then
					signal:Fire(
						realInstance,
						markerType == "finish",
						kfMarkers
					)
				end
			end
		end
	end
end

const function update(delta: number): ()
	for track in PlayingTracks do
		const currentFrame = math.floor(track.TimePosition * track.FrameRate)
		const lastFrame = track.CurrentFrame

		delta = math.min(delta, 1 / track.OriginalFrameRate)

		if currentFrame > track.Length then
			track.Finished:Fire()

			PlayingTracks[track] = nil
			continue
		end
		
		if lastFrame == currentFrame then
			track.TimePosition += delta
			continue
		end

		const frameId = tostring(currentFrame)
		const instanceOverride = track.Deserializer.targetOverrides
		const classNames = track.ClassNames
		const instances = track.Deserializer.targets
		
		for frameNum = lastFrame + 1, currentFrame do
			const currentFrameId = tostring(frameNum)
			const frame = track.FrameAdvance[currentFrameId]

			if not frame then
				continue
			end

			for instanceId, props in frame do
				const realInstance = instanceOverride[instanceId] 
					or instances[instanceId]

				if realInstance then
					const className = classNames[instanceId]

					for name, value in props do
						ApplyProp(
							realInstance, 
							className,
							name, 
							value, 
							track
						)
					end
				else
					LogService:Warn("[MoonPlayer/Player]: failed to play track, unknown instance {instanceId}", {instanceId = instanceId})
					PlayingTracks[track] = nil
				end
			end

			track.FrameAdvance[currentFrameId] = nil
		end 
	
		const frameSignal = track.FrameSignals[frameId]
		if frameSignal then
			frameSignal:Fire()
		end
		
		while true do
			const marker = track.MarkerSequence[1]

			if typeof(marker) ~= "number" or currentFrame < marker then
				break
			end

			task.defer(emitMarkers, track, tostring(marker))
			table.remove(track.MarkerSequence, 1)
		end

		track.CurrentFrame = currentFrame
		track.TimePosition += delta
	end
end

const function updateAttachments(): ()
	for track in PlayingTracks do
		for inst, attach in track.PartAttachments do
			inst.CFrame = attach.CFrame
		end
	end
end 

const function framePregen(delta: number): ()
	for track in PlayingTracks do
		if track.CurrentAdvance == track.CurrentFrame + track.Flags.FrameAdvance then
			continue
		end

		track:_advance()
	end
end

RunService.PreAnimation:Connect(update)
RunService:BindToRenderStep("UPDATE_MOON_ATTACHMENTS", Enum.RenderPriority.Camera.Value + 1, updateAttachments)
RunService:BindToSimulation(framePregen, FRAME_ADVANCE_HZ, Enum.RenderPriority.Last.Value)

return Player