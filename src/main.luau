--[[
    Vortex v1.4
    Copyright (c) 2026 zkyoi
    Licensed under the MIT License (MIT)
]]--

local vortex = {}
local _version: string = "v1.4"

-- // Local Cache
local os_clock = os.clock
local os_time = os.time

local math_clamp = math.clamp
local math_max = math.max
local math_random = math.random
local math_huge = math.huge

local table_insert = table.insert
local table_clear = table.clear
local table_find = table.find
local table_remove = table.remove

local string_sub = string.sub
local string_lower = string.lower
local string_format = string.format
local string_find = string.find
local tostring = tostring

local task_spawn = task.spawn
local task_delay = task.delay
local task_cancel = task.cancel
local task_defer = task.defer
local task_wait = task.wait
local table_clone = table.clone
local table_concat = table.concat

local print = print
local warn = warn
local error = error

local typeof = typeof
local pcall = pcall
local Vector3_zero = Vector3.zero
local CFrame_identity = CFrame.identity

-- // Services
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

-- // Variables
local localPlayer: Player = Players.LocalPlayer
local currentPlaceId: number = game.PlaceId

vortex.activeNetless = {}

-- // Debugging
vortex.debugLogs = {} :: { LogEntry }
vortex.debugMode = false

-- // Save System
local fileSystem = {}

local ROOT = "VortexLibrary/"
local CONFIG = ROOT .. "configs/"

fileSystem.ROOT = ROOT
fileSystem.CONFIG = CONFIG

-- // Clean up
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
local TWEEN_SPEED = 1

local NETLESS_VECTOR: Vector3 = Vector3.new(-30, 0, 0)

-- // Types
export type TimerData = {
    alpha: number,
    elapsedTime: number,
    isFinished: boolean
}

export type TweenData = {
    instance: Instance,
    tweenInfo: TweenInfo,
    properties: { [string]: any }
}

export type InstanceData = {
    instance: string,
    name: string?,
    values: { [string]: any? }?,
    parent: Instance?
}

export type NetlessData = {
    update: (Vector3 | CFrame | Instance) -> (),
    setCanCollide: (boolean) -> (),
    setEnabled: (boolean) -> (),
    stop: () -> ()
}

export type InitialNetless = {
    objects: (Instance | { Instance })?,
    initialTarget: (Vector3 | CFrame | Instance),
    canCollide: boolean?,
    enabled: boolean?
}

export type LogEntry = {
    type: string,
    text: string,
    timestamp: number
}

export type JointData = {
    part0: BasePart,
    part1: BasePart,
    relativePart0: CFrame,
    relativePart1: CFrame
}

-- // Helper Functions
local function log(message: string, logFunc: string?, hide: boolean?, custom: string?): ()
    local messageString: string = tostring(message)
    local lowerFunc: string = (logFunc and string_lower(logFunc)) or "p"
    local hideLog: boolean = hide or false
    local customLog: string = custom or "[Vortex]: "

    local activeLogger: (any) -> () = print
    if lowerFunc == "w" then activeLogger = warn
    elseif lowerFunc == "e" then activeLogger = error end

    if not hideLog then
        table_insert(vortex.debugLogs, {
            type = lowerFunc,
            text = messageString,
            timestamp = os_time()
        })
    end

    if vortex.debugMode == true then
        activeLogger(string_format("%s %s", customLog, messageString))
    end
end

local function missing<fallbackType>(expectedType: string, object: any, fallback: fallbackType?): fallbackType?
    if typeof(object) ~= expectedType then
        return fallback :: fallbackType
    end

    return object :: fallbackType
end

local function findVehicle(seat: (VehicleSeat | Seat)): Model?
    local vehicleChecks = {
        seat:FindFirstAncestor("Body") and seat:FindFirstAncestor("Body").Parent,
        seat:FindFirstAncestor("Car"),
        seat:FindFirstAncestor("Vehicle"),
        seat:FindFirstAncestorWhichIsA("Model")
    }

    for _, check in vehicleChecks do
        if check and check:IsA("Model") and seat:IsDescendantOf(check) then
            return check
        end
    end

    log("Failed to find the vehicle!", "w", false)
    return nil
