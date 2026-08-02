# Vortex
A lightweight, high-performance Luau library for Roblox.

## Quick Start
```lua
local _version = "v0.1.0-alpha"
local vortex = loadstring(game:HttpGet("https://github.com/zkyoi/Vortex/releases/download/" .. _version .. "/main.luau"))()

-- Teleport to a random player
local targetPlayer = vortex.findPlayer("random")
if targetPlayer then
    vortex.teleportTo(targetPlayer)
end
```
