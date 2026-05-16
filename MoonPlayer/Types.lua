local Flags = require("./Compiler/Flags")

export type Deserializer = {
	new: (MoonSave: StringValue) -> Deserializer,
}

export type Serializer = {
	new: (
		MoonSave: StringValue, 
		Flags: Flags.Flags?
	) -> Serializer,
	
	Build: (Serializer) -> StringValue,
}

export type Compiler = {
	Deserializer: Deserializer,
	Serializer: Serializer,

	Flags: Flags.Flags
}

export type AnimationPlayer = {
	new: (
		MoonSave: StringValue, 
		Overrides: { [string]: Instance }?
	) -> AnimationPlayer,
	
	Play: (AnimationPlayer) -> (),
	Stop: (AnimationPlayer) -> (),
	Resume: (AnimationPlayer) -> (),
	SetDuration: (AnimationPlayer, Duration: number) -> (),
	
	ReplaceInstance: (
		AnimationPlayer, 
		Original: Instance | string,
		New: Instance
	) -> (),

	OnFinished: (AnimationPlayer, Callback: () -> any) -> (),

	OnFrameReached: (
		AnimationPlayer, 
		Frame: number, 
		Callback: () -> any
	) -> (),

	OnMarkerReached: (
		AnimationPlayer, 
		MarkerName: string, 
		Callback: (
			Target: Instance, 
			IsFinished: boolean,
			KFMarkers: { [string]: string }
		) -> ()
	) -> ()
}

export type MoonPlayer = {
	Compiler: Compiler,	
	Player: AnimationPlayer
}

return {}