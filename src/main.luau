-- // Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

-- // Variables
local vortex = {}
local localPlayer = Players.LocalPlayer

vortex.activeNetless = {}

local DEFAULT_TIMER_DURATION = 1

local DEFAULT_SIMULATION_INTERVAL = 10
local DEFAULT_SIMULATION_RADIUS = 10000

local MAX_TELEPORT_CHECK_DISTANCE = 5

local NETLESS_VECTOR = Vector3.new(-30, 0, 0)

-- // Types
export type timerData = {
    alpha: number,
    elapsedTime: number,
    isFinished: boolean
}

export type tweenData = {
    instance: Instance,
    tweenInfo: TweenInfo,
    properties: { [string]: any }
}

export type instanceData = {
    instance: string,
    name: string?,
    values: { [string]: any? },
    parent: Instance?
}

export type netlessData = {
    update: (Vector3 | CFrame | Instance) -> (),
    stop: () -> ()
}

export type initialNetless = {
    objects: (Instance | { Instance })?,
    initialTarget: (Vector3 | CFrame | Instance)
}

-- // Utility Functions

-- Disconnects connections
function vortex.disconnect(connection: RBXScriptConnection): boolean
    if connection and connection.Connected then
        connection:Disconnect()
        return true
    end

    return false
end

-- Resets velocity on a single BasePart
function vortex.resetVelocity(part: BasePart): ()
    if not part or not part:IsA("BasePart") then return end

    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
end

-- Gets the CFrame of a target
function vortex.getCFrame(target: (Vector3 | CFrame | Instance)?): CFrame?
    if not target then return nil end
    local targetType = typeof(target)

    if targetType == "CFrame" then
        return target :: CFrame
    elseif targetType == "Vector3" then
        return CFrame.new(target :: Vector3)
    elseif targetType == "Instance" then
        local inst = target :: Instance

        if inst:IsA("Player") then
            local root = vortex.getRoot(inst)

            return root and root.CFrame or nil
        end

        local part = vortex.getBasePart(inst)
        if part then
            return part.CFrame
        elseif inst:IsA("Model") then
            return inst:GetPivot()
        end
    end

    return nil
end

-- Gets the BasePart of a target
function vortex.getBasePart(target: Instance?): BasePart?
    if not target then return nil end

    if target:IsA("BasePart") then
        return target :: BasePart
    elseif target:IsA("Model") then
        return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
    elseif target:IsA("Tool") then
        return (target:FindFirstChild("Handle") :: BasePart?) or target:FindFirstChild("BasePart")
    end

    return nil
end

-- // Initialization Functions

-- Creates a timer for loops
function vortex.createTimer(duration: number): timerData
    if not duration then duration = DEFAULT_TIMER_DURATION end
    local startTime = os.clock()

    return function()
        local elapsedTime = os.clock() - startTime
        local alpha = math.clamp(elapsedTime / duration, 0, 1)

        return {
            alpha = alpha,
            elapsedTime = elapsedTime,
            isFinished = elapsedTime >= duration
        }
    end
end

-- Creates a Tween
function vortex.createTween(tweenData: tweenData): Tween
    if not tweenData then return nil end

    return TweenService:Create(
        tweenData.instance,
        tweenData.tweenInfo,
        tweenData.properties
    )
end

-- Creates an Instance
function vortex.createInstance(instanceData: instanceData): Instance
    if not instanceData then return nil end

    local instanceObject = Instance.new(instanceData.instance)
    instanceObject.Name = instanceData.name or "VortexInstance"

    if instanceData.values then
        for property, value in instanceData.values do
            instanceObject[property] = value
        end
    end

    if instanceData.parent then
        instanceObject.Parent = instanceData.parent
    end

    return instanceObject
end

-- Creates an Attachment
function vortex.createAttachment(parent: BasePart, name: string?): Attachment
    local attachment = Instance.new("Attachment")
    attachment.Name = name or "VortexAttachment"

    if parent then
        attachment.Parent = parent
    end

    return attachment
end

