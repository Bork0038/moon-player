export type Deserializer = {
	new: (MoonSave: StringValue) -> Deserializer,
}

export type Serializer = {
	new: (MoonSave: StringValue, CompressionLevel: number?) -> Serializer,
	
	Build: (Serializer) -> StringValue
}

export type Compiler = {
	Deserializer: Deserializer,
	Serializer: Serializer
}

export type AnimationPlayer = {
	new: (
		MoonSave: StringValue, 
		Overrides: { [string]: Instance }?
	) -> AnimationPlayer,
	
	Play: (AnimationPlayer) -> (),
	Stop: (AnimationPlayer) -> (),
	Resume: (AnimationPlayer) -> (),
	
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
		Callback: (target: Instance, isFinished: boolean) -> ()
	) -> ()
}

export type MoonPlayer = {
	Compiler: Compiler,	
	Player: AnimationPlayer
}

return {}