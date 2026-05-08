local tracker = require 'core.tracker'
local world   = require 'core.world'

local TEMIS_WAYPOINT    = 0x1CE51E  -- Temis waypoint SNO
local WAYPOINT_SPELL_ID = 186139    -- active spell ID while waypoint is channelling
local MAP_KEY           = 0x4D      -- 'M' — opens world map
local MAP_OPEN_WAIT     = 1.0       -- seconds to wait for map to open
local TELEPORT_DEBOUNCE = 3.0       -- seconds between teleport_to_waypoint calls
local LOAD_WAIT         = 10.0      -- seconds to wait for zone transition

-- States: 'idle' → 'open_map' → 'teleporting'
local state        = 'idle'
local state_time   = -1
local last_tp_call = -1

local task = {
    name   = 'teleport_to_dungeon',
    status = 'idle',
}

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    state                   = 'idle'
    state_time              = -1
    last_tp_call            = -1
    tracker.temis_confirmed = false
end

task.shouldExecute = function()
    if tracker.boss_dead then return false end
    if world.is_inside() then return false end
    if tracker.temis_confirmed then return false end
    return true
end

task.Execute = function()
    local now = get_time_since_inject()

    -- Landed — confirm and stop
    if world.is_outside() and state == 'teleporting' then
        tracker.temis_confirmed = true
        state = 'idle'
        console.print('[GemFarmer] Confirmed at Temis — handing off to walk task')
        return
    end

    if state == 'idle' then
        task.status = 'opening map'
        if utility and type(utility.send_key_press) == 'function' then
            utility.send_key_press(MAP_KEY)
        end
        state      = 'open_map'
        state_time = now
        console.print('[GemFarmer] Opening world map before teleport')

    elseif state == 'open_map' then
        if (now - state_time) >= MAP_OPEN_WAIT then
            task.status  = 'teleporting to Temis'
            state        = 'teleporting'
            state_time   = now
            last_tp_call = now
            teleport_to_waypoint(TEMIS_WAYPOINT)
            console.print('[GemFarmer] Teleporting to Temis waypoint')
        else
            task.status = string.format('waiting for map (%.1fs)', MAP_OPEN_WAIT - (now - state_time))
        end

    elseif state == 'teleporting' then
        local player      = get_local_player()
        local channelling = player and player:get_active_spell_id() == WAYPOINT_SPELL_ID

        if channelling then
            task.status = 'channelling waypoint...'
        elseif (now - state_time) >= LOAD_WAIT then
            -- Timed out — restart from map open
            console.print('[GemFarmer] Teleport timed out — retrying')
            state      = 'idle'
            state_time = now
        elseif (now - last_tp_call) >= TELEPORT_DEBOUNCE then
            last_tp_call = now
            teleport_to_waypoint(TEMIS_WAYPOINT)
            task.status = 'retrying teleport call'
        else
            task.status = string.format('waiting for zone (%.0fs)', LOAD_WAIT - (now - state_time))
        end
    end
end

return task
