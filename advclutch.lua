local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = workspace
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
 
local on = false
local canGrab = true
local maxDistance = 30
local preGrabDelay = 0
local postGrabDelay = 0.0
local scriptEnabled = true
local indicatorShown = true
local indicator, screenGui
local lastTarget, lastHitTime = nil, 0
local targetMemoryDuration = 0.01
local checkThrottle = 0
 
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
 
-- Проверка геймпасса (без изменений)
task.spawn(pcall, function()
    if ReplicatedStorage.GamepassEvents.CheckForGamepass:InvokeServer(20837132) then
        maxDistance = 35
    end
end)
 
-- Создание индикатора (БЕЗ ИЗМЕНЕНИЙ!)
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
    label.Text = "адв клатч врублен"
    label.Visible = false
    label.Parent = screenGui
    return label
end
 
indicator = makeIndicator()
 
-- Подписка на событие геймпасса (без изменений)
ReplicatedStorage.GamepassEvents.FurtherReachBoughtNotifier.OnClientEvent:Connect(function()
    maxDistance = 35
end)
 
-- 🚫 mouse1press — оставляем как есть, не трогаем
 
-- ✅ getTarget — теперь ИГНОРИРУЕТ игроков, работает ТОЛЬКО на вещи/объекты
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
    if not model or model == c then return end
 
    -- 🔥 НОВОЕ: Если это персонаж игрока — игнорируем!
    -- Проверяем, есть ли владелец у модели (через Humanoid или через поиск в Players)
    local isPlayerCharacter = false
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        -- Проверяем, принадлежит ли эта модель какому-то игроку
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character == model then
                isPlayerCharacter = true
                break
            end
        end
    end
 
    -- Если это игрок — выходим
    if isPlayerCharacter then return end
 
    -- Можно также разрешить объекты без Humanoid — они точно не игроки
    -- (это расширяет совместимость с вещами)
 
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if not root then return end
 
    local dist = (c.HumanoidRootPart.Position - root.Position).Magnitude
    if dist > maxDistance then return end
 
    return model -- Возвращаем ТОЛЬКО если это НЕ игрок
end
 
-- Обработка клавиш (БЕЗ ИЗМЕНЕНИЙ)
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
    if input.KeyCode == Enum.KeyCode.B then
        on = not on
        if indicatorShown then
            indicator.Visible = true
            indicator.Text = on and "адв клатч врублен" or "адв клатч оффнут"
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
 
-- Основной цикл (tick → os.clock для надёжности)
local lastCheck = 0
RunService.Heartbeat:Connect(function()
    if not on or not canGrab or not scriptEnabled then return end
    if UserInputService:GetFocusedTextBox() then return end
    if os.clock() - lastCheck < checkThrottle then return end
    lastCheck = os.clock()
 
    local t = getTarget()
    if t then
        lastTarget = t
        lastHitTime = os.clock()
    elseif lastTarget and os.clock() - lastHitTime > targetMemoryDuration then
        lastTarget = nil
    end
 
    local c = LocalPlayer.Character
    local root = lastTarget and (lastTarget:FindFirstChild("HumanoidRootPart") or lastTarget.PrimaryPart)
    if not (lastTarget and c and c:FindFirstChild("HumanoidRootPart") and root) then return end
 
    if (c.HumanoidRootPart.Position - root.Position).Magnitude > maxDistance then
        lastTarget = nil
        return
    end
 
    if lastTarget then
        canGrab = false
        task.spawn(function()
            pcall(mouse1press) -- 🚫 ОСТАВЛЕНО КАК ЕСТЬ
            local t0 = os.clock()
            repeat
                task.wait(0.02)
            until not Workspace:FindFirstChild("GrabParts") or os.clock() - t0 > 1.6
            task.wait(postGrabDelay)
            canGrab = true
            lastTarget = nil
        end)
    end
end)
