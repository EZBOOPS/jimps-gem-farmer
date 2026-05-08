local settings = require 'core.settings'
local tracker  = require 'core.tracker'
local world    = require 'core.world'
local stats    = require 'core.stats'

local BOSS_TIMEOUT = 300.0  -- 5 minutes to find the boss before abandoning the run

local task = {
    name   = 'boss_timeout',
    status = 'idle',
}

task.shouldExecute = function()
    if not world.is_inside() then return false end
    if tracker.boss_found or tracker.boss_dead then return false end
    if tracker.enter_time < 0 then return false end
    return (get_time_since_inject() - tracker.enter_time) >= BOSS_TIMEOUT
end

task.Execute = function()
    local elapsed = get_time_since_inject() - tracker.enter_time
    task.status = string.format('timed out (%.0fs) — abandoning run', elapsed)
    console.print(string.format('[GemFarmer] Boss not found after %.0fs — abandoning run', elapsed))

    -- Trigger the normal exit pipeline by marking the run as done
    stats.record_abandon()
    tracker.boss_dead       = true
    tracker.loot_start_time = get_time_since_inject() - settings.loot_wait - 1
end

return task
