-- Unit tests for pad.lua. Run from repo root: lua tests/pad_test.lua
package.path = "mod/G1LockPickHelper/Scripts/?.lua;tests/?.lua;" .. package.path
local pad = require("pad")
local t = require("testlib")
local test, eq = t.test, t.eq

local DIR = "/Game/UI/Textures/Common/HotkeysIcons/"

test("mode: keys are always letters, gamepad always icons, auto follows the input type", function()
    eq(pad.mode("keys", pad.GAMEPAD), "keys", "keys + gamepad")
    eq(pad.mode("gamepad", pad.KEYBOARD), "gamepad", "gamepad + keyboard")
    eq(pad.mode("gamepad", nil), "gamepad", "gamepad, type unknown")
    eq(pad.mode("auto", pad.GAMEPAD), "gamepad", "auto + gamepad")
    eq(pad.mode("auto", pad.KEYBOARD), "keys", "auto + keyboard")
    eq(pad.mode("auto", 2), "keys", "auto + touch")
    eq(pad.mode("auto", nil), "keys", "auto, type unknown")
end)

test("set: the game's Button icons option 2/3/4 is xbox/ps/switch", function()
    eq(pad.set("auto", 2, "PS5", "auto"), "xbox", "Xbox option wins over the name")
    eq(pad.set("auto", 3, "XSX", "auto"), "ps", "PS5")
    eq(pad.set("auto", 4, nil, "auto"), "switch", "Switch")
end)

test("set: the game's Auto takes the gamepad name; anything but PS5/SWITCH is xbox", function()
    eq(pad.set("auto", 1, "PS5", "auto"), "ps", "PS5")
    eq(pad.set("auto", 1, "SWITCH", "auto"), "switch", "SWITCH")
    eq(pad.set("auto", 1, "XSX", "auto"), "xbox", "XSX")
    eq(pad.set("auto", 1, "Generic", "auto"), "xbox", "Generic")
    eq(pad.set("auto", 1, nil, "auto"), "xbox", "no name")
end)

test("set: 'do not use' gives letters with icons = auto, a set with icons = gamepad", function()
    eq(pad.set("auto", 0, "NULL", "auto"), nil, "auto: letters")
    eq(pad.set("playstation", 0, "NULL", "auto"), nil, "auto: letters even with a set chosen")
    eq(pad.set("auto", 0, "NULL", "gamepad"), "xbox", "gamepad: xbox")
    eq(pad.set("switch", 0, "NULL", "gamepad"), "switch", "gamepad: the chosen set")
end)

test("set: [hint] gamepad picks the set whatever the game says", function()
    eq(pad.set("playstation", 2, "XSX", "auto"), "ps", "playstation")
    eq(pad.set("xbox", 3, "PS5", "auto"), "xbox", "xbox")
    eq(pad.set("switch", 1, "PS5", "gamepad"), "switch", "switch")
end)

test("set: an unread or unknown option is xbox", function()
    eq(pad.set("auto", nil, nil, "auto"), "xbox", "nothing read")
    eq(pad.set("auto", 7, "PS5", "auto"), "xbox", "an unknown value")
end)

test("resolve: letters or the set the hint draws", function()
    eq(pad.resolve("auto", "auto", { input_type = pad.KEYBOARD, button_graphics = 3 }), "keys", "keyboard")
    eq(pad.resolve("auto", "auto", { input_type = pad.GAMEPAD, button_graphics = 3 }), "ps", "gamepad, PS5")
    eq(pad.resolve("auto", "auto", { input_type = pad.GAMEPAD, button_graphics = 0 }), "keys", "do not use")
    eq(pad.resolve("gamepad", "auto", {}), "xbox", "icons forced, nothing read")
    eq(pad.resolve("keys", "playstation", { input_type = pad.GAMEPAD }), "keys", "keys")
    eq(pad.resolve("auto", "auto", nil), "keys", "no state")
end)

test("key textures: the game's D-pad icons of each set; other keys and sets have none", function()
    eq(pad.key_texture("ps", "W"), DIR .. "T_Icon_PS_DpadUp.T_Icon_PS_DpadUp", "ps W")
    eq(pad.key_texture("ps", "S"), DIR .. "T_Icon_PS_DpadDown.T_Icon_PS_DpadDown", "ps S")
    eq(pad.key_texture("ps", "A"), DIR .. "T_Icon_PS_DpadLeft.T_Icon_PS_DpadLeft", "ps A")
    eq(pad.key_texture("ps", "D"), DIR .. "T_Icon_PS_DpadRight.T_Icon_PS_DpadRight", "ps D")
    eq(pad.key_texture("xbox", "W"), DIR .. "T_Icon_Xbox_DpadUp.T_Icon_Xbox_DpadUp", "xbox W")
    eq(pad.key_texture("xbox", "A"), DIR .. "T_Icon_Xbox_DpadLeft.T_Icon_Xbox_DpadLeft", "xbox A")
    eq(pad.key_texture("switch", "S"), DIR .. "T_Icon_Switch_Down.T_Icon_Switch_Down", "switch S")
    eq(pad.key_texture("switch", "D"), DIR .. "T_Icon_Switch_Right.T_Icon_Switch_Right", "switch D")
    eq(pad.key_texture("ps", "R"), nil, "R")
    eq(pad.key_texture("keys", "W"), nil, "letters")
    eq(pad.key_texture(nil, "W"), nil, "no set")
end)

t.finish()
