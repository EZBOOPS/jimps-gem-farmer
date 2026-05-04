local plugin_label   = 'gem_farmer'
local plugin_version = '1.0.0'
console.print("Lua Plugin - Gem Farmer (Seer's Reach) - v" .. plugin_version)

local gui = {}
gui.plugin_label   = plugin_label
gui.plugin_version = plugin_version

local function cb(default, key)
    return checkbox:new(default, get_hash(plugin_label .. '_' .. key))
end

gui.elements = {
    main_tree      = tree_node:new(0),
    main_toggle    = cb(false, 'main_toggle'),
    use_keybind    = cb(false, 'use_keybind'),
    keybind_toggle = keybind:new(0x0A, true, get_hash(plugin_label .. '_keybind_toggle')),

    run_tree       = tree_node:new(1),
    loot_wait      = slider_int:new(1, 20, 3,   get_hash(plugin_label .. '_loot_wait')),
    boss_range     = slider_int:new(10, 100, 40, get_hash(plugin_label .. '_boss_range')),
    enter_wait     = slider_int:new(1, 10, 2,   get_hash(plugin_label .. '_enter_wait')),
    reset_wait     = slider_int:new(1, 10, 1,   get_hash(plugin_label .. '_reset_wait')),
    soft_reset     = slider_int:new(5, 120, 30,  get_hash(plugin_label .. '_soft_reset')),
    hard_reset     = slider_int:new(30, 600, 150, get_hash(plugin_label .. '_hard_reset')),
    roam_time      = slider_int:new(1, 30, 5,   get_hash(plugin_label .. '_roam_time')),

    wall_detours       = cb(true, 'wall_detours'),

    dbg_tree           = tree_node:new(1),
    show_boss          = cb(false, 'show_boss'),
    dbg_zone           = cb(false, 'dbg_zone'),
    dbg_pos            = cb(false, 'dbg_pos'),
    dbg_interactables  = cb(false, 'dbg_interactables'),
}

gui.pending_zone          = false
gui.pending_pos           = false
gui.pending_interactables = false

gui.render = function()
    if not gui.elements.main_tree:push('Z | Gem Farmer (Seers Reach) | v' .. plugin_version) then return end

    if BatmobilePlugin == nil then
        render_menu_header('This plugin requires BatmobilePlugin to work')
    end

    gui.elements.main_toggle:render('Enable', 'Enable the gem farmer bot. Stand in front of the dungeon entrance first.')
    gui.elements.use_keybind:render('Use keybind', 'Use a keybind to quick-toggle the bot')
    if gui.elements.use_keybind:get() then
        gui.elements.keybind_toggle:render('Toggle keybind', 'Press this key to enable / disable the bot')
    end

    if gui.elements.run_tree:push('Run Settings') then
        gui.elements.loot_wait:render('Loot wait (s)',      'Seconds to wait after boss dies before leaving.')
        gui.elements.boss_range:render('Boss search range (m)', 'Radius to scan for boss actor while exploring.')
        gui.elements.enter_wait:render('Enter wait (s)',    'Seconds to wait after interacting with the entrance.')
        gui.elements.reset_wait:render('Reset wait (s)',    'Seconds to wait after resetting the dungeon.')
        gui.elements.soft_reset:render('Soft reset (s)',    'Seconds without progress before attempting a nav unstick.')
        gui.elements.hard_reset:render('Hard reset (s)',    'Seconds without progress before abandoning the run entirely.')
        gui.elements.roam_time:render('Roam time (s)',      'Seconds of free roam after getting unstuck.')
        gui.elements.wall_detours:render('Wall detours', 'Enable hardcoded wall zone detours inside the dungeon.')
        gui.elements.run_tree:pop()
    end

    if gui.elements.dbg_tree:push('Debug') then
        gui.elements.show_boss:render('Show boss marker', 'Draw a red circle at the last known boss position.')
        gui.elements.dbg_zone:render('Print zone name to console', 'Check to print current zone info. Auto-unchecks.')
        if gui.elements.dbg_zone:get() then
            gui.elements.dbg_zone:set(false)
            gui.pending_zone = true
        end
        gui.elements.dbg_pos:render('Print my position to console', 'Prints your current X/Y/Z coords. Auto-unchecks.')
        if gui.elements.dbg_pos:get() then
            gui.elements.dbg_pos:set(false)
            gui.pending_pos = true
        end
        gui.elements.dbg_interactables:render('Print nearby interactables to console', 'Prints skin name + distance of all interactable actors within 30m. Auto-unchecks.')
        if gui.elements.dbg_interactables:get() then
            gui.elements.dbg_interactables:set(false)
            gui.pending_interactables = true
        end
        gui.elements.dbg_tree:pop()
    end

    gui.elements.main_tree:pop()
end

return gui
