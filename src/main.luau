--[[
    Vortex
    Copyright (c) 2026 zkyoi
    Licensed under the MIT License
]]--

local vortex = {}
local _version: string = "v1.3.0-beta"

-- // Local Cache
local os_clock = os.clock
local math_clamp = math.clamp
local table_insert = table.insert
local string_sub = string.sub
local string_lower = string.lower
local string_format = string.format
local typeof = typeof

-- // Services
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- // Variables
local localPlayer: Player = Players.LocalPlayer

vortex.activeNetless = {}

-- // Debugging
vortex.debugLogs = {}
vortex.debugMode = false

-- This handles cleanup
local currentSession = {
    connections = {},
    threads = {},
    instances = {},
    controllers = {}
}

-- // Constants
local DEFAULT_TIMER_DURATION: number = 1
local DEFAULT_SIMULATION_INTERVAL: number = 10
local DEFAULT_SIMULATION_RADIUS: number = 10000
local MAX_TELEPORT_CHECK_DISTANCE: number = 5

local NETLESS_VECTOR: Vector3 = Vector3.new(-30, 0, 0)

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
    values: { [string]: any? }?,
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

-- // Helper Functions
local function Log(message: string, logFunc: string?, hide: boolean?): ()
    local hideLog = hide or false
    local lowerFunc = logFunc and string_lower(logFunc)
    local activeLogger: any
    if lowerFunc == "p" then
        activeLogger = print
    elseif lowerFunc == "w" then
        activeLogger = warn
    elseif lowerFunc == "e" then
        activeLogger = error
    else
        lowerFunc = "p"
        activeLogger = print
    end

    if not hideLog then
        table_insert(vortex.debugLogs, string_format("%s: %s", lowerFunc, message))
    end

    if vortex.debugMode == true then
        activeLogger(string_format("[Vortex]: %s", message))
    end
end

local function Missing(type, object, fallback)
    if typeof(object) == type then
        return object
    end

    return fallback
end

local function FindVehicle(seat: VehicleSeat): Model?
    local vehicleChecks = {
        seat:FindFirstAncestor("Body").Parent,
        seat:FindFirstAncestor("Car"),
        seat:FindFirstAncestor("Vehicle"), -- For old games
        seat:FindFirstAncestorWhichIsA("Model") -- Universal fallback
    }

    for _, check in vehicleChecks do
        if check and check:IsA("Model") and seat:IsDescendantOf(check) then
            return check
        end
    end

    Log("Failed to find the vehicle!", "w", false)
    return nil
end

-- // Checks
local SetHidden = Missing("function", sethiddenproperty or sethiddenprop)

-- // Utility Functions
function vortex.Disconnect(connection: RBXScriptConnection): boolean
    if connection and connection.Connected then
        connection:Disconnect()
        return true
    end

    Log("Failed to disconnect a connection!", "w", false)
    return false
end

function vortex.ResetVelocity(part: BasePart): ()
    if not part or not part:IsA("BasePart") then Log("Object is not a BasePart!", "w", false) return end

    part.AssemblyLinearVelocity = Vector3.zero
    part.AssemblyAngularVelocity = Vector3.zero
end

function vortex.GetCFrame(target: (Vector3 | CFrame | Instance)?): CFrame?
    if not target then Log("Unable to find target!", "w", false) return nil end
    local targetType: string = typeof(target)

    if targetType == "CFrame" then
        return target :: CFrame
    elseif targetType == "Vector3" then
        return CFrame.new(target :: Vector3)
    elseif targetType == "Instance" then
        local inst: Instance = target :: Instance

        if inst:IsA("Player") then
            local root: BasePart? = vortex.GetRoot(inst)

            return root and root.CFrame
        end

        local part: BasePart? = vortex.GetBasePart(inst)
        if part then
            return part.CFrame
        elseif inst:IsA("Model") then
            return inst:GetPivot()
        end
    end

    Log("Failed to get CFrame!", "w", false)
    return nil
end

function vortex.GetBasePart(target: Instance?): BasePart?
    if not target then Log("Unable to find target!", "w", false) return nil end

    if target:IsA("BasePart") then
        return target :: BasePart
    elseif target:IsA("Model") then
        return target.PrimaryPart :: BasePart or target:FindFirstChildWhichIsA("BasePart")
    elseif target:IsA("Tool") then
        local handle = target:FindFirstChild("Handle")

        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end

        return target:FindFirstChildWhichIsA("BasePart")
    end

    Log("Failed to get BasePart!", "w", false)
    return nil
