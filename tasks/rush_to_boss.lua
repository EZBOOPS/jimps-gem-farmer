local settings     = require 'core.settings'
local tracker      = require 'core.tracker'
local world        = require 'core.world'

local plugin_label = 'gem_farmer'

local ENTRY_DELAY         = 1.0    -- seconds after entering before starting navigation
local WELL_INTERACT_RANGE = 6.0    -- metres — interact with healing well
local BOSS_POS            = vec3:new(-5.1768, -3.9268, 2.0000)
local BOSS_PATHFIND_DIST  = 20.0   -- switch to pathfinder within this range (narrow path)

local NAV_SAMPLE_INTERVAL = 10.0   -- seconds between position snapshots
local NAV_STUCK_DIST      = 10.0   -- units — must have moved this far each interval or free-roam

-- Wall zone A: X=[0,82] Y=[95,120] — stuck around Y~97-107, move right to X=95
local WALLA_X_MIN      =  0.0
local WALLA_X_MAX      = 82.0
local WALLA_Y_MIN      = 95.0
local WALLA_Y_MAX      = 120.0
local WALLA_BYPASS_POS = vec3:new(95.0, 97.0, 0.0)

local function in_walla_zone(pos)
    local x, y = pos:x(), pos:y()
    return x >= WALLA_X_MIN and x <= WALLA_X_MAX
       and y >= WALLA_Y_MIN and y <= WALLA_Y_MAX
end

-- Wall zone B: X=[0,72] Y=[120,145] — stuck around Y~137, move right to X=73
local WALLB_X_MIN      =  0.0
local WALLB_X_MAX      = 72.0
local WALLB_Y_MIN      = 120.0
local WALLB_Y_MAX      = 145.0
local WALLB_BYPASS_POS = vec3:new(73.0527, 137.0479, -0.0723)

local function in_wallb_zone(pos)
    local x, y = pos:x(), pos:y()
    return x >= WALLB_X_MIN and x <= WALLB_X_MAX
       and y >= WALLB_Y_MIN and y <= WALLB_Y_MAX
end

-- Wall zone C: X=[80,100] Y=[65,88] — bot goes south into wall at Y~75, route west
local WALLC_X_MIN      = 80.0
local WALLC_X_MAX      = 100.0
local WALLC_Y_MIN      = 65.0
local WALLC_Y_MAX      = 88.0
local WALLC_BYPASS_POS = vec3:new(70.0, 80.0, 0.0)

local function in_wallc_zone(pos)
    local x, y = pos:x(), pos:y()
    return x >= WALLC_X_MIN and x <= WALLC_X_MAX
       and y >= WALLC_Y_MIN and y <= WALLC_Y_MAX
end

-- Wall zone D: X=[155,172] Y=[65,88] — stuck at Y~79, move to (173, 69)
local WALLD_X_MIN      = 155.0
local WALLD_X_MAX      = 172.0
local WALLD_Y_MIN      = 65.0
local WALLD_Y_MAX      = 88.0
local WALLD_BYPASS_POS = vec3:new(173.0840, 69.3125, 0.0410)

local function in_walld_zone(pos)
    local x, y = pos:x(), pos:y()
    return x >= WALLD_X_MIN and x <= WALLD_X_MAX
       and y >= WALLD_Y_MIN and y <= WALLD_Y_MAX
end

-- Second wall zone: X=[90,115] Y=[-5,25] — bot must move right to bypass
local WALL2_X_MIN      = 90.0
local WALL2_X_MAX      = 115.0
local WALL2_Y_MIN      = -5.0
local WALL2_Y_MAX      = 25.0
local WALL2_BYPASS_POS = vec3:new(105.4229, 48.9453, 9.4629)

local function in_wall2_zone(pos)
    local x, y = pos:x(), pos:y()
    return x >= WALL2_X_MIN and x <= WALL2_X_MAX
       and y >= WALL2_Y_MIN and y <= WALL2_Y_MAX
end

