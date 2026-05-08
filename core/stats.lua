local stats = {
    runs_completed  = 0,
    runs_abandoned  = 0,
    resets          = 0,
    session_start   = -1,
    total_run_time  = 0,
    last_run_time   = 0,
}

local function ensure_start()
    if stats.session_start < 0 then
        stats.session_start = get_time_since_inject()
    end
end

stats.record_kill = function(enter_time)
    ensure_start()
    stats.runs_completed = stats.runs_completed + 1
    if enter_time and enter_time >= 0 then
        local dur = get_time_since_inject() - enter_time
        stats.last_run_time  = dur
        stats.total_run_time = stats.total_run_time + dur
    end
end

stats.record_abandon = function()
    ensure_start()
    stats.runs_abandoned = stats.runs_abandoned + 1
end

stats.record_reset = function()
    ensure_start()
    stats.resets = stats.resets + 1
end

stats.runs_per_hour = function()
    if stats.session_start < 0 or stats.runs_completed == 0 then return 0 end
    local hrs = (get_time_since_inject() - stats.session_start) / 3600.0
    if hrs < 0.001 then return 0 end
    return stats.runs_completed / hrs
end

stats.avg_run_time = function()
    if stats.runs_completed == 0 then return 0 end
    return stats.total_run_time / stats.runs_completed
end

stats.session_elapsed = function()
    if stats.session_start < 0 then return 0 end
    return get_time_since_inject() - stats.session_start
end

local function fmt_time(secs)
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    return string.format('%dm %02ds', m, s)
end
stats.fmt_time = fmt_time

stats.render = function()
    local x, y, lh, sz = 10, 10, 16, 13
    local function line(text, col)
        graphics.text_2d(text, vec2:new(x, y), sz, col or color_white(200))
        y = y + lh
    end

    line('[ Gem Farmer Stats ]', color_yellow(255))
    line(string.format('Session:   %s',  fmt_time(stats.session_elapsed())), color_white(180))
    line(string.format('Completed: %d',  stats.runs_completed), color_green(220))
    line(string.format('Abandoned: %d',  stats.runs_abandoned), color_red(200))
    line(string.format('Resets:    %d',  stats.resets), color_white(180))
    line(string.format('Runs/hr:   %.1f', stats.runs_per_hour()), color_yellow(220))
    if stats.runs_completed > 0 then
        line(string.format('Avg time:  %s', fmt_time(stats.avg_run_time())), color_white(180))
        line(string.format('Last run:  %s', fmt_time(stats.last_run_time)), color_white(150))
    end
end

return stats
