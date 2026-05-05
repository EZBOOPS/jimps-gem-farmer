local settings = require 'core.settings'
local tracker  = require 'core.tracker'
local world    = require 'core.world'

local RETRY_INTERVAL = 2.0  -- seconds between reset_all_dungeons() retries
local MAX_RETRIES    = 1

local task = {
    name        = 'reset_dungeon',
    status      = 'idle',
    retries     = 0,
    retry_time  = -1,
}

task.shouldExecute = function()
    if not world.is_outside() then return false end
    if not tracker.boss_dead then return false end

    -- Wait for Alfred to finish inventory management before resetting
    if AlfredTheButlerPlugin then
        local status = AlfredTheButlerPlugin.get_status()
        if status and (status.need_trigger or status.inventory_full or status.need_repair) then
            return false
        end
    end

    return true
end

task.Execute = function()
    local now = get_time_since_inject()

    -- First call or retry: fire reset_all_dungeons()
    if tracker.reset_time < 0 then
        task.retries   = task.retries + 1
        tracker.reset_time = now
        task.retry_time    = -1
        reset_all_dungeons()
        task.status = string.format('resetting dungeon (attempt %d/%d)', task.retries, MAX_RETRIES)
        console.print(string.format('[GemFarmer] reset_all_dungeons() attempt %d/%d', task.retries, MAX_RETRIES))
        return
    end

    -- Waiting between retry calls
    if task.retry_time > 0 then
        if (now - task.retry_time) >= RETRY_INTERVAL then
            tracker.reset_time = -1  -- triggers another reset call next tick
        else
            task.status = string.format('waiting to retry reset (%.1fs)', now - task.retry_time)
        end
        return
    end

    local elapsed = now - tracker.reset_time
    task.status = string.format('waiting after reset (%.1fs / %ds)', elapsed, settings.reset_wait)

    if elapsed >= settings.reset_wait then
        if task.retries < MAX_RETRIES then
            -- Fire another reset to make sure it took
            console.print(string.format('[GemFarmer] Firing extra reset %d/%d', task.retries + 1, MAX_RETRIES))
            task.retry_time    = now
            tracker.reset_time = -1
        else
            -- All retries done — move to next run
            task.retries = 0
            tracker.reset_run()
            console.print('[GemFarmer] Reset complete — starting next run')
        end
    end
end

return task
