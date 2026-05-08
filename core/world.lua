local WORLD_OUTSIDE = 4156639130
local WORLD_DUNGEON = 2974643409

local function get_id()
    local w = world.get_current_world()
    return w and w:get_world_id() or nil
end

local world_module = {}

world_module.is_outside = function() return get_id() == WORLD_OUTSIDE end
world_module.is_inside  = function() return get_id() == WORLD_DUNGEON end

return world_module
