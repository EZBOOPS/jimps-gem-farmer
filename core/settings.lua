local gui = require 'gui'

local settings = {
    plugin_label   = gui.plugin_label,
    plugin_version = gui.plugin_version,
    enabled        = false,
    use_keybind    = false,
    loot_wait      = 4,
    boss_range     = 40,
    enter_wait     = 4,
    reset_wait     = 3,
    show_boss      = false,
    soft_reset     = 30,
    hard_reset     = 150,
    roam_time      = 5,
}

settings.get_keybind_state = function()
    if not settings.use_keybind then return true end
    local kb = gui.elements.keybind_toggle
    return kb:get_key() ~= 0x0A and kb:get_state() == 1
end

settings.update_settings = function()
    settings.enabled    = gui.elements.main_toggle:get()
    settings.use_keybind = gui.elements.use_keybind:get()
    settings.loot_wait  = gui.elements.loot_wait:get()
    settings.boss_range = gui.elements.boss_range:get()
    settings.enter_wait = gui.elements.enter_wait:get()
    settings.reset_wait = gui.elements.reset_wait:get()
    settings.show_boss  = gui.elements.show_boss:get()
    settings.soft_reset = gui.elements.soft_reset:get()
    settings.hard_reset = gui.elements.hard_reset:get()
    settings.roam_time  = gui.elements.roam_time:get()
end

return settings
