local settings = require 'core.settings'
local tracker  = require 'core.tracker'
local world    = require 'core.world'

-- No-progress stuck detection — thresholds read from settings each tick
local MOVE_THRESHOLD     = 2.0   -- metres — minimum movement to not be "stuck"
local UNSTICK_COOLDOWN   = 10.0  -- minimum seconds between unstick attempts

-- Wall-oscillation detection (player moves a lot but goes nowhere)
local OSC_SAMPLE_RATE    = 0.20  -- seconds between position samples
local OSC_WINDOW         = 5.0   -- seconds of history to analyse
local OSC_TOTAL_MIN      = 10.0  -- min total distance moved to be considered "active"
local OSC_NET_MAX        = 1.0   -- max net displacement to be considered "oscillating"
local OSC_COOLDOWN       = 15.0  -- minimum seconds between oscillation fixes

local PLUGIN_LABEL = 'gem_farmer'

-- No-progress state
local last_pos          = nil
local last_move_time    = -1
local last_unstick_time = -1

-- Oscillation state
local osc_history       = {}   -- {t, pos} samples
local last_sample_time  = -1
local last_osc_fix_time = -1

local function reset()
    last_pos          = nil
    last_move_time    = -1
    last_unstick_time = -1
    osc_history       = {}
    last_sample_time  = -1
    last_osc_fix_time = -1
end

local function do_unstick(now, reason)
    console.print(string.format('[GemFarmer] Wall unstick: %s — pausing nav for 3s', reason))
    tracker.healing_well_pos = nil
    tracker.escape_until     = now + 3.0
    if BatmobilePlugin then
        BatmobilePlugin.clear_target(PLUGIN_LABEL)
        BatmobilePlugin.pause(PLUGIN_LABEL)
    end
    last_unstick_time = now
    last_osc_fix_time = now
    -- Reset oscillation history so we don't re-trigger immediately
    osc_history      = {}
    last_sample_time = -1
end

local function check_oscillation(now, player_pos)
    -- Sample position at OSC_SAMPLE_RATE
    if last_sample_time >= 0 and (now - last_sample_time) < OSC_SAMPLE_RATE then return end
    last_sample_time = now

    -- Add sample and prune old entries
    osc_history[#osc_history + 1] = { t = now, pos = player_pos }
    local cutoff = now - OSC_WINDOW
    local keep = 1
    while keep <= #osc_history and osc_history[keep].t < cutoff do keep = keep + 1 end
    if keep > 1 then
        local trimmed = {}
        for i = keep, #osc_history do trimmed[#trimmed + 1] = osc_history[i] end
        osc_history = trimmed
    end

    -- Need at least OSC_WINDOW seconds of data
    if #osc_history < 2 then return end
    if (now - osc_history[1].t) < OSC_WINDOW then return end

    -- Compute total path length and net displacement
    local total = 0
    for i = 2, #osc_history do
        total = total + osc_history[i].pos:dist_to(osc_history[i - 1].pos)
    end
    local net = osc_history[#osc_history].pos:dist_to(osc_history[1].pos)

    if total >= OSC_TOTAL_MIN and net <= OSC_NET_MAX then
        local since_last = (last_osc_fix_time < 0) and OSC_COOLDOWN or (now - last_osc_fix_time)
        if since_last >= OSC_COOLDOWN then
            do_unstick(now, string.format('oscillating (moved %.1fm, net %.2fm)', total, net))
        end
    end
end

-- Hook into tracker.reset_run so state clears between runs
local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    reset()
end

local stuck_timeout = {}

stuck_timeout.update = function()
    -- Only monitor while inside, exploring, and not already done
    if not world.is_inside() then reset() return end
    if tracker.boss_found or tracker.boss_dead then reset() return end
    -- Don't fire while we're already in an escape pause
    if tracker.escape_until > 0 and get_time_since_inject() < tracker.escape_until then return end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()
    local now        = get_time_since_inject()

    -- Wall-oscillation check (runs every tick, samples internally at OSC_SAMPLE_RATE)
    check_oscillation(now, player_pos)

    -- No-progress stuck check
    if last_pos == nil or last_move_time < 0 then
        last_pos       = player_pos
        last_move_time = now
        return
    end

    if player_pos:dist_to(last_pos) >= MOVE_THRESHOLD then
        last_pos       = player_pos
        last_move_time = now
        return
    end

    local stuck_for = now - last_move_time

    -- Hard abandon
    if stuck_for >= settings.hard_reset then
        console.print(string.format('[GemFarmer] Stuck for %.0fs — abandoning run', stuck_for))
        reset()
        tracker.boss_dead       = true
        tracker.loot_start_time = get_time_since_inject() - settings.loot_wait - 1
        return
    end

    -- Soft unstick (no progress at all)
    if stuck_for >= settings.soft_reset then
        local since_last = (last_unstick_time < 0) and UNSTICK_COOLDOWN or (now - last_unstick_time)
        if since_last >= UNSTICK_COOLDOWN then
            do_unstick(now, string.format('no progress for %.0fs', stuck_for))
        end
    end
end

return stuck_timeout
