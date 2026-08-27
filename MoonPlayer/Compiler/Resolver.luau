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
	const nodes = {}
	const nodeByJoint = {}
	const nodeByCarrier = {}

	local function insertNode(inst: Instance, name: string, carrier: Instance): ()
		const node = {
			inst = inst,
			name = name,
			children = {}
		}

		table.insert(nodes, node)
		nodeByJoint[inst] = node
		nodeByCarrier[carrier] = node
	end

	for _, inst in hier:QueryDescendants("Motor6D") do
		const part1 = inst.Part1
		const name = part1 and part1.Name

		if not part1 or not name then
			continue
		end

		insertNode(inst, name, part1)
	end

	for _, inst in hier:QueryDescendants("Bone") do
		insertNode(inst, inst.Name, inst)
	end

	for _, node in nodes do
		const joint = node.inst

		if joint:IsA("Motor6D") then
			const part0 = joint.Part0
			const parentNode = part0 and nodeByCarrier[part0]

			if parentNode then
				table.insert(parentNode.children, node)
			end
		elseif joint:IsA("Bone") then
			const parentNode = nodeByCarrier[joint.Parent]

			if parentNode then
				table.insert(parentNode.children, node)
			end
		end
	end

	for _, node in nodes do
		table.sort(node.children, function(a: any, b: any): boolean
			return a.name < b.name
		end)
	end

	const hiers = {}
	local function recurse(node: any, path: string, visited: { [Instance]: boolean }): ()
		if visited[node.inst] then
			return
		end

		visited[node.inst] = true
		hiers[path] = node.inst

		for _, child in node.children do
			recurse(child, path .. "." .. child.name, visited)
		end

		visited[node.inst] = nil
	end

	for _, node in nodes do
		recurse(node, node.name, {})
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