end

local function getBasePartChild(parent: Instance, name: string): BasePart?
    local object: Instance? = parent:FindFirstChild(name)

    if object and object:IsA("BasePart") then
        return object :: BasePart
    end

    return nil
end

-- // Enviroment & Executor Safety Fallbacks

-- // Reflection Library
local setHidden: ((Instance, string, any) -> (boolean))? = missing("function", sethiddenproperty or sethiddenprop)
local isNetworkOwner: ((Instance) -> (boolean))? = missing("function", isnetworkowner)

-- // FileSystem Library
local isFolder: ((string) -> (boolean))? = missing("function", isfolder)
local makeFolder: ((string) -> ())? = missing("function", makefolder)
local writeFile: ((string, string) -> ())? = missing("function", writefile)
local isFile: ((string) -> (boolean))? = missing("function", isfile)
local readFile: ((string) -> (string))? = missing("function", readfile)
local deleteFile: ((string) -> ())? = missing("function", delfile)

-- // Make Config Folder
if not isFolder then
    log("isFolder function is missing from executor enviroment!", "w", false)
elseif not isFolder(CONFIG) then
    if makeFolder then
        log("Failed to find Config folder, attempting to create one!", "w", false)
        makeFolder(CONFIG)
    else
        log("makeFolder function is missing from executor enviroment!", "w", false)
    end
end

-- // Save & Load Functions
function fileSystem.saveConfig(name: string, tbl: { [any]: any }): boolean
    if not writeFile then log("writeFile function is missing from executor enviroment!", "w", false); return false end

    local lines = {}
    for k, v in tbl do
        table_insert(lines, string_format("%s=%s", tostring(k), tostring(v)))
    end

    local success, err = pcall(writeFile, CONFIG .. name .. ".cfg", table_concat(lines, "\n"))
    if not success then log(string_format("Failed to save config \'%s\':\'%s\'!", name, tostring(err)), "w", false); return false end

    log(string_format("Successfully saved config: %s", name), "p", false)

    return true
end

function fileSystem.loadConfig(name: string): { [any]: any }?
    if not isFile or not readFile then log("File system functions are missing from executor enviroment!"); return nil end

    local path = CONFIG .. name .. ".cfg"
    if not isFile(path) then log(string_format("Failed to find config file at %s!", tostring(path))); return nil end

    local success, content = pcall(readFile, path)
    if not success or not content then log(string_format("Failed to read config file at %s!", name), "w", false); return nil end

    local data = {}
    for line in content:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^=]+)=(%S+)$")
        if k and v then
            if v == "true" then v = true
            elseif v == "false" then v = false
            elseif tonumber(v) then v = tonumber(v) end

            data[k] = v
        end
    end

    log(string_format("Successfully loaded config: %s", name), "p", false)

    return data
end

function fileSystem.deleteConfig(name: string): boolean
    if not deleteFile then log("deleteFile function is missing from executor enviroment!", "w", false); return false end

    local path = CONFIG .. name .. ".cfg"

    if isFile and isFile(path) then
        local success = pcall(deleteFile, path)
        if success then
            log(string_format("Successfully deleted config: %s", name), "p", false)
        end
        return success
    end

    log(string_format("Failed to delete config: %s", name), "p", false)

    return false
end

vortex.fileSystem = fileSystem

-- // Utility Functions
function vortex.disconnect(connection: RBXScriptConnection): boolean
    if not connection then
        log("Failed to disconnect, object is nil!")
        return false
    end

    local sessionConnections = currentSession.connections
    local currentConnection = table_find(currentSession.connections, connection)

    if currentConnection then
        table_remove(sessionConnections, currentConnection)
    end

    if connection.Connected then
        connection:Disconnect()
        return true
    end

    log("Connection was already disconnected or inactive.", "p", false)
    return false
