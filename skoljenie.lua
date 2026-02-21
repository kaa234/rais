local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")   

local localPlayer = Players.LocalPlayer




local MAX_FRICTION       = 2.0
local FRICTION_WEIGHT    = 1000   
local DENSITY            = 2
local ELASTICITY         = 0
local ELASTICITY_WEIGHT  = 0


local MASSLESS_DENSITY         = 0      
local MASSLESS_FRICTION        = 0
local MASSLESS_ELASTICITY      = 0
local MASSLESS_FRICTION_WEIGHT = 1000   
local MASSLESS_ELASTICITY_WEIGHT = 0



local processedParts = {}   
local connections    = {}   
local heldParts      = {}   




local function applyMaxFriction(part)
	if not (part:IsA("BasePart") or part:IsA("MeshPart")) then return end
	if processedParts[part] then return end

	part.CustomPhysicalProperties = PhysicalProperties.new(
		DENSITY,
		MAX_FRICTION,
		ELASTICITY,
		FRICTION_WEIGHT,      
		ELASTICITY_WEIGHT
	)

	processedParts[part] = true
end


local function resetPart(part)
	if part:IsA("BasePart") or part:IsA("MeshPart") then
		part.CustomPhysicalProperties = nil
		processedParts[part] = nil
	end
end


local function makePartMassless(part)
	if not (part:IsA("BasePart") or part:IsA("MeshPart")) then return end

	part.CustomPhysicalProperties = PhysicalProperties.new(
		MASSLESS_DENSITY,
		MASSLESS_FRICTION,
		MASSLESS_ELASTICITY,
		MASSLESS_FRICTION_WEIGHT,   
		MASSLESS_ELASTICITY_WEIGHT
	)

	heldParts[part] = true
end


local function restorePartMass(part)
	if part:IsA("BasePart") or part:IsA("MeshPart") then
		part.CustomPhysicalProperties = nil
		heldParts[part] = nil
	end
end



local function processCharacter(character)
	if not character then return end

	
	if connections.character then
		connections.character:Disconnect()
	end

	
	character:WaitForChild("HumanoidRootPart", 10)

	
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") or part:IsA("MeshPart") then
			applyMaxFriction(part)
		end
	end

	
	local descendantConn
	descendantConn = character.DescendantAdded:Connect(function(descendant)
		task.spawn(function()
			task.wait(0.1)          
			applyMaxFriction(descendant)
		end)
	end)
	connections.character = descendantConn
end

local function onCharacterAdded(character)
	task.wait(0.5)   
	processCharacter(character)
end

if localPlayer.Character then
	onCharacterAdded(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacterAdded)


local heldObjectsConnection
local lastHeldCheck = 0
heldObjectsConnection = RunService.Heartbeat:Connect(function()
	local now = tick()

	if now - lastHeldCheck < 0.1 then return end
	lastHeldCheck = now

	local character = localPlayer.Character
	if not character then return end

	
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Weld") or desc:IsA("WeldConstraint") then
			local p0, p1 = desc.Part0, desc.Part1

			
			if p0 and not p0:IsDescendantOf(character) then
				makePartMassless(p0)
			end
			
			if p1 and not p1:IsDescendantOf(character) then
				makePartMassless(p1)
			end
		end
	end

	
	for part, _ in pairs(heldParts) do
		local stillHeld = false

		for _, desc in ipairs(character:GetDescendants()) do
			if desc:IsA("Weld") or desc:IsA("WeldConstraint") then
				if desc.Part0 == part or desc.Part1 == part then
					local other = (desc.Part0 == part) and desc.Part1 or desc.Part0
					if other and other:IsDescendantOf(character) then
						stillHeld = true
						break
					end
				end
			end
		end

		if not stillHeld then
			restorePartMass(part)
		end
	end
end)




local applyToWorld = false
local function applyFrictionToWorld()
	if not applyToWorld then return end

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("BasePart") or obj:IsA("MeshPart") then
			applyMaxFriction(obj)
		end
	end

	workspace.ChildAdded:Connect(function(child)
		task.wait(1)
		if child:IsA("BasePart") or child:IsA("MeshPart") then
			applyMaxFriction(child)
		end
	end)
end
