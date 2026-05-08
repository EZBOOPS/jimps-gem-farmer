local gui = require 'gui'

local recorder = {
    buffers       = { {} },
    last_pos      = nil,
    was_recording = false,
}

local function is_recording()
    return gui.elements.rec_toggle:get()
end

local function save_to_file()
    local buf = recorder.buffers[1]

    console.print('[GemFarmer] Recorder: stopping. Buffer has ' .. #buf .. ' points.')

    if #buf == 0 then
        console.print('[GemFarmer] Recorder: nothing to save — no points were captured.')
        console.print('[GemFarmer] Tip: make sure you walk while recording is active.')
        return
    end

    -- Build file content as a string first
    local lines = {}
    table.insert(lines, '-- Auto-saved by Gem Farmer recorder')
    table.insert(lines, 'local path = {')
    for _, p in ipairs(buf) do
        table.insert(lines, string.format('    vec3:new(%.4f, %.4f, %.4f),', p:x(), p:y(), p:z()))
    end
    table.insert(lines, '}')
    table.insert(lines, 'return path')
    local content = table.concat(lines, '\n') .. '\n'

    -- Write using Alfred's exact pattern
    local ok, err = pcall(function()
        local file, open_err = io.open('paths/approach.lua', 'w')
        if not file then
            error('io.open failed: ' .. tostring(open_err))
        end
        file:write(content)
        file:close()
    end)

    if not ok then
        console.print('[GemFarmer] ERROR writing file: ' .. tostring(err))
        console.print('[GemFarmer] Printing path to console as fallback:')
        console.print(content)
        return
    end

    console.print(string.format('[GemFarmer] Saved %d waypoints to paths/approach.lua', #buf))

    -- Reload in memory so the bot can use it immediately without restarting
    local reload_ok, reload_err = pcall(function()
        package.loaded['paths.approach'] = nil
        local new_path = require 'paths.approach'
        local paths = require 'core.paths'
        paths.approach = new_path
    end)

    if reload_ok then
        console.print('[GemFarmer] Approach path reloaded in memory — ready to use.')
    else
        console.print('[GemFarmer] Saved OK but reload failed: ' .. tostring(reload_err))
        console.print('[GemFarmer] Restart scripts to apply the new path.')
    end
end

recorder.update = function()
    local recording = is_recording()

    -- Detect transition: was recording, now stopped → save
    if recorder.was_recording and not recording then
        save_to_file()
    end
    recorder.was_recording = recording

    if not recording then
        recorder.last_pos = nil
        return
    end

    local player = get_local_player()
    if not player then return end
    local pos = player:get_position()
    if not pos then return end

    local min_dist = gui.elements.rec_interval:get()
    if recorder.last_pos == nil or pos:dist_to(recorder.last_pos) >= min_dist then
        recorder.last_pos = pos
        table.insert(recorder.buffers[1], vec3:new(pos:x(), pos:y(), pos:z()))
    end
end

recorder.clear_path = function()
    recorder.buffers[1] = {}
    recorder.last_pos = nil
    console.print('[GemFarmer] Recording buffer cleared.')
end

recorder.get_point_count = function()
    return #recorder.buffers[1]
end

recorder.render = function()
    -- Live recording HUD: show point count while recording
    if is_recording() then
        local count = #recorder.buffers[1]
        local msg = 'Recording: ' .. count .. ' points captured'
        graphics.text_2d(msg, vec2:new(10, 110), 18, color_yellow(255))
    end

    if not gui.elements.show_path:get() then return end

    local ok, paths = pcall(require, 'core.paths')
    if not ok or not paths then return end

    for i, p in ipairs(paths.approach) do
        graphics.circle_3d(p, 0.6, color_cyan(200))
        if i < #paths.approach then
            graphics.line(p, paths.approach[i + 1], color_cyan(120), 1)
        end
    end

    -- Live buffer in yellow
    local buf = recorder.buffers[1]
    for i, p in ipairs(buf) do
        graphics.circle_3d(p, 0.4, color_yellow(200))
        if i < #buf then
            graphics.line(p, buf[i + 1], color_yellow(120), 1)
        end
    end
end

return recorder
