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

-- Boss progress detection — abandon if not getting closer to boss
local BOSS_POS               = vec3:new(-5.1768, -3.9268, 2.0000)
local BOSS_PROGRESS_INTERVAL = 15.0  -- check every 15 seconds
local BOSS_PROGRESS_MIN      = 5.0   -- must get at least 5m closer
local BOSS_MAX_NO_PROGRESS   = 90.0  -- abandon after 90s of no progress toward boss

-- Wall-slide: when stuck, move perpendicular to the boss direction to follow the
-- wall contour until a clear path opens up. Each tick we re-project the slide
-- target from the player's current position so the bot naturally arcs around
-- corners. SLIDE_DIST is how far ahead to aim; SLIDE_DURATION caps how long we
-- slide before giving up and letting the boss-progress guard handle abandonment.
local SLIDE_DIST     = 12.0  -- units ahead along the slide direction
local SLIDE_DURATION = 8.0   -- seconds to slide before reverting to normal nav

-- No-progress state
local last_pos          = nil
local last_move_time    = -1
local last_unstick_time = -1

-- Oscillation state
local osc_history       = {}   -- {t, pos} samples
local last_sample_time  = -1
local last_osc_fix_time = -1

-- Boss progress state
local boss_check_time        = -1
local boss_best_dist         = 9999
local boss_no_progress_since = -1

local function reset()
    last_pos          = nil
    last_move_time    = -1
    last_unstick_time = -1
    osc_history       = {}
    last_sample_time  = -1
    last_osc_fix_time = -1
    boss_check_time        = -1
    boss_best_dist         = 9999
    boss_no_progress_since = -1
end

-- ── Wall-slide state (read by rush_to_boss) ─────────────────────────────────
-- slide_until > 0 means a slide is active. slide_dir is +1 (left perp) or -1
-- (right perp), chosen once when the slide starts and held for the whole slide
-- so we don't oscillate between sides.
local stuck_timeout = {}
stuck_timeout.slide_until = -1   -- wall-slide active while now < slide_until
stuck_timeout.slide_dir   = 1    -- +1 = left perp, -1 = right perp

-- Compute the wall-slide target for this tick. Called every tick by rush_to_boss
-- while slide_until is active. Returns a vec3 the caller should pathfinder-move to.
-- Re-projects each tick so the slide naturally arcs around corners.
function stuck_timeout.get_slide_target(player_pos)
    -- Direction from player toward boss (2D, normalised)
    local dx = BOSS_POS:x() - player_pos:x()
    local dy = BOSS_POS:y() - player_pos:y()
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then len = 0.001 end
    dx = dx / len
    dy = dy / len

    -- Perpendicular: left (+1) = (-dy, dx), right (-1) = (dy, -dx)
    local d = stuck_timeout.slide_dir
    local px = -dy * d
    local py =  dx * d

    local tx = player_pos:x() + px * SLIDE_DIST
    local ty = player_pos:y() + py * SLIDE_DIST
    local target = vec3:new(tx, ty, player_pos:z())
    return utility.set_height_of_valid_position(target)
end

function stuck_timeout.pick_slide_dir(player_pos)
    -- Try left perp first; if that walkability probe fails try right.
    -- "Biased toward boss" tiebreak: whichever side has a walkable point AND
    -- is not moving directly away from boss wins. In practice the wall is on
    -- one side so only one perp will be walkable.
    local dx = BOSS_POS:x() - player_pos:x()
    local dy = BOSS_POS:y() - player_pos:y()
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 1 end
    dx = dx / len
    dy = dy / len

    for _, d in ipairs({ 1, -1 }) do
        local px = -dy * d
        local py =  dx * d
        local probe = vec3:new(
            player_pos:x() + px * SLIDE_DIST * 0.5,
            player_pos:y() + py * SLIDE_DIST * 0.5,
            player_pos:z())
        probe = utility.set_height_of_valid_position(probe)
        if utility.is_point_walkeable(probe) then
            return d
        end
    end
    return 1  -- fallback
end

local function do_unstick(now, reason, player_pos)
    console.print(string.format('[GemFarmer] Wall unstick: %s — wall-sliding for %.0fs', reason, SLIDE_DURATION))
    tracker.healing_well_pos = nil
    tracker.escape_until     = -1  -- don't use the old pause; slide takes over immediately
    if BatmobilePlugin then
        BatmobilePlugin.clear_target(PLUGIN_LABEL)
        BatmobilePlugin.pause(PLUGIN_LABEL)
    end
    last_unstick_time = now
    last_osc_fix_time = now
    osc_history      = {}
    last_sample_time = -1

    -- Pick slide direction based on what's walkable from here
    stuck_timeout.slide_dir   = stuck_timeout.pick_slide_dir(player_pos)
    stuck_timeout.slide_until = now + SLIDE_DURATION
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
            do_unstick(now, string.format('oscillating (moved %.1fm, net %.2fm)', total, net), player_pos)
        end
    end
end

-- Hook into tracker.reset_run so state clears between runs
local _orig_reset = tracker.reset_run
tracker.reset_run = function()
    _orig_reset()
    reset()
    stuck_timeout.slide_until = -1
    stuck_timeout.slide_dir   = 1
end

stuck_timeout.update = function()
    -- Only monitor while inside, exploring, and not already done
    if not world.is_inside() then reset() return end
    if tracker.boss_found or tracker.boss_dead then reset() return end
    -- Don't fire while we're already wall-sliding (rush_to_boss drives movement)
    if stuck_timeout.slide_until > 0 and get_time_since_inject() < stuck_timeout.slide_until then return end
    -- Don't fire while in a legacy escape pause
    if tracker.escape_until > 0 and get_time_since_inject() < tracker.escape_until then return end

    local player = get_local_player()
    if not player then return end
    local player_pos = player:get_position()
    local now        = get_time_since_inject()

    -- Boss progress check — abandon if not getting closer over time
    local boss_dist = player_pos:dist_to(BOSS_POS)
    if boss_check_time < 0 then
        boss_check_time        = now
        boss_best_dist         = boss_dist
        boss_no_progress_since = now
    elseif (now - boss_check_time) >= BOSS_PROGRESS_INTERVAL then
        if boss_dist < (boss_best_dist - BOSS_PROGRESS_MIN) then
            boss_best_dist         = boss_dist
            boss_no_progress_since = now
        end
        boss_check_time = now

        local no_progress_for = now - boss_no_progress_since
        if no_progress_for >= BOSS_MAX_NO_PROGRESS then
            console.print(string.format('[GemFarmer] No progress toward boss for %.0fs (dist=%.1fm) — abandoning run', no_progress_for, boss_dist))
            reset()
            stuck_timeout.slide_until = -1
            tracker.boss_dead       = true
            tracker.loot_start_time = get_time_since_inject() - settings.loot_wait - 1
            return
        end
    end

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
        stuck_timeout.slide_until = -1
        tracker.boss_dead       = true
        tracker.loot_start_time = get_time_since_inject() - settings.loot_wait - 1
        return
    end

    -- Soft unstick — start wall-slide instead of blind free-roam
    if stuck_for >= settings.soft_reset then
        local since_last = (last_unstick_time < 0) and UNSTICK_COOLDOWN or (now - last_unstick_time)
        if since_last >= UNSTICK_COOLDOWN then
            do_unstick(now, string.format('no progress for %.0fs', stuck_for), player_pos)
        end
    end
end

return stuck_timeout
