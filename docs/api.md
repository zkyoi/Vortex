# Vortex API

## Introduction

In order to use Vortex library, you need to first load the module.

You can either load from a fixed version, which is highly recommended.

```lua
local _version = "v1.3.2" -- Latest stable repository version
local vortex = loadstring(game:HttpGet("https://github.com/zkyoi/Vortex/releases/download/" .. _version .. "/main.luau", true))()

-- Gets the current version
print(vortex:GetVersion())
```

You can load from the latest version.

```lua
local vortex = loadstring(game:HttpGet("https://github.com/zkyoi/Vortex/releases/latest/download/main.luau", true))()

-- Gets the current version
print(vortex:GetVersion())
```

Or you can load directly from the repository.

```lua
local vortex = loadstring(game:HttpGet("https://raw.githubusercontent.com/zkyoi/Vortex/refs/heads/main/src/main.luau", true))()

-- Gets the current version
print(vortex:GetVersion())
```

> [!CAUTION]
> This is not recommended and prone to errors!

Once you have chosen a method to load the library, you're ready to go!

Just read the API to learn how to use specific functions, variables, etc.

## Utility Functions

### vortex.Disconnect

Safely disconnects a RBXScriptConnection.

```lua
function vortex.Disconnect(connection: RBXScriptConnection): boolean
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `connection` | `RBXScriptConnection` | Yes | The connection to disconnect. |

---

## Returns
| Type | Description |
| :--- | :--- |
| `boolean` | Returns 'true' if the connection was successfully disconnected, or 'false' if it was already disconnected/nil. |

## Example

This example will create a connection, wait 5 seconds, then disconnect it.

```lua
local connection
connection = game:GetService("Workspace").ChildAdded:Connect(function(child)
    print(string.format("%s was added to the workspace!", child.Name))
end)

task.wait(5)

if vortex.Disconnect(connection) then -- Disconnects the connection
    print("Successfully disconnected the connection!")
else
    warn("Failed to disconnect the connection!")
end
```

---

### vortex.ResetVelocity

Sets the AssemblyLinearVelocity and AssemblyAngularVelocity of a BasePart to Vector3.zero.

```lua
function vortex.ResetVelocity(part: BasePart, clearForces: boolean?): ()
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `part` | `BasePart` | Yes | The BasePart that is affected |
| `clearForces` | `boolean` | No | Clears all forces on the BasePart. |

## Returns
`None`

---

## Example

This example will call the LocalPlayer's root then reset its velocity.

```lua
local localPlayer = game:GetService("Players").LocalPlayer
local root = vortex.GetRoot(localPlayer)

if root then
    vortex.ResetVelocity(root) -- Resets the roots velocity
end
```

---

### vortex.GetCFrame

Gets the CFrame of a Vector3, CFrame, or an Instance.

```lua
function vortex.GetCFrame(target: (Vector3 | CFrame | Instance)?): CFrame?
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `target` | `Vector3 \| CFrame \| Instance` | Yes | The target you want to retrieve the CFrame of. |

## Returns
| Type | Description |
| :--- | :--- |
| `CFrame` | If successful returns 'CFrame' and if it fails returns 'nil'. |

---

## Example

This example will call the LocalPlayer's root then print its CFrame.

```lua
local localPlayer = game:GetService("Players").LocalPlayer
local root = vortex.GetRoot(localPlayer)

if root then
    local rootCFrame = vortex.GetCFrame(root) -- Gets the roots CFrame
    if rootCFrame then
        print(rootCFrame)
    else
        warn("Failed to get roots CFrame!")
    end
end
```

---

### vortex.GetBasePart

Gets the BasePart of an Instance.

```lua
function vortex.GetBasePart(target: Instance?): BasePart?
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `target` | `Instance` | Yes | The target you want to retrieve the BasePart of. |

## Returns
| Type | Description |
| :--- | :--- |
| `BasePart` | If successful returns 'BasePart' and if it fails returns 'nil'. |

---

## Example

This example will get a BasePart from the LocalPlayer's character and print the name.

```lua
local localPlayer = game:GetService("Players").LocalPlayer
local character = vortex.GetChar(localPlayer)
if not character then warn("Failed to find character!") return end
local basePart = vortex.GetBasePart(character) -- Gets a BasePart from the character

if basePart then
    print(basePart.Name)
else
    warn("Failed to get BasePart!")
end
```

