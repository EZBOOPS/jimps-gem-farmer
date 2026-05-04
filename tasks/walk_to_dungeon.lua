local tracker = require 'core.tracker'
local world   = require 'core.world'
local paths   = require 'core.paths'

local plugin_label    = 'gem_farmer'
local WAYPOINT_ARRIVE = 12.0   -- metres — advance to next waypoint when this close
local ENTRANCE_RANGE  = 30.0   -- metres — stop when this close to dungeon entrance

local task = {
    name        = 'walk_to_dungeon',
    status      = 'idle',
    wp_index    = 1,
    initialized = false,
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    task.wp_index    = 1
    task.initialized = false
end

local function entrance_pos()
    local ap = paths.approach
    if ap and #ap > 0 then return ap[#ap] end
    return nil
end

task.shouldExecute = function()
    if not world.is_outside() then return false end
    if tracker.boss_dead then return false end
    if not paths.approach or #paths.approach == 0 then return false end
    local ep = entrance_pos()
    if not ep then return false end
    local player = get_local_player()
    if not player then return false end
    return player:get_position():dist_to(ep) >= ENTRANCE_RANGE
end

task.Execute = function()
    if BatmobilePlugin == nil then
        task.status = 'ERROR: BatmobilePlugin not loaded'
        return
    end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()
    local ap = paths.approach

    -- Start from nearest waypoint on first execute
    if not task.initialized then
        task.initialized = true
        local best_i, best_d = 1, math.huge
        for i, wp in ipairs(ap) do
            local d = player_pos:dist_to(wp)
            if d < best_d then best_i, best_d = i, d end
        end
        task.wp_index = best_i
        console.print(string.format('[GemFarmer] walk_to_dungeon: starting at waypoint %d/%d', best_i, #ap))
    end

    -- Advance past waypoints we're already close to
    while task.wp_index <= #ap and player_pos:dist_to(ap[task.wp_index]) < WAYPOINT_ARRIVE do
        task.wp_index = task.wp_index + 1
    end

    if task.wp_index > #ap then
        task.status = 'arrived — handing off to enter_dungeon'
        BatmobilePlugin.pause(plugin_label)
        return
    end

    local target = ap[task.wp_index]
    task.status  = string.format('walking to dungeon [%d/%d] (%.0fm to entrance)', task.wp_index, #ap, player_pos:dist_to(entrance_pos()))
    BatmobilePlugin.set_target(plugin_label, target, false)
    BatmobilePlugin.resume(plugin_label)
    BatmobilePlugin.update(plugin_label)
    BatmobilePlugin.move(plugin_label)
end

return task
