-- Personal keybinding overrides. Omarchy defaults load first, then these.
-- See all bindings with: omarchy menu keybindings --print

-- Calculator: gnome-calculator instead of omacalc.
hl.unbind("SUPER + CTRL + Q")
o.bind("SUPER + CTRL + Q", "Calculator", "gnome-calculator")

hl.unbind("XF86Calculator")
o.bind("XF86Calculator", "Calculator", "gnome-calculator")

-- Spotify is not installed.
hl.unbind("SUPER + SHIFT + M")

-- From the Omarchy install: SUPER+ALT+arrows move to the previous/next workspace.
hl.unbind("SUPER + ALT + LEFT")
hl.unbind("SUPER + ALT + RIGHT")
o.bind("SUPER + ALT + LEFT", "Previous workspace", hl.dsp.focus({ workspace = "r-1" }))
o.bind("SUPER + ALT + RIGHT", "Next workspace", hl.dsp.focus({ workspace = "r+1" }))