end

function vortex.GetClosestPlayer(): Player?
    local rootCFrame = vortex.GetCFrame(localPlayer)
    if not rootCFrame then Log("Unable to get root CFrame!", "w", false) return nil end
    local allPlayers = Players:GetPlayers()
    local closest: Player
    local closestDistance: number = math.huge

    if #allPlayers <= 1 then
        Log("Failed to find other players!", "w", false)
        return nil
    end

    for _, player in allPlayers do
        if player == localPlayer then continue end
        local targetCFrame = vortex.GetCFrame(player)
        if not targetCFrame then Log("Failed to find target CFrame!", "w", false) continue end

        local distance = (rootCFrame.Position - targetCFrame.Position).Magnitude
        if closestDistance > distance then
            closest = player
            closestDistance = distance
        end
    end

    return closest
end

-- // Initialization Functions
function vortex.CreateTimer(durationSeconds: number?): () -> timerData
    durationSeconds = math.max(durationSeconds or DEFAULT_TIMER_DURATION, 0.001)

    local startTime: number = os_clock()

    return function(): timerData
        local elapsedTime: number = os_clock() - startTime
        local alpha: number = math_clamp(elapsedTime / durationSeconds, 0, 1)

        return {
            alpha = alpha,
            elapsedTime = elapsedTime,
            isFinished = elapsedTime >= durationSeconds
        }
    end
end

function vortex.CreateTween(data: tweenData): Tween
    return TweenService:Create(
        data.instance,
        data.tweenInfo,
        data.properties
    )
end

function vortex.CreateInstance(data: instanceData): Instance
    local instanceObject: Instance = Instance.new(data.instance)
    instanceObject.Name = data.name or "VortexInstance"

    if data.values then
        for property, value in data.values do
            instanceObject[property] = value
        end
    end

    if data.parent then
        instanceObject.Parent = data.parent
    end

    table_insert(currentSession.instances, instanceObject)
    return instanceObject
end

function vortex.CreateAttachment(parent: BasePart, name: string?): Attachment
    local attachment: Attachment = vortex.CreateInstance({
        instance = "Attachment",
        name = name or "VortexAttachment",
        parent = parent
    })

    return attachment
end

function vortex.SimulationBoost(radius: number?, intervalSeconds: number?): { stop: () -> () }?
    if not SetHidden then Log("Unable to continue, missing dependency!", "w", false) return nil end
    intervalSeconds = intervalSeconds or DEFAULT_SIMULATION_INTERVAL
    radius = radius or DEFAULT_SIMULATION_RADIUS
    local isRunning: boolean = true

    local thread: thread?
    thread = task.spawn(function()
        while isRunning do
            if not localPlayer or not localPlayer.Parent then break end

            pcall(function()
                SetHidden(localPlayer, "SimulationRadius", radius)
                SetHidden(localPlayer, "MaximumSimulationRadius", radius)
            end)
            task.wait(intervalSeconds)
        end
    end)
    table_insert(currentSession.threads, thread)

    local controller = {} :: { stop: () -> () }
    function controller.Stop()
        if not isRunning then return end
        isRunning = false

        if thread then
            task.cancel(thread)
        end
    end

    table_insert(currentSession.controllers, controller)
    return controller
end