-- Creates a simulation loop
function vortex.simulationBoost(radius: number?, interval: number?): { stop: () -> () }
    if not sethiddenproperty then return nil end
    interval = interval or DEFAULT_SIMULATION_INTERVAL
    radius = radius or DEFAULT_SIMULATION_RADIUS
    local isRunning = true

    local thread: thread?
    thread = task.spawn(function()
        while isRunning do
            if not localPlayer or not localPlayer.Parent then break end

            pcall(function()
                sethiddenproperty(localPlayer, "SimulationRadius", radius)
                sethiddenproperty(localPlayer, "MaximumSimulationRadius", radius)
            end)
            task.wait(interval)
        end
    end)

    local controller = {}
    function controller.stop()
        if not isRunning then return end
        isRunning = false

        if thread then
            task.cancel(thread)
        end
    end

    return controller
end

-- Netless
function vortex.netlessAlign(initialNetless: initialNetless): netlessData?
    if not initialNetless then return nil end

    local objects, initialTarget = initialNetless.objects, initialNetless.initialTarget
    local objectsList: { Instance } = typeof(objects) == "Instance" and { objects } or (objects :: { Instance })
    if not objectsList then return end

    local targetCFrame = vortex.getCFrame(initialTarget) or CFrame.identity
    local targetAnchor = vortex.createInstance({
        instance = "Part",
        name = "NetlessAnchor",
        parent = Workspace,
        values = {
            Anchored = true,
            Transparency = 1,
            CanCollide = false,
            CFrame = targetCFrame
        }
    })
    local anchorAttachment = vortex.createAttachment(targetAnchor)

    local VECTOR = NETLESS_VECTOR

    local managedParts = {}
    local activeConstraints = {}
    local originalCollisions = {}

    local controller = {}
    local isRunning = true
    local conn: RBXScriptConnection?

    function controller.update(newTarget: (Vector3 | CFrame | Instance)): ()
        if not isRunning then return end

        local newCFrame = vortex.getCFrame(newTarget)
        if newCFrame then
            targetAnchor.CFrame = newCFrame
        end
    end

    function controller.stop(): ()
        if not isRunning then return end
        isRunning = false

        if conn then
            vortex.disconnect(conn)
        end

        for _, instance in activeConstraints do
            if instance and instance.Parent then
                instance:Destroy()
            end
        end

        targetAnchor:Destroy()

        for _, part in managedParts do
            vortex.activeNetless[part] = nil

            if part and part.Parent then
                if originalCollisions[part] ~= nil then
                    part.CanCollide = originalCollisions[part]
                end

                vortex.resetVelocity(part)
            end
        end
    end

    for _, object in objectsList do
        local basePart = vortex.getBasePart(object)
        if basePart and not basePart.Anchored then
            if vortex.activeNetless[basePart] then
                vortex.activeNetless[basePart].stop()
            end

            local objectAttachment = vortex.createAttachment(basePart)
            local alignPos = vortex.createInstance({
                instance = "AlignPosition",
                parent = basePart,
                values = {
                    Mode = Enum.PositionAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxForce = math.huge,
                    Responsiveness = 100
                }
            })

            local alignOrient = vortex.createInstance({
                instance = "AlignOrientation",
                parent = basePart,
                values = {
                    Mode = Enum.OrientationAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxTorque = math.huge,
                    Responsiveness = 100
                }
            })

            originalCollisions[basePart] = basePart.CanCollide
            basePart.CanCollide = false

            table.insert(managedParts, basePart)
            table.insert(activeConstraints, objectAttachment)
            table.insert(activeConstraints, alignPos)
            table.insert(activeConstraints, alignOrient)

            basePart.Destroying:Once(function()
                if isRunning then
                    controller.stop()
                end
            end)
        end
    end

    if #managedParts == 0 then
        targetAnchor:Destroy()
        return nil
    end

    conn = RunService.Heartbeat:Connect(function()
        for _, part in managedParts do
            if part and part.Parent then
                part.AssemblyLinearVelocity = VECTOR
            end
        end
    end)

    for _, part in managedParts do
        vortex.activeNetless[part] = controller
    end

    return controller
end

-- // Core Functions

