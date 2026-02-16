local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
 
local localPlayer = Players.LocalPlayer
 
-- Настройки для персонажа (чтобы он не терял вес)
local MAX_FRICTION = 2.0
local FRICTION_WEIGHT = 100
local DENSITY = 2
local ELASTICITY = 0
local ELASTICITY_WEIGHT = 100
 
-- Настройки для MASSLESS GRAB (предметы в руке)
local MASSLESS_DENSITY = 0 -- Делает предмет безмассовым
local MASSLESS_FRICTION = 0 -- Убирает трение предмета
local MASSLESS_ELASTICITY = 0
local MASSLESS_FRICTION_WEIGHT = 0
local MASSLESS_ELASTICITY_WEIGHT = 0
 
local processedParts = {} 
local connections = {}    
local enabled = true
local heldParts = {} -- Отслеживаем предметы в руках
 
local function applyMaxFriction(part)
    if part:IsA("BasePart") and processedParts[part] ~= true then
 part.CustomPhysicalProperties = PhysicalProperties.new(
 DENSITY, MAX_FRICTION, ELASTICITY, FRICTION_WEIGHT, ELASTICITY_WEIGHT
        )
 processedParts[part] = true
    end
end
 
local function resetPart(part)
    if part:IsA("BasePart") then
        part.CustomPhysicalProperties = nil
        processedParts[part] = nil
    end
end
 
-- Делает предмет безмассовым (как в Massless Grab)
local function makePartMassless(part)
    if part:IsA("BasePart") then
        part.CustomPhysicalProperties = PhysicalProperties.new(
            MASSLESS_DENSITY, 
            MASSLESS_FRICTION, 
            MASSLESS_ELASTICITY, 
            MASSLESS_FRICTION_WEIGHT, 
            MASSLESS_ELASTICITY_WEIGHT
        )
        heldParts[part] = true
    end
end
 
-- Возвращает предмету нормальные свойства
local function restorePartMass(part)
    if part:IsA("BasePart") and heldParts[part] then
        part.CustomPhysicalProperties = nil
        heldParts[part] = nil
    end
end
 
local function processCharacter(character)
    if not character or not enabled then return end
    
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
 
local heldObjectsConnection
local lastHeldCheck = 0
heldObjectsConnection = RunService.Heartbeat:Connect(function()
    local now = tick()
    -- Проверяем каждый кадр для максимальной отзывчивости
    if now - lastHeldCheck < 0.1 then return end 
    lastHeldCheck = now
    
    local character = localPlayer.Character
    if not character then return end
    
    -- Проверяем все Weld и WeldConstraint
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("Weld") or desc:IsA("WeldConstraint") then
            local part0, part1 = desc.Part0, desc.Part1
            
            -- Part0 - обычно часть персонажа (рука)
            -- Part1 - предмет, который берут
            
            if part0 and not part0:IsDescendantOf(character) then
                makePartMassless(part0)
            end
            
            if part1 and not part1:IsDescendantOf(character) then
                makePartMassless(part1)
            end
        end
    end
    
    -- Проверяем, какие предметы больше не удерживаются
    for part, _ in pairs(heldParts) do
        local isStillHeld = false
        
        -- Проверяем, есть ли ещё Weld/WeldConstraint с этим предметом
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("Weld") or desc:IsA("WeldConstraint") then
                if desc.Part0 == part or desc.Part1 == part then
                    -- Если предмет всё ещё прикреплён к чему-то в руке
                    local otherPart = (desc.Part0 == part) and desc.Part1 or desc.Part0
                    if otherPart and otherPart:IsDescendantOf(character) then
                        isStillHeld = true
                        break
                    end
                end
            end
        end
        
        -- Если предмет больше не удерживается, возвращаем ему массу
        if not isStillHeld then
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
 
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.F then
        enabled = not enabled
        
        if enabled then
            if localPlayer.Character then
                processCharacter(localPlayer.Character)
            end
        else
            local char = localPlayer.Character
            if char then
                for _, part in ipairs(char:GetChildren()) do
                    if part:IsA("BasePart") or part:IsA("MeshPart") then
                        resetPart(part)
                    end
                end
            end
            
            -- Возвращаем массу всем предметам, которые держали
            for part, _ in pairs(heldParts) do
                restorePartMass(part)
            end
        end
    end
end)
 
local function onCharacterAdded(character)
    task.wait(1)
    if enabled then
        processCharacter(character)
    end
end
 
if localPlayer.Character then
    onCharacterAdded(localPlayer.Character)
end
 
localPlayer.CharacterAdded:Connect(onCharacterAdded)
 
applyFrictionToWorld()
