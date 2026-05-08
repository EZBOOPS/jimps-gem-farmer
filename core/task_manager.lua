local task_manager = {}

local tasks       = {}
local last_tick   = -1
local tick_rate   = 0.05   -- max 20 executions per second
local current_task = { name = 'Idle', status = 'idle' }

task_manager.register_task = function(task)
    table.insert(tasks, task)
end

task_manager.execute_tasks = function()
    local now = get_time_since_inject()
    if now - last_tick < tick_rate then return end
    last_tick = now

    for _, task in ipairs(tasks) do
        if task.shouldExecute() then
            current_task = task
            task:Execute()
            return
        end
    end
    current_task = { name = 'Idle', status = 'idle' }
end

task_manager.get_current_task = function()
    return current_task
end

-- Load tasks in priority order (first = highest priority)
local task_files = {
    'exit_dungeon',
    'alfred',              -- run before reset so inventory is managed first
    'reset_dungeon',
    'boss_timeout',
    'teleport_to_dungeon', -- teleport to Temis if far from dungeon or in wrong world
    'walk_to_dungeon',     -- follow waypoints from Temis to dungeon entrance
    'enter_dungeon',
    'rush_to_boss',
    'fight_boss',
    'idle',
}

for _, name in ipairs(task_files) do
    local task = require('tasks.' .. name)
    task_manager.register_task(task)
end

return task_manager
