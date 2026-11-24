-- Optional, Hyprland >= 0.55 (Lua config).
-- Put this in the OVERRIDES section of ~/.config/hypr/hyprland.lua, then
-- run `hyprctl reload`. It makes OpenLogi's lock key window float offscreen
-- the moment it maps, so it never takes tiled space or flashes on screen
-- before the mod closes it. The mod works without it.
hl.window_rule({
    name  = "openlogi-lock-key-osd",
    match = { class = "openlogi-lock-key-osd" },
    float = true,
    no_initial_focus = true,
    no_anim = true,
    size  = { 1, 1 },
    move  = { "monitor_w", "monitor_h" },
})
