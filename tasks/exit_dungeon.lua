local settings = require 'core.settings'
local tracker  = require 'core.tracker'
local world    = require 'core.world'

local RETRY_INTERVAL = 5.0

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

local task = {
    name       = 'exit_dungeon',
    status     = 'idle',
    leave_time = -1,
    retries    = 0,
}

task.shouldExecute = function()
    if not world.is_inside() then return false end
    if not tracker.boss_dead then return false end
    if tracker.loot_start_time < 0 then return false end
    local elapsed = get_time_since_inject() - tracker.loot_start_time
    return elapsed >= settings.loot_wait
end

task.Execute = function()
    -- Always ensure UR is fully free during exit phase
    ur_free()

    local now     = get_time_since_inject()
    local elapsed = task.leave_time >= 0 and (now - task.leave_time) or RETRY_INTERVAL

    if elapsed >= RETRY_INTERVAL then
        task.retries    = task.retries + 1
        task.leave_time = now
        leave_dungeon()
        task.status = string.format('leaving dungeon (attempt %d)', task.retries)
        console.print(string.format('[GemFarmer] leave_dungeon() attempt %d', task.retries))
        return
    end

    task.status = string.format('waiting for zone transition (%.1fs / %.1fs)', elapsed, RETRY_INTERVAL)
end

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    ur_free()
    task.leave_time = -1
    task.retries    = 0
end

return task
