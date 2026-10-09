-- G1LockPickHelper pad: what the hint draws for a key - its letter or the game's gamepad icon - and the icon
-- textures. Pure Lua 5.4: main.lua reads the game's state (the input type, the "Button icons" option, the gamepad
-- name) and passes it in.
local M = {}

-- CommonInputSubsystem:GetCurrentInputType() (ECommonInputType).
M.KEYBOARD, M.GAMEPAD = 0, 1

-- GothicGameUserSettings.ButtonGraphics (the game's "Button icons" option).
M.BUTTON_GRAPHICS = { [0] = "none", [1] = "auto", [2] = "xbox", [3] = "ps", [4] = "switch" }

local SETS = { playstation = "ps", xbox = "xbox", switch = "switch" } -- [hint] gamepad -> set
local FROM_NAME = { PS5 = "ps", SWITCH = "switch" } -- CommonUI gamepad name -> set; any other name: xbox

local DIR = "/Game/UI/Textures/Common/HotkeysIcons/"
local KEY_TEXTURES = { -- model key -> the game's icon: W up, S down, A left, D right
    ps = { W = "T_Icon_PS_DpadUp", S = "T_Icon_PS_DpadDown", A = "T_Icon_PS_DpadLeft", D = "T_Icon_PS_DpadRight" },
    xbox = { W = "T_Icon_Xbox_DpadUp", S = "T_Icon_Xbox_DpadDown", A = "T_Icon_Xbox_DpadLeft",
        D = "T_Icon_Xbox_DpadRight" },
    switch = { W = "T_Icon_Switch_Up", S = "T_Icon_Switch_Down", A = "T_Icon_Switch_Left", D = "T_Icon_Switch_Right" },
}

-- icons: [hint] icons; input_type: GetCurrentInputType() or nil (unread). "keys" or "gamepad".
function M.mode(icons, input_type)
    if icons == "gamepad" then return "gamepad" end
    if icons == "auto" and input_type == M.GAMEPAD then return "gamepad" end
    return "keys"
end

-- gamepad: [hint] gamepad; button_graphics: ButtonGraphics or nil; gamepad_name: the CommonUI gamepad name or nil;
-- icons: [hint] icons. The icon set, or nil: the game says "do not use" and icons is auto - letters, like the game.
function M.set(gamepad, button_graphics, gamepad_name, icons)
    local game = M.BUTTON_GRAPHICS[button_graphics]
    if game == "none" and icons == "auto" then return nil end
    if SETS[gamepad] then return SETS[gamepad] end
    if game == "ps" or game == "xbox" or game == "switch" then return game end
    if game == "auto" then return FROM_NAME[gamepad_name] or "xbox" end
    return "xbox"
end

-- What the hint draws: "keys" (the letters) or an icon set. state: { input_type, button_graphics, gamepad_name }.
function M.resolve(icons, gamepad, state)
    state = state or {}
    if M.mode(icons, state.input_type) == "keys" then return "keys" end
    return M.set(gamepad, state.button_graphics, state.gamepad_name, icons) or "keys"
end

-- The object path of the icon of a model key (W, S, A, D) in a set; nil for anything else.
function M.key_texture(set, key)
    local names = KEY_TEXTURES[set]
    local name = names and names[key]
    if not name then return nil end
    return DIR .. name .. "." .. name
end

return M
