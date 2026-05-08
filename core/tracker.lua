local tracker = {
    boss_found            = false,
    boss_dead             = false,
    boss_last_pos         = nil,
    loot_start_time       = -1,

    reset_time            = -1,

    interact_time         = -1,
    interact_cooldown     = 5.0,
    last_interact_attempt = nil,

    healing_well_pos      = nil,
    enter_time            = -1,
    escape_until          = -1,
    temis_confirmed       = false,
}

tracker.reset_run = function()
    tracker.boss_found            = false
    tracker.boss_dead             = false
    tracker.boss_last_pos         = nil
    tracker.loot_start_time       = -1
    tracker.reset_time            = -1
    tracker.interact_time         = -1
    tracker.last_interact_attempt = nil
    tracker.healing_well_pos      = nil
    tracker.enter_time            = -1
    tracker.escape_until          = -1
    tracker.temis_confirmed       = false
end

return tracker
