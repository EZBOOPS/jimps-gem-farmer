local gui          = require 'gui'
local settings     = require 'core.settings'
local task_manager = require 'core.task_manager'
local tracker      = require 'core.tracker'
local external     = require 'core.external'
local stuck        = require 'tasks.stuck_timeout'
local world        = require 'core.world'

local BOSS_POS = vec3:new(-5.1768, -3.9268, 2.0000)
local dbg_last_print = -1

local local_player

local function update_locals()
    local_player = get_local_player()
end

local function main_pulse()
    settings:update_settings()
    if not local_player then return end
    if not settings.enabled or not settings.get_keybind_state() then return end

    if local_player:is_dead() then
        revive_at_checkpoint()
        return
    end

    stuck.update()
    task_manager.execute_tasks()
end

local function render_pulse()
    if not local_player or not settings.enabled or not settings.get_keybind_state() then return end

    if settings.show_boss and tracker.boss_last_pos then
        graphics.circle_3d(tracker.boss_last_pos, 2.0, color_red(200))
        graphics.text_3d('BOSS', tracker.boss_last_pos, 16, color_red(255))
    end

    local task = task_manager.get_current_task()
    if task then
        local msg = 'Gem Farmer: ' .. task.name
        if task.status and task.status ~= '' then
            msg = msg .. ' (' .. task.status .. ')'
        end
        local x = get_screen_width() / 2 - (#msg * 5.5)
        graphics.text_2d(msg, vec2:new(x, 80), 20, color_white(255))
    end

    if gui.elements.dbg_coords:get() and world.is_inside() then
        local pos = local_player:get_position()
        local px, py, pz = pos:x(), pos:y(), pos:z()
        local dx = BOSS_POS:x() - px
        local dy = BOSS_POS:y() - py
        local dist = math.sqrt(dx * dx + dy * dy)
        local now = get_time_since_inject()
        local lines = {
            string.format('X: %.2f', px),
            string.format('Y: %.2f', py),
            string.format('Z: %.2f', pz),
            string.format('Boss dX: %+.1f', dx),
            string.format('Boss dY: %+.1f', dy),
            string.format('Boss dist: %.1fm', dist),
        }
        local sw = get_screen_width()
        for i, line in ipairs(lines) do
            graphics.text_2d(line, vec2:new(sw - 180, 100 + (i - 1) * 22), 18, color_white(255))
        end
        -- Also print to console once per second
        if (now - dbg_last_print) >= 1.0 then
            dbg_last_print = now
            console.print(string.format('[GemFarmer] pos=(%.2f, %.2f, %.2f)  boss_dX=%+.1f  boss_dY=%+.1f  dist=%.1f',
                px, py, pz, dx, dy, dist))
        end
    end
end

on_update(function()
    update_locals()
    main_pulse()
end)

on_render_menu(function()
    gui.render()

    if gui.pending_zone then
        gui.pending_zone = false
        local w = world.get_current_world()
        if w then
            console.print('[GemFarmer] Zone: '     .. tostring(w:get_current_zone_name()))
            console.print('[GemFarmer] World: '    .. tostring(w:get_name()))
            console.print('[GemFarmer] World ID: ' .. tostring(w:get_world_id()))
        else
            console.print('[GemFarmer] world.get_current_world() returned nil')
        end
    end

    if gui.pending_pos then
        gui.pending_pos = false
        local p = get_local_player()
        if p then
            local pos = p:get_position()
            console.print(string.format('[GemFarmer] Position: vec3:new(%.4f, %.4f, %.4f)', pos:x(), pos:y(), pos:z()))
        else
            console.print('[GemFarmer] get_local_player() returned nil')
        end
    end

    if gui.pending_interactables then
        gui.pending_interactables = false
        local p = get_local_player()
        if p then
            local player_pos = p:get_position()
            local count = 0
            for _, actor in ipairs(actors_manager.get_all_actors()) do
                if loot_manager.is_interactable_object(actor) then
                    local dist = actor:get_position():dist_to(player_pos)
                    if dist <= 30.0 then
                        local name = actor:get_skin_name() or '(nil)'
                        console.print(string.format('[GemFarmer] Interactable: "%s" %.1fm', name, dist))
                        count = count + 1
                    end
                end
            end
            if count == 0 then
                console.print('[GemFarmer] No interactable actors within 30m')
            end
        else
            console.print('[GemFarmer] get_local_player() returned nil')
        end
    end
end)

on_render(render_pulse)

GemFarmerPlugin = external
