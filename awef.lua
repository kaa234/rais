local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = workspace
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local on = false
local canGrab = true
local maxDistance = 20
local preGrabDelay = 0
local postGrabDelay = 0.0
local scriptEnabled = true
local indicatorShown = true
local indicator, screenGui
local lastTarget, lastHitTime = nil, 0
local targetMemoryDuration = 0.25
local checkThrottle = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

task.spawn(pcall, function()
	if ReplicatedStorage.GamepassEvents.CheckForGamepass:InvokeServer(20837132) then
		maxDistance = 29.3
	end
end)

local function makeIndicator()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "индикатор"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = indicatorShown
	screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0,200,0,50)
	label.Position = UDim2.new(0.5,-100,0,20)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(0,0,0)
	label.TextColor3 = Color3.new(1,0,0)
	label.TextScaled = true
	label.Font = Enum.Font.SourceSansBold
	label.Text = "триггер врублен"
	label.Visible = false
	label.Parent = screenGui
	return label
end

indicator = makeIndicator()

ReplicatedStorage.GamepassEvents.FurtherReachBoughtNotifier.OnClientEvent:Connect(function()
	maxDistance = 29.3
end)

local function getTarget()
	local c = LocalPlayer.Character
	if not c or not c:FindFirstChild("HumanoidRootPart") then return end
	if Workspace:FindFirstChild("GrabParts") then return end
	local origin, dir = Camera.CFrame.Position, Camera.CFrame.LookVector
	rayParams.FilterDescendantsInstances = {c, Workspace.Terrain}
	local result = Workspace:Raycast(origin, dir * 1000, rayParams)
	if not result then
		local dirs = {
			dir,
			(dir + Vector3.new(0, 0.075, 0)).Unit,
			(dir - Vector3.new(0, 0.075, 0)).Unit
		}
		for _, d in ipairs(dirs) do
			result = Workspace:Raycast(origin, d * 1000, rayParams)
			if result then break end
		end
	end
	if not result then return end
	local hit = result.Instance
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model or not model:FindFirstChildOfClass("Humanoid") or model == c then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum.Health <= 0 then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local dist = (c.HumanoidRootPart.Position - root.Position).Magnitude
	if dist > maxDistance then return end
	return model
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Equals then
		on = false
		scriptEnabled = false
		if indicator then
			indicator.Visible = true
			indicator.Text = "скрипт убит"
			task.delay(1, function()
				if screenGui then
					screenGui.Enabled = false
				end
			end)
		end
	end
	if not scriptEnabled then return end
	if input.KeyCode == Enum.KeyCode.G then
		on = not on
		if indicatorShown then
			indicator.Visible = true
			indicator.Text = on and "триггер врублен" or "триггер оффнут"
			task.delay(0.6, function()
				if indicator then indicator.Visible = false end
			end)
		end
	end
	if input.KeyCode == Enum.KeyCode.LeftBracket then
		indicatorShown = not indicatorShown
		if screenGui then screenGui.Enabled = indicatorShown end
	end
end)

local lastCheck = 0
RunService.Heartbeat:Connect(function()
	if not on or not canGrab or not scriptEnabled then return end
	if UserInputService:GetFocusedTextBox() then return end
	if tick() - lastCheck < checkThrottle then return end
	lastCheck = tick()
	local t = getTarget()
	if t then
		lastTarget = t
		lastHitTime = tick()
	elseif lastTarget and tick() - lastHitTime > targetMemoryDuration then
		lastTarget = nil
	end
	local c = LocalPlayer.Character
	local root = lastTarget and lastTarget:FindFirstChild("HumanoidRootPart")
	if not (lastTarget and c and c:FindFirstChild("HumanoidRootPart") and root) then return end
	if (c.HumanoidRootPart.Position - root.Position).Magnitude > maxDistance then
		lastTarget = nil
		return
	end
	if lastTarget then
		canGrab = false
		task.spawn(function()
			pcall(mouse1press)
			local t0 = tick()
			repeat
				task.wait(0.02)
			until not Workspace:FindFirstChild("GrabParts") or tick() - t0 > 1.6
			task.wait(postGrabDelay)
			canGrab = true
			lastTarget = nil
		end)
	end
end)
local UserInputService = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local Camera            = workspace.CurrentCamera
local localPlayer       = Players.LocalPlayer

Camera.FieldOfView = 70

local AIM_KEY           = Enum.KeyCode.V
local DISABLE_KEY       = Enum.KeyCode.Equals
local MAX_DISTANCE      = 180
local FOV_RADIUS        = 999999

local SMOOTH_FACTOR_BASE    = 29
local ACCEL_MULTIPLIER_BASE = 6.1
local STARTUP_SPEED         = 6.1

local FLICK_THRESHOLD_DEG   = 6
local FLICK_SPEED_MULT      = 1.5
local FLICK_ACCEL_BOOST     = 1

local AIM_OFFSET_RADIUS      = 1.3
local JITTER_STRENGTH        = 0.45
local JITTER_SPEED           = 5
local REACTION_DELAY_RANGE   = {0.00000001, 0.000000001}
local SMOOTH_VARIATION       = 0.20
local MIN_ANGLE_RESIDUAL     = math.rad(0.4)

local PREDICTION_FACTOR      = 0.020

local isAiming       = false
local lockedTarget   = nil
local permanentlyOff = false
local isTyping       = false
local aimStartup     = 0
local aimOffset      = Vector3.new()
local jitterSeed     = tick()
local reactionDelay  = 0
local aimingActive   = false

local validTargets = {}

