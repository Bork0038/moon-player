# MoonPlayer

MoonPlayer is an experimental Moon Animator save player
Due to its experimental state expect bugs

Credit to [MaximumADHD/Moonlite](https://github.com/MaximumADHD/Moonlite) for interpolator + joint hierarchy resolver

## Features

- Compiles MoonSave into compressed binary format
- Uses a frame buffer to avoid having the entire track loaded into memory

## Installation

```powershell
aftman install
rojo serve place.project.json
```

`place.project.json` syncs the package to `ReplicatedStorage.MoonPlayer`.

## Runtime Usage

`Player.new(track, flags?)` expects a compiled MoonSave. Flags are built from
`MoonPlayer.Flags.Player` and combined with `+`.

### Instance overrides

Use the `InstanceOverrides` flag to retarget an animation onto a different rig/model. The
key is the dot-path of an animated instance and the value is the instance to use instead.
An override **cascades**: everything underneath the overridden instance — descendant items,
rig joints, and `ObjectValue` references — is resolved relative to the new instance.

```luau
const Flags = MoonPlayer.Flags.Player

const player = MoonPlayer.Player.new(track, Flags.InstanceOverrides({
	["Workspace.Dummy"] = workspace.OtherDummy,
}))
```

Overrides can also be applied after creation with `player:ReplaceInstance(original, new)`,
where `original` is an Instance or its dot-path. Call it before `Play()`.

Example:

```luau
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const MoonPlayer = require(ReplicatedStorage.MoonPlayer)
const track = ReplicatedStorage.Animations.Wave

const player = MoonPlayer.Player.new(track, MoonPlayer.Flags.Player.InstanceOverrides({
	["Workspace.Dummy"] = workspace.Dummy,
}))

player:GetMarkerReachedSignal("Footstep"):Connect(function(target, isFinished, kfMarkers)
	print("marker", target, isFinished)
end)

player.Finished:Connect(function()
	print("finished")
end)

player:GetFrameReachedSignal(100):Connect(function()
	print("frame 100 reached")
end)

player:Play()
```

Main methods/signals:

- `Play()` rewinds the track, restores default values, and starts playback.
- `Stop()` stops playback and restores defaults.
- `Resume()` continues playback without rewinding.
- `Destroy()` removes the track from playback and destroys the player's signals; call it when you're done with a player.
- `Finished` is a signal fired when the track ends: `player.Finished:Connect(callback)`.
- `GetMarkerReachedSignal(name)` returns a signal fired with `(targetInstance, isFinishedMarker, kfmarkers)` when the named marker is reached.
- `GetFrameReachedSignal(frame)` returns a signal fired when the target frame has been reached.
- `OnFinished(callback)` / `OnMarkerReached(name, callback)` / `OnFrameReached(frame, callback)` are callback shorthands that connect to the corresponding signal and return the `RBXScriptConnection`.
- `ReplaceInstance(original, new)` remaps `original` (an Instance or dot-path) to `new`, cascading to descendants, joints, and object references. Call before `Play()`.

## Compiling a Track

The compilation process should only be done once in studio before publishing to avoid having to store the entire MoonSave in game

- use `Serializer.new(moonSave, flags?)` + `serializer:build()` to compile a MoonSave

```luau
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const MoonPlayer = require(ReplicatedStorage.Packages.MoonPlayer)

const Serializer = MoonPlayer.Compiler.Serializer
const Flags = MoonPlayer.Compiler.Flags

const sourceSave = workspace.MoonSave

const flags = Flags.CompressionLevel(7) + Flags.CFrameSerializeMethod.Bytes("F32", "F16")
const compiledTrack = MoonPlayer.Compiler.Serializer.new(sourceSave, flags):Build()

compiledTrack.Name = "Wave"
compiledTrack.Parent = ReplicatedStorage.Animations
```
