local settings     = require 'core.settings'
local tracker      = require 'core.tracker'
local world        = require 'core.world'

local plugin_label = 'gem_farmer'

local ENTRY_DELAY         = 2.0    -- seconds after entering before starting navigation
local WELL_INTERACT_RANGE = 6.0    -- metres — interact with healing well
local BOSS_POS            = vec3:new(5.0742, 6.3398, 1.9697)
local EXPLORE_AFTER_STUCK = 8.0    -- seconds of free exploration after each escape pause

local task = {
    name          = 'rush_to_boss',
    status        = 'idle',
    well_done     = false,
    explore_until = -1,
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    task.well_done     = false
    task.explore_until = -1
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
        task.explore_until = tracker.escape_until + EXPLORE_AFTER_STUCK
        return
    end

    -- After an escape pause, free-explore briefly to route around the obstacle
    if task.explore_until > 0 then
        if now < task.explore_until then
            task.status = string.format('routing around obstacle (%.1fs)', task.explore_until - now)
            BatmobilePlugin.resume(plugin_label)
            BatmobilePlugin.update(plugin_label)
            BatmobilePlugin.move(plugin_label)
            return
        end
        task.explore_until = -1
    end

    if tracker.enter_time > 0 and (now - tracker.enter_time) < ENTRY_DELAY then
        task.status = 'waiting for dungeon load'
        return
    end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()

    -- Boss check first
    local boss = find_boss(player_pos)
    if boss then
        tracker.boss_found    = true
        tracker.boss_last_pos = boss:get_position()
        BatmobilePlugin.pause(plugin_label)
        console.print('[GemFarmer] Boss detected — handing off to fight task')
        return
    end

    -- Healing well — beeline if spotted, otherwise drive to boss coords
    if try_interact_well(player_pos) then return end

    -- Batmobile set_target drives toward boss position with wall avoidance
    task.status = string.format('heading to boss (%.1fm)', player_pos:dist_to(BOSS_POS))
    BatmobilePlugin.set_target(plugin_label, BOSS_POS, false)
    BatmobilePlugin.resume(plugin_label)
    BatmobilePlugin.update(plugin_label)
    BatmobilePlugin.move(plugin_label)
end

return task
