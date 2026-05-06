local settings      = require 'core.settings'
local tracker       = require 'core.tracker'
local world         = require 'core.world'
local stuck_timeout = require 'tasks.stuck_timeout'

local plugin_label = 'gem_farmer'

local ENTRY_DELAY         = 1.0    -- seconds after entering before starting navigation
local WELL_INTERACT_RANGE = 6.0    -- metres — interact with healing well
local BOSS_POS            = vec3:new(-5.1768, -3.9268, 2.0000)
local BOSS_PATHFIND_DIST  = 20.0   -- switch to pathfinder within this range

local NAV_SAMPLE_INTERVAL = 6.0
local NAV_STUCK_DIST      = 10.0

-- Screen-north = (-1,-1) in XY. "Boss is due north" when px-py == bx-by.
-- bx-by = -5.1768 - (-3.9268) = -1.25
-- Strafe waypoint: a point on that diagonal (px-py=-1.25) that sits in open
-- dungeon space, well clear of the entry-side geometry (X≈90-170).
-- Chosen: X=50, Y=51.25 (50 - 51.25 = -1.25 ✓)
local BOSS_DIAGONAL       = -1.25   -- target value of (px - py) for alignment
local DIAGONAL_TOLERANCE  = 5.0     -- units — close enough to diagonal to start charging
local STRAFE_WAYPOINT     = vec3:new(50.0, 51.25, 0.0)

local task = {
    name             = 'rush_to_boss',
    status           = 'idle',
    well_done        = false,
    nav_sample_pos   = nil,
    nav_sample_time  = -1,
    phase            = 'strafe',   -- 'strafe' | 'charge'
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    task.well_done       = false
    task.nav_sample_pos  = nil
    task.nav_sample_time = -1
    task.phase           = 'strafe'
end

local function is_butcher(actor)
    local name = actor:get_skin_name()
    return name and name:lower():find('butcher') ~= nil
end

local function find_boss(player_pos)
    for _, actor in ipairs(actors_manager.get_enemy_actors()) do
        if actor:is_boss() and not actor:is_dead() and not is_butcher(actor) then
            if actor:get_position():dist_to(player_pos) < settings.boss_range then
                return actor
            end
        end
    end
    return nil
end

local function try_interact_well(player_pos)
    if task.well_done then return false end
    for _, actor in ipairs(actors_manager.get_all_actors()) do
        local name = actor:get_skin_name() or ''
        if name == 'Healing_Well_Basic' then
            local dist = actor:get_position():dist_to(player_pos)
            if dist <= WELL_INTERACT_RANGE then
                console.print(string.format('[GemFarmer] Interacting with Healing_Well_Basic (%.1fm)', dist))
                interact_object(actor)
                task.well_done = true
                return false
            else
                BatmobilePlugin.pause(plugin_label)
                pathfinder.request_move(actor:get_position())
                task.status = string.format('beelining to healing well (%.1fm)', dist)
                return true
            end
        end
    end
    return false
end

task.shouldExecute = function()
    return world.is_inside() and not tracker.boss_found and not tracker.boss_dead
end

local function suppress_rotation()
    if settings.disable_rotation_rush and UniversalRotationPlugin then
        UniversalRotationPlugin.disable()
    end
end

local function restore_rotation()
    if UniversalRotationPlugin then
        UniversalRotationPlugin.enable()
    end
end

task.Execute = function()
    if BatmobilePlugin == nil then
        task.status = 'ERROR: BatmobilePlugin not loaded'
        return
    end

    suppress_rotation()

    local now = get_time_since_inject()

    if stuck_timeout.slide_until > 0 and now < stuck_timeout.slide_until then
        task.status = string.format('unsticking (%.1fs)', stuck_timeout.slide_until - now)
        BatmobilePlugin.resume(plugin_label)
        BatmobilePlugin.update(plugin_label)
        BatmobilePlugin.move(plugin_label)
        task.nav_sample_pos  = nil
        task.nav_sample_time = -1
        return
    end
    if stuck_timeout.slide_until > 0 and now >= stuck_timeout.slide_until then
        stuck_timeout.slide_until = -1
        task.nav_sample_pos  = nil
        task.nav_sample_time = -1
        console.print('[GemFarmer] Unstick done — resuming boss path')
    end

    if tracker.enter_time > 0 and (now - tracker.enter_time) < ENTRY_DELAY then
        task.status = 'waiting for dungeon load'
        return
    end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()

    if task.nav_sample_pos == nil then
        task.nav_sample_pos  = player_pos
        task.nav_sample_time = now
    elseif (now - task.nav_sample_time) >= NAV_SAMPLE_INTERVAL then
        local units_moved = player_pos:dist_to(task.nav_sample_pos)
        if units_moved < NAV_STUCK_DIST then
            console.print(string.format('[GemFarmer] Nav stuck (%.1f units in %.0fs) — unsticking', units_moved, NAV_SAMPLE_INTERVAL))
            stuck_timeout.slide_until = now + settings.slide_duration
            task.nav_sample_pos  = nil
            task.nav_sample_time = -1
            return
        end
        task.nav_sample_pos  = player_pos
        task.nav_sample_time = now
    end

    local boss = find_boss(player_pos)
    if boss then
        tracker.boss_found    = true
        tracker.boss_last_pos = boss:get_position()
        BatmobilePlugin.pause(plugin_label)
        pathfinder.request_move(player_pos)
        restore_rotation()
        console.print('[GemFarmer] Boss detected — handing off to fight task')
        return
    end

    if try_interact_well(player_pos) then return end

    local px, py = player_pos:x(), player_pos:y()
    local diagonal = px - py

    -- Transition from strafe to charge once aligned on boss diagonal
    if task.phase == 'strafe' and math.abs(diagonal - BOSS_DIAGONAL) <= DIAGONAL_TOLERANCE then
        task.phase = 'charge'
        console.print(string.format('[GemFarmer] Aligned on boss diagonal (%.2f) — charging', diagonal))
    end

    local boss_dist = player_pos:dist_to(BOSS_POS)

    if task.phase == 'strafe' then
        -- Drive toward strafe waypoint until diagonally aligned with boss
        local strafe_dist = player_pos:dist_to(STRAFE_WAYPOINT)
        task.status = string.format('strafing to align (diag=%.1f target=%.1f, %.0fm)', diagonal, BOSS_DIAGONAL, strafe_dist)
        BatmobilePlugin.set_target(plugin_label, STRAFE_WAYPOINT, false)
        BatmobilePlugin.resume(plugin_label)
        BatmobilePlugin.update(plugin_label)
        BatmobilePlugin.move(plugin_label)

    else
        -- Aligned — charge straight at boss
        if boss_dist <= BOSS_PATHFIND_DIST then
            BatmobilePlugin.pause(plugin_label)
            if boss_dist <= 8.0 then
                tracker.boss_found    = true
                tracker.boss_last_pos = BOSS_POS
                pathfinder.request_move(player_pos)
                restore_rotation()
                console.print('[GemFarmer] Arrived at boss area — forcing fight handoff')
                return
            end
            task.status = string.format('final approach to boss (%.1fm)', boss_dist)
            pathfinder.request_move(BOSS_POS)
        else
            task.status = string.format('charging to boss (%.1fm)', boss_dist)
            BatmobilePlugin.set_target(plugin_label, BOSS_POS, false)
            BatmobilePlugin.resume(plugin_label)
            BatmobilePlugin.update(plugin_label)
            BatmobilePlugin.move(plugin_label)
        end
    end
end

return task
