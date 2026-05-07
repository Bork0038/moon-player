local SpecialProps do
	local ModelInstance = Instance.new("Model")
	local ParticleEmitterInstance = Instance.new("ParticleEmitter")

	SpecialProps = {
		Camera = {
			Advanced = {
				AttachToPart = function(inst, value, player)
					player.PartAttachments[inst] = value
				end
			}
		},

		ParticleEmitter = {
			Simple = {
				Clear = ParticleEmitterInstance.Clear,
				Emit = ParticleEmitterInstance.Emit,
			}
		},

		Model = {
			Simple = {
				Scale = ModelInstance.ScaleTo,
				CFrame = ModelInstance.PivotTo,
			},
		},
	}
end

local function ApplyProp(inst, name, value, player)
	local className = inst.ClassName
	local specialClass = SpecialProps[className]

	if not specialClass then
		inst[name] = value
		return
	end

	if specialClass.Simple then
		local simpleHandler = specialClass.Simple[name]

		if simpleHandler then
			return simpleHandler(inst, value)
		end
	end

	if specialClass.Advanced then
		local advancedHandler = specialClass.Advanced[name]

		if advancedHandler then
			return advancedHandler(inst, value, player)
		end
	end

	inst[name] = value
end

return ApplyProp