-- Teleports LocalPlayer to a specific location
function vortex.teleportTo(target: (Vector3 | CFrame | Instance)): boolean
    local root = vortex.getRoot(localPlayer)
    local targetCFrame = vortex.getCFrame(target)
    if not root or not targetCFrame then return false end

    vortex.resetVelocity(root)
    root.CFrame = targetCFrame

    return (root.Position - targetCFrame.Position).Magnitude <= MAX_TELEPORT_CHECK_DISTANCE
end

-- Views a target
function vortex.view(target: Instance?): boolean
    local currentCamera = Workspace.CurrentCamera
    if not currentCamera then return false end

    local function setCamera(target): ()
        if not target then return end

        currentCamera.CameraSubject = target
    end

    local targetType = typeof(target)
    if not target then
        local humanoid = vortex.getHumanoid(localPlayer)

        if humanoid then
            setCamera(humanoid)
        end

        return false
    end

    if targetType == "Instance" then
        local inst = target :: Instance

        if inst:IsA("Humanoid") then
            setCamera(inst)
            return true
        elseif inst:IsA("Player") then
            local humanoid = vortex.getHumanoid(inst)

            if humanoid then
                setCamera(humanoid)
                return true
            end
        elseif inst:IsA("BasePart") then
            setCamera(inst)

            return true
        elseif inst:IsA("Model") then
            local humanoid = vortex.getHumanoid(inst)
            local basePart = vortex.getBasePart(inst)

            if humanoid then
                setCamera(humanoid)

                return true
            elseif inst.PrimaryPart or basePart then
                setCamera(inst.PrimaryPart or basePart)

                return true
            end
        end
    end

    return false
end

-- Views LocalPlayer
function vortex.unview(): boolean
    return vortex.view(localPlayer)
end

-- Finds a tool from LocalPlayer's Backpack or character
function vortex.findTool(player: Player, toolName: string): Tool?
    if not player or not toolName or toolName == "" then return nil end

    local checkContainer = function(container: Instance?): Tool?
        if not container then return nil end

        local item = container:FindFirstChild(toolName)
        return (item and item:IsA("Tool")) and (item :: Tool) or nil
    end

    return checkContainer(player and player:FindFirstChildOfClass("Backpack")) or checkContainer(vortex.getChar(player))
end

-- // Player & Entity Functions

-- Finds a player based off their Username/DisplayName (Also has "me" and "random")
function vortex.findPlayer(target: string?): Player?
    if not target or target == "" then return nil end

    local partial = string.lower(target)
    local allPlayers = Players:GetPlayers()

    if partial == "me" then
        return localPlayer
    elseif partial == "random" then
        local others = {}

        for _, player in allPlayers do
            if player ~= localPlayer then
                table.insert(others, player)
            end
        end

        return #others > 0 and others[math.random(1, #others)] or nil
    end

    local isMatch = function(name: string): boolean
        return string.sub(name:lower(), 1, #partial) == partial
    end

    for _, player in allPlayers do
        if (player.Name:lower() == partial or player.DisplayName:lower() == partial) or (isMatch(player.Name) or isMatch(player.DisplayName)) then
            return player
        end
    end

    return nil
end

-- Gets the character of a player
function vortex.getChar(player: Player): Model?
    return player and (player.Character :: Model?) or nil
end

-- // Check Character

-- Checks whether the target is a character or a player
local function checkCharacter(target: (Model | Player)?): Model?
    if not target then return nil end
    local character: Model

    if target:IsA("Model") then
        character = target
    elseif target:IsA("Player") then
        character = vortex.getChar(target)
    end

    return character or nil
end

-- Gets the root of a character/player
function vortex.getRoot(target: (Model | Player)?): BasePart?
    if not target then return nil end
    local character = checkCharacter(target)
    return character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
end

-- Gets the Humanoid of a character/player
function vortex.getHumanoid(target: (Model | Player)?): Humanoid?
    if not target then return nil end
    local character = checkCharacter(target)
    return character and (character:FindFirstChildOfClass("Humanoid") :: Humanoid?) or nil
end

-- Breaks the LocalPlayer's Joints
function vortex.breakJoints(): ()
    local character = vortex.getChar(localPlayer)
    if not character then return end
    for _, joint in character:GetDescendants() do
        if joint:IsA("Motor6D") then
            joint:Destroy()
        end
    end
end

return vortex
