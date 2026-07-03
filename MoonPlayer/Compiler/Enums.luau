--!optimize 2
const Enums = {
	PropertyType = {
		Bool = 0x00,
		CFrame = 0x01,
		Number = 0x02,
		Color3 = 0x03,
		String = 0x04,
		ObjectValue = 0x05,
		Value = 0x06,
		Nil = 0x07,
		Vector3 = 0x08,
		ColorSequence = 0x09,
		NumberSequence = 0x0A
	}
}

return Enums :: typeof(Enums)