function vortex.NetlessAlign(data: initialNetless): netlessData?
    if not data then Log("Please specify data!", "w", false) return nil end

    local initialTarget: (Vector3 | CFrame | Instance) = data.initialTarget
    local objects: (Instance | { Instance })? = data.objects
    if not objects then Log("Unable to get objects from data!", "w", false) return nil end

    local objectsList: { Instance }

    if typeof(objects) == "Instance" then
        objectsList = { objects }
    else
        objectsList = objects
    end

    local targetCFrame: CFrame = vortex.GetCFrame(initialTarget) or CFrame.identity
    local targetAnchor: BasePart = vortex.CreateInstance({
        instance = "Part",
        name = "NetlessAnchor",
        parent = Workspace,
        values = {
            Anchored = true,
            Transparency = 1,
            CanCollide = false,
            CFrame = targetCFrame
        }
    }) :: BasePart
    local anchorAttachment: Attachment = vortex.CreateAttachment(targetAnchor)

    local VECTOR = NETLESS_VECTOR

    local managedParts: { BasePart } = {}
    local activeConstraints: { Instance } = {}
    local originalCollisions: { [BasePart]: boolean } = {}

    local controller: netlessData = {} :: netlessData
    local isRunning: boolean = true
    local conn: RBXScriptConnection?

    function controller.Update(newTarget: (Vector3 | CFrame | Instance)): ()
        if not isRunning then return end

        local newCFrame: CFrame? = vortex.GetCFrame(newTarget)
        if newCFrame then
            targetAnchor.CFrame = newCFrame
        end
    end

    function controller.Stop(): ()
        if not isRunning then return end
        isRunning = false

        if conn then
            vortex.Disconnect(conn)
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

                vortex.ResetVelocity(part)
            end
        end
    end

    for _, object in objectsList do
        local basePart: BasePart? = vortex.GetBasePart(object)

        if basePart and not basePart.Anchored then
            if vortex.activeNetless[basePart] then
                vortex.activeNetless[basePart].stop()
            end

            local objectAttachment: Attachment = vortex.CreateAttachment(basePart)
            local alignPos: AlignPosition = vortex.CreateInstance({
                instance = "AlignPosition",
                parent = basePart,
                values = {
                    Mode = Enum.PositionAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxForce = math.huge,
                    Responsiveness = 100
                }
            }) :: AlignPosition

            local alignOrient: AlignOrientation = vortex.CreateInstance({
                instance = "AlignOrientation",
                parent = basePart,
                values = {
                    Mode = Enum.OrientationAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxTorque = math.huge,
                    Responsiveness = 100
                }
            }) :: AlignOrientation

            originalCollisions[basePart] = basePart.CanCollide
            basePart.CanCollide = false

            table_insert(managedParts, basePart)
            table_insert(activeConstraints, objectAttachment)
            table_insert(activeConstraints, alignPos)
            table_insert(activeConstraints, alignOrient)

            basePart.Destroying:Once(function()
                if isRunning then
                    controller.Stop()
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
    table_insert(currentSession.connections, conn)

    for _, part in managedParts do
        vortex.activeNetless[part] = controller
    end

    table_insert(currentSession.controllers, controller)
    return controller
end

-- // Core Functions
function vortex.TeleportTo(target: (Vector3 | CFrame | Instance)): boolean
    local root: BasePart? = vortex.GetRoot(localPlayer)
    local targetCFrame: CFrame? = vortex.GetCFrame(target)
    if not root or not targetCFrame then Log("Failed to find root or its CFrame!", "w", false) return false end

    vortex.ResetVelocity(root)

    for _, v in root:GetChildren() do
        if v:IsA("BodyVelocity") or v:IsA("BodyForce") or v:IsA("LinearVelocity") then
            v:Destroy()
        end
    end

    root.CFrame = targetCFrame

    return (root.Position - targetCFrame.Position).Magnitude <= MAX_TELEPORT_CHECK_DISTANCE
end

function vortex.View(target: Instance?): boolean
    local currentCamera: Camera = Workspace.CurrentCamera
    if not currentCamera then Log("Failed to find CurrentCamera!", "w", false) return false end

    local function SetCamera(subject: Instance): ()
        currentCamera.CameraSubject = subject
    end

    local targetType: string = typeof(target)
    if not target then
        local humanoid: Humanoid = vortex.GetHumanoid(localPlayer)

        if humanoid then
            Log("Failed to find target, attempting to set camera to LocalPlayers Humanoid!", "w", false)
            SetCamera(humanoid)

            return true
        end

        Log("Failed to find target!", "w", false)
        return false
    end

    if targetType == "Instance" then
        local inst: Instance = target :: Instance

        if inst:IsA("Humanoid") then
            SetCamera(inst)
            return true
        elseif inst:IsA("Player") then
            local humanoid: Humanoid = vortex.GetHumanoid(inst)

            if humanoid then
                SetCamera(humanoid)
                return true
            end
        elseif inst:IsA("BasePart") then
            SetCamera(inst)

            return true
        elseif inst:IsA("Model") then
            local humanoid: Humanoid = vortex.GetHumanoid(inst)
            local basePart: BasePart? = vortex.GetBasePart(inst)

            if humanoid then
                SetCamera(humanoid)

                return true
            elseif inst.PrimaryPart or basePart then
                SetCamera(inst.PrimaryPart or basePart)

                return true
            end
        end
    end

    Log("Failed to view!", "w", false)
    return false
end

function vortex.Unview(): boolean
    return vortex.View(localPlayer)
end

function vortex.FindTool(player: Player, toolName: string): Tool?
    local CheckContainer = function(container: Instance?): Tool?
        if not container then Log("Please a container!", "w", false) return nil end

        local item: Tool? = container:FindFirstChild(toolName)

        if not item then
            for _, v in container:GetChildren() do
                if v and string.find(v.Name:lower(), toolName:lower()) then
                    item = v
                    break
                end
            end
        end

        return (item and item:IsA("Tool")) and (item :: Tool)
    end

    return CheckContainer(player and player:FindFirstChildOfClass("Backpack")) or CheckContainer(vortex.GetChar(player))
end

function vortex.EquipTool(tool: Tool): Tool?
    local character: Model? = vortex.GetChar(localPlayer)
    if not character then Log("Failed to find character!", "w", false) return nil end
    local humanoid: Humanoid? = vortex.GetHumanoid(character)
    if not humanoid then Log("Failed to find Humanoid!", "w", false) return nil end

    humanoid:UnequipTools()
    tool.Parent = character

    return tool
end

function vortex.DropTool(tool: Tool): Tool?
    local character: Model? = vortex.GetChar(localPlayer)
    if not character then Log("Failed to find character!", "w", false) return nil end
    local humanoid: Humanoid? = vortex.GetHumanoid(character)
    if not humanoid then Log("Failed to find Humanoid!", "w", false) return nil end

    if tool.Parent ~= character then
        vortex.EquipTool(tool)
    end

    tool.Parent = Workspace

    return tool
end

-- // Player & Entity Functions
function vortex.FindPlayer(target: string?): Player?
    if not target or target == "" then Log("Failed to find target!", "w", false) return nil end

    local partial: string = string_lower(target)
    local allPlayers = Players:GetPlayers()

    if partial == "me" then
        return localPlayer
    elseif partial == "random" then
        local others = {}

        for _, player in allPlayers do
            if player ~= localPlayer then
                table_insert(others, player)
            end
        end

        return #others > 0 and others[math.random(1, #others)]
    end

    local IsMatch = function(name: string): boolean
        return string_sub(string_lower(name), 1, #partial) == partial
    end

    for _, player in allPlayers do
        if (IsMatch(player.Name) or IsMatch(player.DisplayName)) then
            return player -- This returns the first match
        end
    end

    Log("Failed to find Player!", "w", false)
    return nil
end

function vortex.GetChar(player: Player): Model?
    return player and (player.Character :: Model?)
end

-- // Check Character
local function CheckCharacter(target: (Model | Player)?): Model?
    if not target then Log("Unable to find target!", "w", false) return nil end

    if target:IsA("Model") then
        return target :: Model
    elseif target:IsA("Player") then
        return target.Character :: Model
    end

    Log("Unable to check character!", "w", false)
    return nil
end

function vortex.GetRoot(target: (Model | Player)?): BasePart?
    if not target then Log("Unable to find target!", "w", false) return nil end
    local character: Model? = CheckCharacter(target)
    return character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
end

function vortex.GetHumanoid(target: (Model | Player)?): Humanoid?
    if not target then Log("Unable to find target!", "w", false) return nil end
    local character: Model? = CheckCharacter(target)
    return character and (character:FindFirstChildOfClass("Humanoid") :: Humanoid?)
end

function vortex.BreakJoints(): ()
    local character: Model? = vortex.GetChar(localPlayer)
    if not character then Log("Unable to find character!", "w", false) return end
    for _, joint in character:GetDescendants() do
        if joint:IsA("Motor6D") then
            joint:Destroy()
        end
    end
end

function vortex.Unsit(): ()
    local humanoid: Humanoid = vortex.GetHumanoid(localPlayer)
    if not humanoid then Log("Failed to find Humanoid!", "w", false) return end
    if not humanoid.SeatPart then Log("Humanoid is not currently sitting!", "w", false) return end

    local seatedState: EnumItem = Enum.HumanoidStateType.Seated
    if not seatedState then Log("Failed to find HumanoidStateType.Seated!", "w", false) return end

    humanoid.Sit = false
    humanoid:SetStateEnabled(seatedState, false)

    task.delay(0.5, function()
        if not humanoid then Log("Failed to find Humanoid!", "w", false) return end
        humanoid:SetStateEnabled(seatedState, true)
    end)
end

function vortex.TeleportVehicle(target: (Vector3 | CFrame | Instance), useFallback: boolean?): boolean
    local targetCFrame: CFrame? = vortex.GetCFrame(target)
    if not targetCFrame then Log("Failed to find target CFrame!", "w", false) return false end
    local character: Model? = vortex.GetChar(localPlayer)
    if not character then Log("Failed to find character!", "w", false) return false end
    local root: BasePart? = vortex.GetRoot(character)
    if not root then Log("Failed to find root!", "w", false) return false end
    local humanoid: Humanoid? = vortex.GetHumanoid(character)
    if not humanoid then Log("Failed to find Humanoid!", "w", false) return false end
    local seat: VehicleSeat? = humanoid.SeatPart
    if not seat then Log("Failed to find seat!", "w", false) return false end
    local seatCFrame: CFrame = seat.CFrame

    local vehicle: Model? = FindVehicle(seat)

    if not vehicle then
        Log("Failed to find vehicle, attempting fallback!", "w", false)
        vortex.ResetVelocity(seat)
        vortex.TeleportTo(targetCFrame)

        return true
    end

    if vehicle then
        if useFallback then
            vortex.ResetVelocity(seat)
            vehicle:PivotTo(targetCFrame)

            return true
        end

        local jointData = {}
        local gyros = {}

        for _, joint in vehicle:GetDescendants() do
            local jointParent = joint.Parent

            if joint and joint:IsA("Rotate") and joint.Part0 and joint.Part1 then
                table_insert(jointData, {
                    part0 = joint.Part0,
                    part1 = joint.Part1,
                    relativePart0 = seatCFrame:ToObjectSpace(joint.Part0.CFrame),
                    relativePart1 = seatCFrame:ToObjectSpace(joint.Part1.CFrame)
                })
            end

            local gyro: BodyGyro? = jointParent:FindFirstChildOfClass("BodyGyro") or jointParent:FindFirstChild("BodyGyro")
            if gyro then
                table_insert(gyros, gyro)
            end
        end

        vortex.ResetVelocity(seat)
        vortex.TeleportTo(targetCFrame)

        for _, data in jointData do
            vortex.ResetVelocity(data.part0)
            vortex.ResetVelocity(data.part1)

            data.part0.CFrame = targetCFrame:ToWorldSpace(data.relativePart0)
            data.part1.CFrame = targetCFrame:ToWorldSpace(data.relativePart1)
        end

        for _, gyro in gyros do
            local relativeRotation: CFrame = seatCFrame.Rotation:Inverse() * gyro.CFrame.Rotation
            gyro.CFrame = targetCFrame.Rotation * relativeRotation
        end

        task.defer(function()
            if seat and seat.Parent then
                vortex.ResetVelocity(seat)

                for _, v in vehicle:GetDescendants() do
                    if v:IsA("BasePart") then
                        vortex.ResetVelocity(v)
                    end
                end
            end
        end)

        return true
    end

    Log("Failed to teleport vehicle!", "w", false)
    return false
end

-- // Methods
function vortex.QuickTest(): ()
    -- Add: Functionality
end

function vortex:GetVersion(): string
    return _version
end

-- It's not required but highly recommended once you're done using the library
function vortex.CleanUp(): ()
    local sessionConnections = currentSession.connections
    local sessionThreads = currentSession.threads
    local sessionInstances = currentSession.instances
    local sessionControllers = currentSession.controllers

    for i=#sessionConnections, 1, -1 do
        local connection = sessionConnections[i]
        vortex.Disconnect(connection)
        sessionConnections[i] = nil
    end

    for i=#sessionThreads, 1, -1 do
        local thread = sessionThreads[i]
        if typeof(thread) == "thread" then
            task.cancel(thread)
        end
        sessionThreads[i] = nil
    end

    for i=#sessionInstances, 1, -1 do
        local instance = sessionInstances[i]
        if typeof(instance) == "Instance" then
            instance:Destroy()
        end
        sessionInstances[i] = nil
    end

    for i=#sessionControllers, 1, -1 do
        local controller = sessionControllers[i]
        if controller and typeof(controller.Stop) == "function" then
            controller.Stop()
        end
    end
end

function vortex.DumpLogs(): ()
    for _, log in vortex.debugLogs do
        local logType: string = string_sub(log, 1, 1)
        local message: string = string_sub(log, 4)

        Log(message, logType, true)
    end
end

function vortex.Exit(): ()
    game:Shutdown()
end

return vortex
