-- stolen from moonlite
local function fastResolvePath(path: MoonAnimPath, root)
	local tbl = {}
	
	for i = 2, #path.InstanceNames do
		local class = path.InstanceTypes[i]
		local name  = path.InstanceNames[i]
		
		table.insert(tbl, `{class}[Name = "{name}"]`)
	end
	
	return root:QueryDescendants(table.concat(tbl, " > "))[1]
end

local function resolveAnimPath(path: MoonAnimPath?, root: Instance?): Instance?
	if not path then
		return nil
	end

	local numSteps = #path.InstanceNames
	local current: Instance = root or game

	local success = pcall(function()
		for i = 2, numSteps do
			local name = path.InstanceNames[i]
			local class = path.InstanceTypes[i]

			local nextInst = (current :: any)[name]
			assert(typeof(nextInst) == "Instance")
			assert(nextInst.ClassName == class)

			current = nextInst
		end
	end)

	if success then
		return current
	end
	
	local success, data = pcall(fastResolvePath, path, current)

	if success and typeof(data) == "Instance" then
		return data
	end

	return nil
end

local function resolveJoints(target: Instance)
	local jointsByHier = {} :: { [string]: MoonJointInfo }
	local byCanon = {} :: { [string]: MoonJointInfo }

	local function canon(s: string): string
		s = tostring(s or "")
		s = s:gsub("[\226\128\152\226\128\153]", "'")
		s = s:gsub("%s+", " ")
		s = s:gsub("^%s+", ""):gsub("%s+$", "")
		return s:lower()
	end

	local function addKey(key: string, info: MoonJointInfo)
		jointsByHier[key] = info
		byCanon[canon(key)] = info
	end

	local list = {} :: { MoonJointInfo }

	for _, d: Instance in ipairs(target:GetDescendants()) do
		if d:IsA("Motor6D") then
			local j = d :: Motor6D
			local info: MoonJointInfo = { Name = j.Name, Joint = j, Children = {} }
			table.insert(list, info)
		elseif d:IsA("Bone") then
			local b = d :: Bone
			local info: MoonJointInfo = { Name = b.Name, Joint = b, Children = {} }
			table.insert(list, info)
		end
	end

	local jointToInfo = {} :: { [Instance]: MoonJointInfo }
	for _, info in ipairs(list) do
		jointToInfo[info.Joint] = info
	end

	for _, info in ipairs(list) do
		local joint = info.Joint
		if joint:IsA("Motor6D") then
			local p0 = (joint :: Motor6D).Part0
			if p0 then
				for _, other in ipairs(list) do
					local oj = other.Joint
					if oj:IsA("Motor6D") then
						local op1 = (oj :: Motor6D).Part1
						if op1 == p0 then
							other.Children[info.Name] = info
							info.Parent = other
							break
						end
					elseif oj:IsA("Bone") then
						if (oj :: Bone).Parent == p0 then
							other.Children[info.Name] = info
							info.Parent = other
							break
						end
					end
				end
			end
		elseif joint:IsA("Bone") then
			local parent = (joint :: Bone).Parent
			if parent then
				local parentInfo = jointToInfo[parent]
				if parentInfo then
					parentInfo.Children[info.Name] = info
					info.Parent = parentInfo
				end
			end
		end
	end

	for _, info in ipairs(list) do
		local j = info.Joint
		if j:IsA("Motor6D") then
			local m = j :: Motor6D
			local p0 = m.Part0
			local p1 = m.Part1
			if p0 then addKey(p0.Name .. "." .. m.Name, info) end
			if p1 then addKey(p1.Name .. "." .. m.Name, info) end
			addKey(m.Name, info)
			if p0 and p1 then
				addKey(p0.Name .. "." .. p1.Name, info)
				addKey(p0.Name .. "." .. m.Name .. "." .. p1.Name, info)
			end
		else
			local b = j :: Bone
			addKey(b.Name, info)
			local hier = b.Name
			local cur = b.Parent
			while cur and cur ~= target do
				hier = cur.Name .. "." .. hier
				cur = cur.Parent
			end
			addKey(hier, info)
		end
	end

	local function findSmart(tree: string): MoonJointInfo?
		if jointsByHier[tree] then return jointsByHier[tree] end
		local c = canon(tree)
		if byCanon[c] then return byCanon[c] end

		for k, v in pairs(jointsByHier) do
			if k:sub(-#tree) == tree or tree:sub(-#k) == k then
				return v
			end
		end

		for k, v in pairs(byCanon) do
			if k:sub(-#c) == c or c:sub(-#k) == k then
				return v
			end
		end

		return nil
	end

	return jointsByHier, findSmart
end


return {
	resolveJoints = resolveJoints,
	resolveAnimPath = resolveAnimPath
}