end

function vortex.resetVelocity(part: BasePart, clearForces: boolean?): ()
    if not part or not part:IsA("BasePart") then log("Object is not a BasePart!", "w", false); return end

    if clearForces then
        for _, v in part:GetChildren() do
            if v:IsA("BodyVelocity") or v:IsA("BodyForce") or v:IsA("LinearVelocity") then
                v:Destroy()
            end
        end
    end

    part.AssemblyLinearVelocity = Vector3_zero
    part.AssemblyAngularVelocity = Vector3_zero
end

function vortex.getCFrame(target: (Vector3 | CFrame | Instance)?): CFrame?
    if not target then log("Target is nil!", "w", false); return nil end
    local targetType: string = typeof(target)

    if targetType == "CFrame" then
        return target :: CFrame
    elseif targetType == "Vector3" then
        return CFrame.new(target :: Vector3)
    elseif targetType == "Instance" then
        local inst: (Model | Player) = target :: any

        if inst:IsA("Player") then
            local root: BasePart? = vortex.getRoot(inst)

            return root and root.CFrame
        end

        local part: BasePart? = vortex.getBasePart(inst)
        if part then
            return part.CFrame
        elseif inst:IsA("Model") then
            local model: Model = inst :: Model
            return model:GetPivot()
        end
    end

    log("Failed to get CFrame!", "w", false)
    return nil
end

function vortex.getBasePart(target: Instance?): BasePart?
    if not target then log("Target is nil!", "w", false); return nil end

    if target:IsA("BasePart") then return target :: BasePart
    elseif target:IsA("Model") then return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
    elseif target:IsA("Tool") then
        local handle = target:FindFirstChild("Handle")

        if handle and handle:IsA("BasePart") then
            return handle :: BasePart
        end

        return target:FindFirstChildWhichIsA("BasePart") :: BasePart
    end

    log("Failed to get BasePart!", "w", false)
    return nil
end

function vortex.getClosestPlayer(): Player?
    local rootCFrame = vortex.getCFrame(localPlayer)
    if not rootCFrame then log("Failed to get root CFrame!", "w", false); return nil end
    local allPlayers = Players:GetPlayers()
    local closest: Player?
    local closestDistance: number = math_huge

    if #allPlayers <= 1 then
        log("Failed to find other players!", "w", false)
        return nil
    end

    for _, player in allPlayers do
        if not player or not player.Parent or player == localPlayer then continue end
        local targetCFrame = vortex.getCFrame(player)
        if not targetCFrame then log("Failed to find target CFrame!", "w", false); continue end

        local distance = (rootCFrame.Position - targetCFrame.Position).Magnitude
        if closestDistance > distance then
            closest = player
            closestDistance = distance
        end
    end

    return closest
end

-- // Initialization Functions
function vortex.createTimer(durationSeconds: number?): () -> TimerData
    local duration: number = math_max(durationSeconds or DEFAULT_TIMER_DURATION, 0.001)

    local startTime: number = os_clock()

    return function(): TimerData
        local elapsedTime: number = os_clock() - startTime
        local alpha: number = math_clamp(elapsedTime / duration, 0, 1)

        return {
            alpha = alpha,
            elapsedTime = elapsedTime,
            isFinished = elapsedTime >= duration
        }
    end
end

function vortex.createTween(data: TweenData): Tween
    return TweenService:Create(
        data.instance,
        data.tweenInfo,
        data.properties
    )
end

function vortex.createInstance(data: InstanceData): Instance
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

function vortex.createAttachment(parent: BasePart, name: string?): Attachment
    local attachment: Attachment = vortex.createInstance({
        instance = "Attachment",
        name = name or "VortexAttachment",
        parent = parent
    }) :: Attachment

    return attachment
