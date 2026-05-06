local tracker = require 'core.tracker'
local world   = require 'core.world'

local plugin_label = 'gem_farmer'

local status_enum = {
    IDLE    = 'idle',
    WAITING = 'waiting for alfred to finish',
}

local task = {
    name   = 'alfred',
    status = status_enum.IDLE,
}

local function alfred_plugin()
    return _G.AlfredTheButlerPlugin or _G.PLUGIN_alfred_the_butler
end

local function reset()
    local a = alfred_plugin()
    if a then a.pause(plugin_label) end
    task.status = status_enum.IDLE
    console.print('[GemFarmer] Alfred finished — resuming farming')
end

local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    if task.status == status_enum.WAITING then
        local a = alfred_plugin()
        if a then a.pause(plugin_label) end
        task.status = status_enum.IDLE
    end
end

task.shouldExecute = function()
    if task.status == status_enum.WAITING then return true end
    if not world.is_outside() then return false end
    local a = alfred_plugin()
    if not a then return false end
    local st = a.get_status()
    if not st or not st.enabled then return false end
    return st.need_trigger or st.inventory_full or st.need_repair
end

task.Execute = function()
    if task.status == status_enum.IDLE then
        local a = alfred_plugin()
        if a then
            a.resume()
            a.trigger_tasks_with_teleport(plugin_label, reset)
        end
        task.status = status_enum.WAITING
        console.print('[GemFarmer] Yielding to Alfred for inventory management')
    end
end

-- Clear any stale paused state from a prior session
local _a = alfred_plugin()
if _a then _a.pause(plugin_label) end

return task
