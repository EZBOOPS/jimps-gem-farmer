local settings      = require 'core.settings'
local tracker       = require 'core.tracker'
local world         = require 'core.world'
local stuck_timeout = require 'tasks.stuck_timeout'

local plugin_label = 'gem_farmer'

-- UR control helpers
local function ur_set_enabled(state)
    if _G.UNIVERSAL_ROTATION then _G.UNIVERSAL_ROTATION.set_enabled(state) end
end

local function ur_free()
    if UniversalRotationPlugin then
        UniversalRotationPlugin.set_external_target_override(false)
    end
    ur_set_enabled(true)
    _G.EXTERNAL_ROTATION_TARGET = nil
end

-- Navigation constants
local ENTRY_DELAY         = 1.0
local WELL_INTERACT_RANGE = 6.0
local BOSS_POS            = vec3:new(-5.1768, -3.9268, 2.0000)
local BOSS_PATHFIND_DIST  = 20.0
local NAV_SAMPLE_INTERVAL = 6.0
local NAV_STUCK_DIST      = 10.0
local BOSS_DIAGONAL       = -1.25
local DIAGONAL_TOLERANCE  = 5.0
local STRAFE_WAYPOINT     = vec3:new(50.0, 51.25, 0.0)

-- Enemy proximity for conditional rotation
local NEARBY_RANGE_SQ = 5.0 * 5.0

local task = {
    name             = 'rush_to_boss',
    status           = 'idle',
    well_done        = false,
    nav_sample_pos   = nil,
    nav_sample_time  = -1,
    phase            = 'strafe',
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    task.well_done       = false
    task.nav_sample_pos  = nil
    task.nav_sample_time = -1
    task.phase           = 'strafe'
    ur_free()
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

-- Apply rush-phase rotation policy each tick.
-- disable_rotation_rush OFF      → ur_free(), UR runs normally, no interference
-- disable_rotation_rush ON, slider 0  → UR fully suppressed during rush
-- disable_rotation_rush ON, slider N  → UR enabled only when >=N enemies within 5m;
--                                        UR handles its own targeting when active
local function apply_rush_rotation(player_pos)
    if not settings.disable_rotation_rush then
        ur_free()
        return
    end

    local min = settings.min_targets_to_attack

    if min == 0 then
        ur_set_enabled(false)
        _G.EXTERNAL_ROTATION_TARGET = nil
        return
    end

    -- Count enemies within 5m; let UR pick its own targets when threshold is met
    local count = 0
    for _, actor in ipairs(actors_manager.get_enemy_actors()) do
        if not actor:is_dead() then
            local ok, apos = pcall(function() return actor:get_position() end)
            if ok and apos then
                local dx = player_pos:x() - apos:x()
                local dy = player_pos:y() - apos:y()
                if (dx*dx + dy*dy) <= NEARBY_RANGE_SQ then
                    count = count + 1
                end
            end
        end
    end

    if count >= min then
        ur_set_enabled(true)
        _G.EXTERNAL_ROTATION_TARGET = nil  -- let UR pick freely
    else
        ur_set_enabled(false)
        _G.EXTERNAL_ROTATION_TARGET = nil
    end
end

task.shouldExecute = function()
    return not world.is_outside() and not tracker.boss_found and not tracker.boss_dead
end

task.Execute = function()
    if BatmobilePlugin == nil then
        task.status = 'ERROR: BatmobilePlugin not loaded'
        return
    end

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
    elseif tracker.enter_time < 0 then
        tracker.enter_time = now
    end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()

    apply_rush_rotation(player_pos)

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
        -- Hand off: clear override so fight_boss gets clean UR state
        ur_free()
        console.print('[GemFarmer] Boss detected — handing off to fight task')
        return
    end

    if try_interact_well(player_pos) then return end

    local px, py = player_pos:x(), player_pos:y()
    local diagonal = px - py

    if task.phase == 'strafe' and math.abs(diagonal - BOSS_DIAGONAL) <= DIAGONAL_TOLERANCE then
        task.phase = 'charge'
        console.print(string.format('[GemFarmer] Aligned on boss diagonal (%.2f) — charging', diagonal))
    end

    local boss_dist = player_pos:dist_to(BOSS_POS)

    if task.phase == 'strafe' then
        local strafe_dist = player_pos:dist_to(STRAFE_WAYPOINT)
        task.status = string.format('strafing to align (diag=%.1f target=%.1f, %.0fm)', diagonal, BOSS_DIAGONAL, strafe_dist)
        BatmobilePlugin.set_target(plugin_label, STRAFE_WAYPOINT, false)
        BatmobilePlugin.resume(plugin_label)
        BatmobilePlugin.update(plugin_label)
        BatmobilePlugin.move(plugin_label)
    else
        if boss_dist <= BOSS_PATHFIND_DIST then
            BatmobilePlugin.pause(plugin_label)
            if boss_dist <= 8.0 then
                tracker.boss_found    = true
                tracker.boss_last_pos = BOSS_POS
                pathfinder.request_move(player_pos)
                ur_free()
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
