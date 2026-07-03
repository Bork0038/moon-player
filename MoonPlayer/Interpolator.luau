--!optimize 2
const Interpolator = {}

const CONSTANT_INTERPS = {
	["Instance"] = true,
	["boolean"] = true,
	["string"] = true,
	["nil"] = true,
}

const function lerp(a: any, b: any, t: number): any
	if type(a) == "number" then
		assert(type(b) == "number")
		return math.lerp(a, b, t)
	else
		return (a :: any):Lerp(b, t)
	end
end

function Interpolator.get(value: any): (start: any, goal: any, delta: number) -> any
	if typeof(value) == "ColorSequence" then
		return function(start: ColorSequence, goal: ColorSequence, t: number): ColorSequence
			const value = lerp(start.Keypoints[1].Value, goal.Keypoints[1].Value, t)
			return ColorSequence.new(value)
		end
	elseif typeof(value) == "NumberSequence" then
		return function(start: NumberSequence, goal: NumberSequence, t: number): NumberSequence
			const value = lerp(start.Keypoints[1].Value, goal.Keypoints[1].Value, t)
			return NumberSequence.new(value)
		end
	elseif typeof(value) == "NumberRange" then
		return function(start: NumberRange, goal: NumberRange, t: number): NumberRange
			const value = lerp(start.Min, goal.Min, t)
			return NumberRange.new(value)
		end
	elseif CONSTANT_INTERPS[typeof(value)] then
		return function(start: any, goal: any, t: number): any
			if t >= 1 then
				return goal
			else
				return start
			end
		end
	end

	return lerp
end

return Interpolator