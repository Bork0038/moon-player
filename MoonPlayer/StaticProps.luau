--!optimize 2
const STATIC_PROPS = {
    Camera = {
		AttachToPart = true,
		LookAtPart = true,
	},

	Humanoid = {
		AddAccessory = true,
		ChangeState = true,
		EquipTool = true,
		MoveTo = true,
		Move = true,
		PlayEmote = true,
		RemoveAccessories = true,
		TakeDamage = true,
		UnequipTools = true,
	},

	ParticleEmitter = {
		Emit = true,
		Clear = true,
	},

	Sound = {
		PlayOnce = true,
		SetTime = true,
		Play = true,
		Resume = true,
		Pause = true,
		Stop = true,
	},
}

return STATIC_PROPS