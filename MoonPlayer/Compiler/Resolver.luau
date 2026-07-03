--!optimize 2
local __index do
	xpcall(function(...)
		return game.MoonPlayer
	end, function(...)
		__index = debug.info(2, "f")
	end)
end

const function mergePath(path: { InstanceNames: { string }, InstanceTypes: { string } }, start: number, finish: number): string
	return table.concat(path.InstanceNames, ".", start, finish)
end

const function fastResolvePath(path: { InstanceNames: { string }, InstanceTypes: { string } }, root: Instance): Instance?
	const tbl = {}

	for i = 2, #path.InstanceNames do
		const class = path.InstanceTypes[i]
		const name = path.InstanceNames[i]

		table.insert(tbl, `{class}[Name = "{name}"]`)
	end

	return root:QueryDescendants(table.concat(tbl, " > "))[1]
end


const Resolver = {}

function Resolver.new(overrides: { [string]: Instance }, excluded: { string })
	const self = {
		cache = {},
		internalCache = {},
		excluded = excluded,
	}

	for name, inst in overrides do
		self.cache[name] = inst
		self.internalCache[name] = inst
	end 

	return setmetatable(self, {
		__index = Resolver
	})
end

function Resolver:resolveJoints(hier: Instance): { [string]: Instance }
	const joints = {}

	for _, inst in hier:QueryDescendants("Motor6D") do
		const part1 = inst.Part1 
		const name = part1 and part1.Name

		if not name then
			continue
		end 

		joints[name] = {
			inst = inst,
			children = {}
		}
	end

	for _, inst in hier:QueryDescendants("Bone") do
		joints[inst.Name] = {
			inst = inst,
			children = {}
		}
	end

	for name, data in joints do
		const joint = data.inst
		const class = joint.ClassName
		
		if class == "Motor6D" then
			const part0 = joint.part0
			if not part0 then
				continue
			end 

			const data0 = joints[part0.Name]
			if not data0 then
				continue
			end 

			data0.children[name] = data
		elseif class == "Bone" then
			const parentBone = joints[joint.Parent.Name]
			if not parentBone then
				continue
			end

			parentBone.children[name] = data
		end
	end

	const hiers = {}
	local function recurse(name: string, joint: any, path: string): ()
		for childName, childJoint in joint.children do
			const newPath = path .. "." .. childName
			hiers[newPath] = childJoint.inst

			recurse(childName, childJoint, newPath)
		end
	end

	for name, data in joints do
		hiers[name] = data.inst
		
		recurse(name, data, name)
	end

	return hiers
end 

function Resolver:resolveInstance(path: { InstanceNames: { string }, InstanceTypes: { string } }, root: Instance?): Instance?
	root = root or game

	if tostring(path.InstanceNames[1]):lower() == "game" then
		table.remove(path.InstanceNames, 1)
		table.remove(path.InstanceTypes, 1)
	end 

	const key = mergePath(path, 1, #path.InstanceNames)
	const cachedInstance = self.cache[key]

	if self.excluded[key] then
		return 
	end 

	if cachedInstance then
		return cachedInstance
	end

	const names = path.InstanceNames
	const types = path.InstanceTypes
	
	const suffixTypes = { types[#names] }
	const suffixNames = { names[#names] }

	local parentInst = root
	local startIdx = 1

	for i = #names - 1, 1, -1 do
		const mergedPath = mergePath(path, 1, i)
		const cachedInst = self.internalCache[mergedPath]

		if cachedInst then
			parentInst = cachedInst
			startIdx = i + 1
			break
		end

		table.insert(suffixTypes, 1, types[i])
		table.insert(suffixNames, 1, names[i])
	end

	local outputInst
	const suffixCount = #suffixNames

	for i = 1, suffixCount do
		const name = suffixNames[i]
		const type = suffixTypes[i]
		
		local success, inst = pcall(__index, parentInst, name)
		if not success or typeof(inst) ~= "Instance" or inst.ClassName ~= type then
			break
		end

		const instKey = mergePath(path, 1, startIdx + i - 1)

		self.internalCache[instKey] = inst
		parentInst = inst
		
		if i == suffixCount then
			outputInst = inst
		end
	end

	if not outputInst then
		local success, data = pcall(fastResolvePath, path, root :: Instance)

		if success and typeof(data) == "Instance" then
			outputInst = data
		end
	end

	if outputInst then
		self.cache[key] = outputInst
	end

	return outputInst
end

return Resolver