local task = {
    name                  = 'rush_to_boss',
    status                = 'idle',
    well_done        = false,
    explore_until    = -1,
    nav_sample_pos   = nil,
    nav_sample_time  = -1,
    free_roam_until  = -1,
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    task.well_done       = false
    task.explore_until   = -1
    task.nav_sample_pos  = nil
    task.nav_sample_time = -1
    task.free_roam_until = -1
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

-- Returns true if the well was found (caller should skip Batmobile exploration)
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
                return false  -- done, resume exploration
            else
                -- Pause Batmobile and beeline directly to the well
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

task.Execute = function()
    if BatmobilePlugin == nil then
        task.status = 'ERROR: BatmobilePlugin not loaded'
        return
    end

    local now = get_time_since_inject()

    if tracker.escape_until > 0 and now < tracker.escape_until then
        task.status = string.format('escape pause (%.1fs)', tracker.escape_until - now)
        BatmobilePlugin.pause(plugin_label)
        -- Schedule free exploration after this pause so we don't re-hit the same wall
        task.explore_until = tracker.escape_until + settings.roam_time
        return
    end

    -- After an escape pause, free-explore briefly to route around the obstacle
    if task.explore_until > 0 then
        if now < task.explore_until then
            task.status = string.format('routing around obstacle (%.1fs)', task.explore_until - now)
            BatmobilePlugin.resume(plugin_label)
            BatmobilePlugin.update(plugin_label)
            BatmobilePlugin.move(plugin_label)
            task.nav_sample_pos  = nil   -- reset so stuck check starts fresh after explore
            task.nav_sample_time = -1
            return
        end
        task.explore_until = -1
    end

    -- Free-roam unstick triggered by nav stuck detection
    if task.free_roam_until > 0 then
        if now < task.free_roam_until then
            task.status = string.format('free roam unstuck (%.1fs)', task.free_roam_until - now)
            BatmobilePlugin.resume(plugin_label)
            BatmobilePlugin.update(plugin_label)
            BatmobilePlugin.move(plugin_label)
            return
        end
        task.free_roam_until = -1
        task.nav_sample_pos  = nil
        task.nav_sample_time = -1
        console.print('[GemFarmer] Free roam done — resuming boss path')
    end

    if tracker.enter_time > 0 and (now - tracker.enter_time) < ENTRY_DELAY then
        task.status = 'waiting for dungeon load'
        return
    end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()

    -- Nav stuck detection: snapshot position every NAV_SAMPLE_INTERVAL seconds.
    -- If less than NAV_STUCK_DIST units moved since last snapshot → free-roam to unstick.
    if task.nav_sample_pos == nil then
        task.nav_sample_pos  = player_pos
        task.nav_sample_time = now
    elseif (now - task.nav_sample_time) >= NAV_SAMPLE_INTERVAL then
        local units_moved = player_pos:dist_to(task.nav_sample_pos)
        if units_moved < NAV_STUCK_DIST then
            console.print(string.format('[GemFarmer] Nav stuck (%.1f units in %.0fs) — free roaming', units_moved, NAV_SAMPLE_INTERVAL))
            task.free_roam_until = now + settings.roam_time
            task.nav_sample_pos  = nil
            task.nav_sample_time = -1
            BatmobilePlugin.resume(plugin_label)
            BatmobilePlugin.update(plugin_label)
            BatmobilePlugin.move(plugin_label)
            return
        end
        task.nav_sample_pos  = player_pos
        task.nav_sample_time = now
    end

    -- Boss check first
    local boss = find_boss(player_pos)
    if boss then
        tracker.boss_found    = true
        tracker.boss_last_pos = boss:get_position()
        BatmobilePlugin.pause(plugin_label)
        pathfinder.request_move(player_pos)  -- cancel any ongoing final-approach move
        console.print('[GemFarmer] Boss detected — handing off to fight task')
        return
    end

    -- Healing well — beeline if spotted, otherwise drive to boss coords
    if try_interact_well(player_pos) then return end

    if settings.wall_detours then
        if in_walla_zone(player_pos) then
            BatmobilePlugin.pause(plugin_label)
            task.status = string.format('detouring wall A (%.1fm)', player_pos:dist_to(WALLA_BYPASS_POS))
            pathfinder.request_move(WALLA_BYPASS_POS)
            return
        end
        if in_wallb_zone(player_pos) then
            BatmobilePlugin.pause(plugin_label)
            task.status = string.format('detouring wall B (%.1fm)', player_pos:dist_to(WALLB_BYPASS_POS))
            pathfinder.request_move(WALLB_BYPASS_POS)
            return
        end
        if in_wallc_zone(player_pos) then
            BatmobilePlugin.pause(plugin_label)
            task.status = string.format('detouring wall C (%.1fm)', player_pos:dist_to(WALLC_BYPASS_POS))
            pathfinder.request_move(WALLC_BYPASS_POS)
            return
        end
        if in_walld_zone(player_pos) then
            BatmobilePlugin.pause(plugin_label)
            task.status = string.format('detouring wall D (%.1fm)', player_pos:dist_to(WALLD_BYPASS_POS))
            pathfinder.request_move(WALLD_BYPASS_POS)
            return
        end
        if in_wall2_zone(player_pos) then
            BatmobilePlugin.pause(plugin_label)
            task.status = string.format('detouring wall2 (%.1fm)', player_pos:dist_to(WALL2_BYPASS_POS))
            pathfinder.request_move(WALL2_BYPASS_POS)
            return
        end
    end

    local boss_dist = player_pos:dist_to(BOSS_POS)
    if boss_dist <= BOSS_PATHFIND_DIST then
        BatmobilePlugin.pause(plugin_label)
        -- Arrived at boss area — force handoff to fight task
        if boss_dist <= 8.0 then
            tracker.boss_found    = true
            tracker.boss_last_pos = BOSS_POS
            pathfinder.request_move(player_pos)
            console.print('[GemFarmer] Arrived at boss area — forcing fight handoff')
            return
        end
        task.status = string.format('final approach to boss (%.1fm)', boss_dist)
        pathfinder.request_move(BOSS_POS)
    else
        -- Longer stretch — Batmobile drives
        task.status = string.format('heading to boss (%.1fm)', boss_dist)
        BatmobilePlugin.set_target(plugin_label, BOSS_POS, false)
        BatmobilePlugin.resume(plugin_label)
        BatmobilePlugin.update(plugin_label)
        BatmobilePlugin.move(plugin_label)
    end
end

return task
