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

`Player.new(track, instanceOverrides?)` expects a compiled MoonSave

Example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoonPlayer = require(ReplicatedStorage.MoonPlayer)
local track = ReplicatedStorage.Animations.Wave

local player = MoonPlayer.Player.new(track, {
	["Workspace.Dummy"] = workspace.Dummy,
})

player:OnMarkerReached("Footstep", function(target, isFinished, kfMarkers)
	print("marker", target, isFinished)
end)

player:OnFinished(function()
	print("finished")
end)

player:OnFrameReached(100, function()
	print("frame 100 reached")
end)

player:Play()
```

Main methods:

- `Play()` rewinds the track, restores default values, and starts playback.
- `Stop()` stops playback and restores defaults.
- `Resume()` continues playback without rewinding.
- `OnFinished(callback)` runs the callback when the track ends.
- `OnMarkerReached(name, callback)` runs `callback(targetInstance, isFinishedMarker, kfmarkers)` when a named marker is reached.
- `OnFrameReached(frame, callback)` runs `callback()` when a target frame has been reached

## Compiling a Track

The compilation process should only be done once in studio before publishing to avoid having to store the entire MoonSave in game

- use `Serializer.new(moonSave, compressionLevel?)` + `serializer:build()` to compile a MoonSave

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoonPlayer = require(ReplicatedStorage.Packages.MoonPlayer)

local Serializer = MoonPlayer.Compiler.Serializer
local Flags = MoonPlayer.Compiler.Flags

local sourceSave = workspace.MoonSave

local flags = Flags.CompressionLevel(7) + Flags.CFrameSerializeMethod.Bytes
local compiledTrack = MoonPlayer.Compiler.Serializer.new(sourceSave, flags):Build()

compiledTrack.Name = "Wave"
compiledTrack.Parent = ReplicatedStorage.Animations
```