---

### vortex.GetClosestPlayer

Gets the closest player to the LocalPlayer's character.

```lua
function vortex.GetClosestPlayer(): Player?
```

---

## Returns
| Type | Description |
| :--- | :--- |
| `Player` | If successful returns a 'Player' and if it fails returns 'nil'. |

---

## Example

This example will get the closest player and print their name.
```lua
local closestPlayer = vortex.GetClosestPlayer() -- Gets the closest player
if closestPlayer then
    print(closestPlayer.Name)
else
    warn("Failed to get a player!")
end
```

---

## Initialization Functions

### vortex.CreateTimer

Creates a step function which acts as a timer.

```lua
function vortex.CreateTimer(durationSeconds: number?): () -> timerData
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `durationSeconds` | `number` | No | The duration of seconds you would like the timer to last. |

## Returns
| Type | Description |
| :--- | :--- |
| `() -> timerData` | Returns a step function, that when called, runs and returns the current timerData.  |

## Types

```lua
export type timerData = {
    alpha: number,
    elapsedTime: number,
    isFinished: boolean
}
```

---

## Example

This example will create a timer which runs for 3 seconds.

```lua
local RunService = game:GetService("RunService")
local getTimer = vortex.CreateTimer(3) -- CreateTimer

local connection
connection = RunService.RenderStepped:Connect(function()
    local data = getTimer() -- Using the function

    print(string.format("Current Progress: %.2f%% (Elapsed %.2f)", data.alpha * 100, data.elapsedTime))

    if data.isFinished then
        print("Timer has finished!")
        vortex.Disconnect(connection)
    end
end)
```

---

### vortex.CreateTween

Creates a Tween.

```lua
function vortex.CreateTween(data: tweenData): Tween
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `data` | `tweenData` | Yes | The tweenData which will be created. |

## Returns
| Type | Description |
| :--- | :--- |
| `Tween` | Creates then returns the created Tween. |

## Types
```lua
export type tweenData = {
    instance: Instance,
    tweenInfo: TweenInfo,
    properties: { [string]: any }
}
```

---

## Example

This example will create a tween to move the root 10 studs above its current position.

```lua
local localPlayer = game:GetService("Players").LocalPlayer
local root = vortex.GetRoot(localPlayer)

if root then
    local rootCFrame = vortex.GetCFrame(root)
    if rootCFrame then
        vortex.CreateTween({
            instance = root,
            tweenInfo = TweenInfo.new(
                0.2
            ),
            properties = {
                CFrame = CFrame.new(rootCFrame.Position + Vector3.new(0, 10, 0))
            }
        }):Play() -- Creates and plays the tween
    else
        warn("Failed to get roots CFrame!")
    end
end
```

---

### vortex.CreateInstance

Creates an Instance.

```lua
function vortex.CreateInstance(data: instanceData): Instance
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `data` | `instanceData` | Yes | The instanceData which will be created. |

## Returns
| Type | Description |
| :--- | :--- |
| `Instance` | Creates then returns the created Instance. |

## Types
```lua
export type instanceData = {
    instance: string,
    name: string?,
    values: { [string]: any? }?,
    parent: Instance?
}
```

---

## Example

This example will create a part in the workspace.
```lua
vortex.CreateInstance({
    instance = "Part",
    parent = game:GetService("Workspace")
}) -- Creates an Instance of a 'part'
```

---

### vortex.CreateAttachment

Creates an Attachment.

```lua
function vortex.CreateAttachment(parent: BasePart, name: string?): Attachment
```

---

## Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `parent` | `BasePart` | Yes | Where the attachment will be created. |
| `name` | `string` | No | Name of the attachment. |

## Returns
| Type | Description |
| :--- | :--- |
| `Attachment` | Creates then returns the created Attachment. |

---

## Example

This example will create a part in the workspace and then create an attachment in that part.
```lua
local part = vortex.CreateInstance({
    instance = "Part",
    parent = game:GetService("Workspace")
})

local attachment = vortex.CreateAttachment(part) -- Creates an attachment
```

---

> [!NOTE]
> The documentation for this API is not currently finished!