end

function vortex.simulationBoost(radius: number?, intervalSeconds: number?): { stop: () -> () }?
    if not setHidden then log("setHidden function is missing from executor enviroment!", "w", false); return nil end

    intervalSeconds = intervalSeconds or DEFAULT_SIMULATION_INTERVAL
    radius = radius or DEFAULT_SIMULATION_RADIUS
    local isRunning: boolean = true

    local thread: thread?
    thread = task_spawn(function()
        while isRunning do
            if not localPlayer or not localPlayer.Parent then log("Failed to find the LocalPlayer!", "w", false); break end

            pcall(function()
                setHidden(localPlayer, "SimulationRadius", radius)
                setHidden(localPlayer, "MaximumSimulationRadius", radius)
            end)
            task_wait(intervalSeconds)
        end
    end)
    table_insert(currentSession.threads, thread)

    local controller = {} :: { stop: () -> () }
    function controller.stop()
        if not isRunning then log("Failed to stop, not currently running!", "w", false); return end
        isRunning = false

        local index = table_find(currentSession.controllers, controller)
        if index then
            table_remove(currentSession.controllers, index)
        end

        if thread then
            task_cancel(thread)
        end
    end

    table_insert(currentSession.controllers, controller)
    return controller
end

function vortex.netlessAlign(data: InitialNetless): NetlessData?
    if not data then log("Please specify data!", "w", false); return nil end

    local initialTarget: (Vector3 | CFrame | Instance) = data.initialTarget
    local objects: (Instance | { Instance })? = data.objects
    if not objects then log("Failed to get objects from data!", "w", false); return nil end

    local desiredCanCollide: boolean = data.canCollide == true
    local isEnabled: boolean = data.enabled ~= false

    local objectsList: { Instance }

    if typeof(objects) == "Instance" then
        objectsList = { objects } :: any
    elseif typeof(objects) == "table" then
        objectsList = objects :: { Instance }
    else
        objectsList = objects :: any
    end

    local targetCFrame: CFrame = vortex.getCFrame(initialTarget) or CFrame_identity
    local targetAnchor: BasePart = vortex.createInstance({
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
    local anchorAttachment: Attachment = vortex.createAttachment(targetAnchor)

    local VECTOR = NETLESS_VECTOR
    local multipliedVector: number = 1.5

    local managedParts: { BasePart } = {}
    local activeInstances: { Instance } = {}
    local originalCollisions: { [BasePart]: boolean } = {}

    local controller: NetlessData = {} :: NetlessData
    local isRunning: boolean = true
    local conn: RBXScriptConnection?

    local function createNetlessVelocity(): ()
        if conn then return end

        conn = RunService.Heartbeat:Connect(function()
            for i=#managedParts, 1, -1 do
                local part = managedParts[i]
                if not part or not part.Parent then
                    table_remove(managedParts, i)
                    continue
                end

                if isNetworkOwner and isNetworkOwner(part) then
                    part.AssemblyLinearVelocity = VECTOR
                else
                    part.AssemblyLinearVelocity = VECTOR * multipliedVector
                end

                part.AssemblyAngularVelocity = Vector3_zero
            end
        end)

        if conn then
            table_insert(currentSession.connections, conn)
        end
    end

    function controller.update(newTarget: (Vector3 | CFrame | Instance)): ()
        if not isRunning then log("Failed to update, not currently running!", "w", false); return end

        local newCFrame: CFrame? = vortex.getCFrame(newTarget)
        if newCFrame then
            targetAnchor.CFrame = newCFrame
        end
    end

    function controller.setCanCollide(state: boolean): ()
        if not isRunning then log("Failed to set CanCollide, not currently running!", "w", false); return end
        desiredCanCollide = state

        for _, part in managedParts do
            if part and part.Parent then
                part.CanCollide = state
            end
        end
    end

    function controller.setEnabled(state: boolean): ()
        if not isRunning then log("Failed to set enabled, not currently running!", "w", false); return end
        if isEnabled == state then return end
        isEnabled = state

        if not isEnabled then
            if conn then
                vortex.disconnect(conn)
                conn = nil
            end

            for _, instance in activeInstances do
                if instance and instance:IsA("Constraint") then
                    instance.Enabled = false
                end
            end

            for _, part in managedParts do
                if part and part.Parent and originalCollisions[part] ~= nil then
                    part.CanCollide = originalCollisions[part]
                end

                vortex.resetVelocity(part)
            end
        else
            for _, instance in activeInstances do
                if instance and instance:IsA("Constraint") then
                    instance.Enabled = true
                end
            end

            for _, part in managedParts do
                if part and part.Parent then
                    part.CanCollide = desiredCanCollide
                end
            end

            createNetlessVelocity()
        end
    end

    function controller.stop(): ()
        if not isRunning then log("Failed to stop, not currently running!", "w", false); return end
        isRunning = false

        local index = table_find(currentSession.controllers, controller)
        if index then
            table_remove(currentSession.controllers, index)
        end

        if conn then
            vortex.disconnect(conn)
        end

        for _, instance in activeInstances do
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
        local basePart: BasePart? = vortex.getBasePart(object)

        if basePart and not basePart.Anchored then
            if vortex.activeNetless[basePart] then
                vortex.activeNetless[basePart].stop()
            end

            local objectAttachment: Attachment = vortex.createAttachment(basePart)
            local alignPos: AlignPosition = vortex.createInstance({
                instance = "AlignPosition",
                parent = basePart,
                values = {
                    Mode = Enum.PositionAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxForce = math_huge,
                    MaxVelocity = math_huge,
                    Responsiveness = 200,
                    RigidityEnabled = false,
                    ReactionForceEnabled = false
                }
            }) :: AlignPosition

            local alignOrient: AlignOrientation = vortex.createInstance({
                instance = "AlignOrientation",
                parent = basePart,
                values = {
                    Mode = Enum.OrientationAlignmentMode.TwoAttachment,
                    Attachment0 = objectAttachment,
                    Attachment1 = anchorAttachment,
                    MaxTorque = math_huge,
                    MaxAngularVelocity = math_huge,
                    Responsiveness = 200,
                    RigidityEnabled = false,
                    ReactionTorqueEnabled = false
                }
            }) :: AlignOrientation

            originalCollisions[basePart] = basePart.CanCollide
            basePart.CanCollide = false

            table_insert(managedParts, basePart)
            table_insert(activeInstances, objectAttachment)
            table_insert(activeInstances, alignPos)
            table_insert(activeInstances, alignOrient)

            basePart.Destroying:Once(function()
                if isRunning then
                    controller.stop()
                end
            end)
        end
    end

    if #managedParts == 0 then
        targetAnchor:Destroy()
        log("Managed parts is 0, destroyed anchor!", "w", false)
        return nil
    end

    if isEnabled then
        createNetlessVelocity()
    end

    for _, part in managedParts do
        vortex.activeNetless[part] = controller
    end

    table_insert(currentSession.controllers, controller)
    return controller
end

-- // Core Functions
function vortex.teleportTo(target: (Vector3 | CFrame | Instance), useTween: boolean?, tweenSpeed: number?): boolean
    local root: BasePart? = vortex.getRoot(localPlayer)
    local targetCFrame: CFrame? = vortex.getCFrame(target)
    if not root or not targetCFrame then log("Failed to find root or its CFrame!", "w", false); return false end
    tweenSpeed = tweenSpeed or TWEEN_SPEED

    vortex.resetVelocity(root)

    if useTween then
        local tween: Tween = vortex.createTween({
            instance = root,
            tweenInfo = TweenInfo.new(
                tweenSpeed,
                Enum.EasingStyle.Linear
            ),
            properties = {
                CFrame = targetCFrame
            }
        })
        tween:Play()
        tween.Completed:Wait()
    else
        root.CFrame = targetCFrame
    end

    return (root.Position - targetCFrame.Position).Magnitude <= MAX_TELEPORT_CHECK_DISTANCE
end

function vortex.view(target: Instance?): boolean
    local currentCamera: Camera = Workspace.CurrentCamera
    if not currentCamera then log("Failed to find CurrentCamera!", "w", false); return false end

    local function setCamera(subject: Instance): ()
        currentCamera.CameraSubject = subject :: ( BasePart | Humanoid )
    end

    local targetType: string = typeof(target)
    if not target then
        local humanoid: Humanoid? = vortex.getHumanoid(localPlayer)

        if humanoid then
            log("Failed to find target, attempting to set camera to LocalPlayers Humanoid!", "w", false)
            setCamera(humanoid)

            return true
        end

        log("Failed to find target!", "w", false)
        return false
    end

    if targetType == "Instance" then
        local inst: Instance = target :: Instance

        if inst:IsA("Humanoid") then
            setCamera(inst)
            return true
        elseif inst:IsA("Player") then
            local humanoid: Humanoid? = vortex.getHumanoid(inst :: Player) :: Humanoid

            if humanoid then
                setCamera(humanoid)
                return true
            end
        elseif inst:IsA("BasePart") then setCamera(inst); return true
        elseif inst:IsA("Model") then
            local humanoid: Humanoid? = vortex.getHumanoid(inst :: Model)
            local basePart: BasePart? = vortex.getBasePart(inst)

            if humanoid then
                setCamera(humanoid)

                return true
            elseif inst.PrimaryPart or basePart then
                setCamera(inst.PrimaryPart or basePart)

                return true
            end
        end
    end

    log("Failed to view!", "w", false)
    return false
end

function vortex.unview(): boolean
    return vortex.view(localPlayer)
end

function vortex.findTool(player: Player, toolName: string): Tool?
    local checkContainer = function(container: Instance?): Tool?
        if not container then log("Please specify a container!", "w", false); return nil end

        local item: (Tool | Instance)? = container:FindFirstChild(toolName)

        if not item then
            for _, v in container:GetChildren() do
                if v and string_find(v.Name:lower(), toolName:lower()) then
                    item = v
                    break
                end
            end
        end

        if item and item:IsA("Tool") then
            return item :: Tool
        end

        return nil
    end

    return checkContainer(player and player:FindFirstChildOfClass("Backpack")) or checkContainer(vortex.getChar(player))
end

function vortex.equipTool(tool: Tool, unequipTools: boolean?): Tool?
    unequipTools = unequipTools ~= false

    local character: Model? = vortex.getChar(localPlayer)
    if not character then log("Failed to find Character!", "w", false); return nil end
    local humanoid: Humanoid? = vortex.getHumanoid(character)
    if not humanoid then log("Failed to find Humanoid!", "w", false); return nil end

    if unequipTools then
        humanoid:UnequipTools()
    end

    tool.Parent = character

    return tool
end

function vortex.dropTool(tool: Tool): Tool?
    vortex.equipTool(tool)
    tool.Parent = Workspace

    return tool
end

-- // Player & Entity Functions
function vortex.findPlayer(target: string?): Player?
    if not target or target == "" then log("Target is nil or blank string!", "w", false); return nil end

    local partial: string = string_lower(target)
    local allPlayers = Players:GetPlayers()

    if partial == "me" then
        return localPlayer
    elseif partial == "random" then
        local others: { Player } = {}

        for _, player in allPlayers do
            if player ~= localPlayer then
                table_insert(others, player)
            end
        end

        if #others > 0 then
            return others[math_random(1, #others)]
        end

        return nil
    end

    local IsMatch = function(name: string): boolean
        return string_sub(string_lower(name), 1, #partial) == partial
    end

    for _, player in allPlayers do
        if (IsMatch(player.Name) or IsMatch(player.DisplayName)) then
            return player
        end
    end

    log("Failed to find Player!", "w", false)
    return nil
end

function vortex.getChar(player: Player): Model?
    return player and (player.Character :: Model?)
end

-- // Check Character
local function checkCharacter(target: (Model | Player)?): Model?
    if not target then log("Target is nil!", "w", false); return nil end

    if target:IsA("Model") then return target :: Model
    elseif target:IsA("Player") then return vortex.getChar(target :: Player) :: Model end

    log("Failed to check character!", "w", false)
    return nil
end

function vortex.getRoot(target: (Model | Player)?, timeout: number?): BasePart?
    if not target then log("Target is nil!", "w", false); return nil end
    local character: Model? = checkCharacter(target)
    if not character then
        return nil
    end

    local root: BasePart? = getBasePartChild(character, "HumanoidRootPart")

    if root then
        return root
    end

    local waitRoot: Instance? = character:WaitForChild("HumanoidRootPart", timeout or 1)

    if waitRoot and waitRoot:IsA("BasePart") then
        return waitRoot :: BasePart
    end

    return nil
end

function vortex.getHumanoid(target: (Model | Player)?, timeout: number?): Humanoid?
    if not target then log("Target is nil!", "w", false); return nil end
    local character: Model? = checkCharacter(target)
    if not character then
        return nil
    end

    local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        return humanoid
    end

    local waitHumanoid: Instance? = character:WaitForChild("Humanoid", timeout or 1)

    if waitHumanoid and waitHumanoid:IsA("Humanoid") then
        return waitHumanoid :: Humanoid
    end

    return nil
end

function vortex.breakJoints(): ()
    local character: Model? = vortex.getChar(localPlayer)
    if not character then log("Failed to find Character!", "w", false); return end
    for _, joint in character:GetDescendants() do
        if joint:IsA("Motor6D") then
            joint:Destroy()
        end
    end
end

function vortex.unsit(): ()
    local humanoid: Humanoid? = vortex.getHumanoid(localPlayer)
    if not humanoid then log("Failed to find Humanoid!", "w", false); return end
    if not humanoid.Sit then log("Humanoid is not currently sitting!", "w", false); return end

    local seatedState: EnumItem = Enum.HumanoidStateType.Seated
    if not seatedState then log("Failed to find HumanoidStateType.Seated!", "w", false); return end

    humanoid.Sit = false
    humanoid:SetStateEnabled(seatedState, false)

    task_delay(0.5, function()
        if not humanoid then log("Failed to find Humanoid!", "w", false); return end
        humanoid:SetStateEnabled(seatedState, true)
    end)
end

function vortex.teleportVehicle(target: (Vector3 | CFrame | Instance), useFallback: boolean?): boolean
    local targetCFrame: CFrame? = vortex.getCFrame(target)
    if not targetCFrame then log("Failed to find target CFrame!", "w", false); return false end
    local character: Model? = vortex.getChar(localPlayer)
    if not character then log("Failed to find Character!", "w", false); return false end
    local root: BasePart? = vortex.getRoot(character)
    if not root then log("Failed to find root!", "w", false); return false end
    local humanoid: Humanoid? = vortex.getHumanoid(character)
    if not humanoid then log("Failed to find Humanoid!", "w", false); return false end
    local seat: (Seat | VehicleSeat)? = humanoid.SeatPart
    if not seat then log("Failed to find seat!", "w", false); return false end
    local seatCFrame: CFrame = seat.CFrame

    local vehicle: Model? = findVehicle(seat :: (VehicleSeat | Seat))

    if not vehicle then
        log("Failed to find vehicle, attempting fallback!", "w", false)
        vortex.resetVelocity(seat)

        return vortex.teleportTo(targetCFrame)
    end

    if vehicle then
        if useFallback then
            vortex.resetVelocity(seat)
            vehicle:PivotTo(targetCFrame)

            return true
        end

        local jointData: { JointData } = {}
        local gyros: { BodyGyro } = {}

        for _, joint in vehicle:GetDescendants() do
            local jointParent = joint.Parent

            if joint and (joint:IsA("Rotate") or joint:IsA("AlignPosition") or joint:IsA("AlignOrientation") or joint:IsA("VectorForce")) and joint.Part0 and joint.Part1 then
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

        vortex.resetVelocity(seat)
        vortex.teleportTo(targetCFrame)

        for _, data in jointData do
            vortex.resetVelocity(data.part0)
            vortex.resetVelocity(data.part1)

            data.part0.CFrame = targetCFrame:ToWorldSpace(data.relativePart0)
            data.part1.CFrame = targetCFrame:ToWorldSpace(data.relativePart1)
        end

        for _, gyro in gyros do
            local relativeRotation: CFrame = seatCFrame.Rotation:Inverse() * gyro.CFrame.Rotation
            gyro.CFrame = targetCFrame.Rotation * relativeRotation
        end

        task_defer(function()
            if seat and seat.Parent then
                vortex.resetVelocity(seat)

                for _, v in vehicle:GetDescendants() do
                    if v:IsA("BasePart") then
                        vortex.resetVelocity(v)
                    end
                end
            end
        end)

        return true
    end

    log("Failed to teleport vehicle!", "w", false)
    return false
end

-- // Methods
function vortex:GetVersion(): string
    return _version
end

-- // Extra
function vortex.cleanUp(): ()
    log("Cleaning up.", "p", false)
    local sessionConnections = currentSession.connections
    local sessionThreads = currentSession.threads
    local sessionInstances = currentSession.instances
    local sessionControllers = currentSession.controllers

    for i=#sessionConnections, 1, -1 do
        local connection = sessionConnections[i]
        if typeof(connection) == "RBXScriptConnection" then
            vortex.disconnect(connection)
        end
    end
    table_clear(sessionConnections)

    for i=#sessionThreads, 1, -1 do
        local thread = sessionThreads[i]
        if typeof(thread) == "thread" then
            task_cancel(thread)
        end
    end
    table_clear(sessionThreads)

    for i=#sessionInstances, 1, -1 do
        local instance = sessionInstances[i]
        if typeof(instance) == "Instance" then
            instance:Destroy()
        end
    end
    table_clear(sessionInstances)

    for i=#sessionControllers, 1, -1 do
        local controller = sessionControllers[i]
        if controller and typeof(controller.stop) == "function" then
            controller.stop()
        end
    end
    table_clear(sessionControllers)
end

function vortex.dumpLogs(clear: boolean?): { LogEntry }
    log("Dumping logs.", "p", false)
    local logsCopy = table_clone(vortex.debugLogs)
    for _, entry in logsCopy do
        log(entry.text, entry.type, true)
    end

    if clear then
        table_clear(vortex.debugLogs)
    end

    return logsCopy
end

function vortex.exit(): ()
    log("Exiting game!", "w", false)
    game:Shutdown()
end

function vortex.getJobId(): string
    return game.JobId :: string
end

function vortex.joinJobId(jobId: string?, placeId: number?): { success: boolean, err: string }
    local targetJobId: string = jobId or vortex.getJobId()
    local targetPlaceId: number = placeId or currentPlaceId

    local success, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(targetPlaceId, targetJobId, localPlayer)
    end)

    return { success, err } :: any
end

function vortex.rejoin(): ()
    log("Attempting to rejoin..", "p", false)

    local attempt = vortex.joinJobId(vortex.getJobId(), currentPlaceId)
    if not attempt.success then
        log("Failed to rejoin!", "w", false)
    end
end

function vortex.isStudio(): boolean
    return RunService:IsStudio() :: boolean
end

function vortex.generateUuid(): string
    return HttpService:GenerateGUID(false) :: string
end

return vortex
