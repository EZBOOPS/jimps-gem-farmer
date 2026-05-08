local gui          = require 'gui'
local settings     = require 'core.settings'
local task_manager = require 'core.task_manager'
local tracker      = require 'core.tracker'

local external = {}

external.enable = function()
    gui.elements.main_toggle:set(true)
    gui.elements.keybind_toggle:set(true)
    settings:update_settings()
end

external.disable = function()
    gui.elements.main_toggle:set(false)
    gui.elements.keybind_toggle:set(false)
    settings:update_settings()
end

external.status = function()
    local task = task_manager.get_current_task()
    return {
        enabled = settings.enabled and settings.get_keybind_state(),
        task    = task and task.name or 'Idle',
        status  = task and task.status or 'idle',
        inside  = tracker.inside_dungeon,
        boss_dead = tracker.boss_dead,
    }
end

return external
