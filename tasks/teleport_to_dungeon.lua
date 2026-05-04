local tracker = require 'core.tracker'
local world   = require 'core.world'
local paths   = require 'core.paths'

local TEMIS_WAYPOINT     = 0x1CE51E  -- Temis waypoint SNO
local TELEPORT_COOLDOWN  = 12.0      -- seconds between teleport attempts
local ENTRANCE_RANGE     = 10.0      -- metres — within this = already close enough

local teleport_time = -1

local task = {
    name   = 'teleport_to_dungeon',
    status = 'idle',
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    teleport_time = -1
end

local function entrance_pos()
    local ap = paths.approach
    if ap and #ap > 0 then return ap[#ap] end
    return nil
end

task.shouldExecute = function()
    if tracker.boss_dead then return false end
    if world.is_inside() then return false end

    -- If already in the overworld, only teleport if approach path exists and we are
    -- nowhere near the entrance (walk_to_dungeon will take over once we land at Temis)
    if world.is_outside() then
        local ep = entrance_pos()
        if not ep then return false end
        local player = get_local_player()
        if not player then return false end
        -- Close enough — walk_to_dungeon / enter_dungeon will handle it
        if player:get_position():dist_to(ep) < ENTRANCE_RANGE then return false end
        -- Already recently teleported — give walk_to_dungeon time to work
        local now = get_time_since_inject()
        if teleport_time > 0 and (now - teleport_time) < TELEPORT_COOLDOWN then return false end
        return true
    end

    -- Unknown world (e.g. lobby, different zone) — always teleport
    local now = get_time_since_inject()
    if teleport_time > 0 and (now - teleport_time) < TELEPORT_COOLDOWN then return false end
    return true
end

task.Execute = function()
    task.status = 'teleporting to Temis'
    teleport_time = get_time_since_inject()
    teleport_to_waypoint(TEMIS_WAYPOINT)
    console.print('[GemFarmer] Teleporting to Temis waypoint')
end

return task