local function isValidTarget(model)
    local hum = model:FindFirstChild("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    return hum and hum.Health > 0 and root and model ~= localPlayer.Character
end

local function addTarget(model)
    if isValidTarget(model) then validTargets[model] = true end
end

local function removeTarget(model)
    validTargets[model] = nil
end

for _, obj in ipairs(Workspace:GetDescendants()) do
    if obj:IsA("Model") and isValidTarget(obj) then addTarget(obj) end
end

Workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Model") then task.wait(0.1); addTarget(obj) end
end)

Workspace.DescendantRemoving:Connect(function(obj)
    if validTargets[obj] then removeTarget(obj) end
end)

local function getRoot(m)
    return m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
end

local function findClosest()
    local mx,my = UserInputService:GetMouseLocation().X, UserInputService:GetMouseLocation().Y
    local best,bd = nil,math.huge

    for model, _ in pairs(validTargets) do
        if model.Parent then
            local r = getRoot(model)
            if r then
                local p = r.Position
                local d3 = (p - Camera.CFrame.Position).Magnitude
                if d3 <= MAX_DISTANCE then
                    local sp, on = Camera:WorldToScreenPoint(p)
                    if on then
                        local d2 = (Vector2.new(sp.X,sp.Y) - Vector2.new(mx,my)).Magnitude
                        if d2 < bd and d2 <= FOV_RADIUS then bd, best = d2, model end
                    end
                end
            end
        else
            validTargets[model] = nil
        end
    end
    return best
end

local currentTarget = nil

task.spawn(function()
    while true do
        if not isTyping and not permanentlyOff then
            currentTarget = findClosest()
        end
        task.wait(0.1)
    end
end)

local function randomUnitVector3()
    local theta = math.random() * 2 * math.pi
    local z = math.random() * 2 - 1
    local r = math.sqrt(1 - z*z)
    return Vector3.new(r*math.cos(theta), r*math.sin(theta), z)
end

local function getRealisticAimPoint(basePos, dt)
    aimOffset = aimOffset:Lerp(randomUnitVector3() * AIM_OFFSET_RADIUS, dt * 2)

    local t = tick() - jitterSeed
    local jitterX = math.sin(t * JITTER_SPEED) * JITTER_STRENGTH
    local jitterY = math.cos(t * JITTER_SPEED * 1.3) * JITTER_STRENGTH * 0.8
    local jitter = Vector3.new(jitterX, jitterY, 0)

    return basePos + aimOffset + jitter
end

local function smoothAim(pos, dt)
    local cf = Camera.CFrame

    local wantedPos = getRealisticAimPoint(pos, dt)
    local currentLook = cf.LookVector
    local targetLook  = (wantedPos - cf.Position).Unit
    local angle = math.acos(math.clamp(currentLook:Dot(targetLook), -1, 1))

    local randFactor = 1 + (math.random() * 2 - 1) * SMOOTH_VARIATION
    local SMOOTH_FACTOR = SMOOTH_FACTOR_BASE * randFactor
    local ACCEL_MULTIPLIER = ACCEL_MULTIPLIER_BASE * randFactor

    if angle > math.rad(FLICK_THRESHOLD_DEG) then
        SMOOTH_FACTOR = SMOOTH_FACTOR * FLICK_SPEED_MULT
        ACCEL_MULTIPLIER = ACCEL_MULTIPLIER * FLICK_ACCEL_BOOST
    end

    local want = CFrame.lookAt(cf.Position, wantedPos)
    local a = 1 - math.exp(-SMOOTH_FACTOR * dt * ACCEL_MULTIPLIER)
    
    local s = 1 - math.exp(-STARTUP_SPEED * dt)
    aimStartup = math.clamp(aimStartup + s, 0, 1)

    if angle < MIN_ANGLE_RESIDUAL then
        a = a * 0.3
    end

    Camera.CFrame = cf:Lerp(want, a * aimStartup)
end

UserInputService.TextBoxFocused:Connect(function() isTyping = true end)
UserInputService.TextBoxFocusReleased:Connect(function() isTyping = false end)

UserInputService.InputBegan:Connect(function(inp,p)
    if p or isTyping or permanentlyOff then return end
    if inp.KeyCode==DISABLE_KEY then
        permanentlyOff, isAiming, lockedTarget = true, false, nil
        aimingActive = false
    elseif inp.KeyCode==AIM_KEY then
        if currentTarget then
            lockedTarget   = currentTarget
            isAiming       = true
            aimStartup     = 0
            aimOffset      = Vector3.new()
            jitterSeed     = tick()
            aimingActive   = false
            reactionDelay  = math.random() * (REACTION_DELAY_RANGE[2]-REACTION_DELAY_RANGE[1]) + REACTION_DELAY_RANGE[1]
            task.delay(reactionDelay, function()
                if isAiming and lockedTarget == currentTarget then
                    aimingActive = true
                end
            end)
        end
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.KeyCode==AIM_KEY then
        isAiming, lockedTarget = false, nil
        aimingActive = false
    end
end)

RunService.RenderStepped:Connect(function(dt)
    if permanentlyOff or isTyping or not isAiming then return end
    if not aimingActive then return end

    if lockedTarget and lockedTarget.Parent then
        local r = getRoot(lockedTarget)
        local hum = lockedTarget:FindFirstChild("Humanoid")
        
        if r and hum and hum.Health > 0 then
            local predictedPos = r.Position + (r.AssemblyLinearVelocity * PREDICTION_FACTOR)
            smoothAim(predictedPos, dt)
            return
        end
    end
    isAiming, lockedTarget = false, nil
    aimingActive = false
end)
