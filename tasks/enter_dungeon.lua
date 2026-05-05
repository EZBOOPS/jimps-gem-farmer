local settings  = require 'core.settings'
local tracker   = require 'core.tracker'
local world     = require 'core.world'

local plugin_label   = 'gem_farmer'
local SEARCH_RANGE   = 60.0   -- wider net — player may be placed away from door after reset
local CHECK_INTERVAL = 0.5    -- seconds between world ID checks after interacting
local ENTER_TIMEOUT  = 10.0   -- seconds before retrying the interaction

local ready_time = -1   -- when we're allowed to start entering (after enter_wait)

-- Hook reset_run to clear our local state
local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    ready_time = -1
end

local task = {
    name   = 'enter_dungeon',
    status = 'idle',
}

local function find_dungeon_entrance(player_pos)
    local best, best_d, best_name = nil, SEARCH_RANGE, ''
    for _, actor in ipairs(actors_manager.get_all_actors()) do
        if loot_manager.is_interactable_object(actor) then
            local d = actor:get_position():dist_to(player_pos)
            if d < best_d then
                best, best_d = actor, d
                best_name = actor:get_skin_name() or '?'
            end
        end
    end
    if best then
        console.print(string.format('[GemFarmer] Entrance candidate: "%s" (%.1fm)', best_name, best_d))
    end
    return best
end

task.shouldExecute = function()
    if not world.is_outside() then return false end
    if tracker.boss_dead then return false end

    -- Wait for Alfred to finish inventory management before entering
    if AlfredTheButlerPlugin then
        local status = AlfredTheButlerPlugin.get_status()
        if status and (status.need_trigger or status.inventory_full or status.need_repair) then
            return false
        end
    end

    return true
end

task.Execute = function()
    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()
    local now = get_time_since_inject()

    -- Wait enter_wait seconds after dungeon reset before trying to enter
    if ready_time < 0 then
        ready_time = now + settings.enter_wait
        task.status = string.format('waiting before entering (%.0fs)', settings.enter_wait)
        console.print(string.format('[GemFarmer] enter_dungeon: waiting %.0fs before entering', settings.enter_wait))
        return
    end
    if now < ready_time then
        task.status = string.format('waiting before entering (%.1fs)', ready_time - now)
        return
    end

    -- Waiting for zone transition into dungeon
    if tracker.interact_time > 0 then
        local elapsed = now - tracker.interact_time

        if world.is_inside() then
            tracker.interact_time         = -1
            tracker.last_interact_attempt = nil
            tracker.enter_time            = get_time_since_inject()
            if BatmobilePlugin then BatmobilePlugin.reset(plugin_label) end
            console.print('[GemFarmer] Entered dungeon — starting exploration')
            return
        end

        -- Only re-check every CHECK_INTERVAL seconds
        local last_check = tracker.last_interact_attempt or tracker.interact_time
        if (now - last_check) < CHECK_INTERVAL then
            task.status = string.format('waiting for zone transition (%.1fs)', elapsed)
            return
        end
        tracker.last_interact_attempt = now

        if elapsed >= ENTER_TIMEOUT then
            tracker.interact_time         = -1
            tracker.last_interact_attempt = nil
            console.print('[GemFarmer] Enter timed out — retrying')
        else
            task.status = string.format('waiting for zone transition (%.1fs / %.0fs)', elapsed, ENTER_TIMEOUT)
        end
        return
    end

    local door = find_dungeon_entrance(player_pos)
    if door then
        local dist = player_pos:dist_to(door:get_position())
        task.status = string.format('found entrance (%.1fm)', dist)
        if dist > 3.0 then
            pathfinder.request_move(door:get_position())
        else
            local cooldown_ok = tracker.last_interact_attempt == nil or
                                (now - tracker.last_interact_attempt) >= tracker.interact_cooldown
            if cooldown_ok then
                task.status = 'interacting with entrance'
                tracker.last_interact_attempt = now
                interact_object(door)
                tracker.interact_time = now
                console.print('[GemFarmer] Interacting with dungeon entrance')
            end
        end
    else
        task.status = string.format('no entrance within %.0fm — move closer', SEARCH_RANGE)
        console.print(string.format('[GemFarmer] enter_dungeon: no interactable found within %.0fm', SEARCH_RANGE))
    end
end

return task
