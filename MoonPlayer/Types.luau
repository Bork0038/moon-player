--!optimize 2
const Flags = require("./Flags")
const Signal = require("./Signal")

export type MoonSave = StringValue & {
	frames: StringValue,
	dict: StringValue,
	sequence: StringValue,
	defaults: StringValue,
	markers: StringValue,
	hierarchy: StringValue,
	cframes: Configuration,
}

export type Serializer = {
	new: (
		MoonSave: StringValue,
		Flags: Flags.Flag?
	) -> Serializer,
	
	Build: (Serializer) -> MoonSave,
}

export type Compiler = {
	Serializer: Serializer,

	Flags: Flags.SerializerFlags
}

export type AnimationPlayer = {
	new: (
		MoonSave: MoonSave,
		Flags: Flags.Flag?
	) -> AnimationPlayer,
	
	Play: (AnimationPlayer) -> (),
	Stop: (AnimationPlayer) -> (),
	Resume: (AnimationPlayer) -> (),
	Destroy: (AnimationPlayer) -> (),
	SetDuration: (AnimationPlayer, Duration: number) -> (),
	
	ReplaceInstance: (
		AnimationPlayer, 
		Original: Instance | string,
		New: Instance
	) -> (),

	Finished: Signal.Signal<()>,

	GetFrameReachedSignal: (
		AnimationPlayer,
		Frame: number
	) -> Signal.Signal<()>,

	GetMarkerReachedSignal: (
		AnimationPlayer,
		MarkerName: string
	) -> Signal.Signal<Instance, boolean, { [string]: string }>,

	OnFinished: (AnimationPlayer, Callback: () -> ()) -> RBXScriptConnection,

	OnFrameReached: (
		AnimationPlayer,
		Frame: number,
		Callback: () -> ()
	) -> RBXScriptConnection,

	OnMarkerReached: (
		AnimationPlayer,
		MarkerName: string,
		Callback: (
			Target: Instance,
			IsFinished: boolean,
			KFMarkers: { [string]: string }
		) -> ()
	) -> RBXScriptConnection
}

export type MoonPlayer = {
	Compiler: Compiler,
	Player: AnimationPlayer,
	Flags: Flags.Flags
}

return {}