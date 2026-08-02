# Vortex
A lightweight, high-performance Luau library for Roblox.

## Quick Start
```lua
local vortex = loadstring(game:HttpGet("https://raw.githubusercontent.com/zkyoi/Vortex/refs/heads/main/src/main.luau"))()

-- Teleport to a random player
local targetPlayer = vortex.findPlayer("random")
if targetPlayer then
	vortex.teleportTo(targetPlayer)
end
```
