-- Bits of the previous CachyOS Hyprland config kept on top of Omarchy.
-- Loaded last from hyprland.lua; delete this file (and its require) to drop them.
-- Original: ~/.config/hypr.cachyos-backup-20261029-180828/config/

hl.config({
  general = {
    resize_on_border = true,
    extend_border_grab_area = 10,
  },
  misc = {
    middle_click_paste = false,
    -- Hide the terminal while a GUI app it launched is open.
    enable_swallow = true,
    swallow_regex = "^(kitty|Alacritty|com\\.mitchellh\\.ghostty|foot)$",
  },
  render = {
    -- Fullscreen video/games skip compositing (easier on the UHD 620).
    direct_scanout = 2,
  },
})

-- Small floating calculator.
hl.window_rule({
  match = { class = "^(org\\.gnome\\.Calculator)$" },
  float = true,
  size = { "max(monitor_w, monitor_h)*0.17", "min(monitor_w, monitor_h)*0.43" },
})

-- Games go to their own workspace, fullscreen.
local gamingApps = "^(steam_app.*|gamescope)$"
local gamingWorkspace = "name:gaming"
hl.window_rule({ match = { content = "game" }, workspace = gamingWorkspace })
hl.window_rule({ match = { xdg_tag = "^(.*game.*)$" }, workspace = gamingWorkspace, fullscreen_state = 2, content = "game", sync_fullscreen = true })
hl.window_rule({ match = { class = gamingApps }, workspace = gamingWorkspace })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Launching\\.{3})$" }, float = true, center = true, workspace = gamingWorkspace })
hl.window_rule({
  match = {
    class         = gamingApps,
    title         = "^(.+)$",
    initial_title = "negative:^(.*\\\\home\\\\.*)$",
  },
  content          = "game",
  decorate         = false,
  fullscreen_state = 2,
  size             = { "monitor_w", "monitor_h" },
  sync_fullscreen  = true,
})
hl.window_rule({
  match = {
    class         = "^(steam_app.*)$",
    initial_title = "^$",
  },
  center           = true,
  float            = true,
  fullscreen       = false,
  fullscreen_state = 0,
  workspace        = gamingWorkspace,
})

-- Screen zoom: SUPER + -/= (and keypad -/+).
local function zoom(step)
  local z = hl.get_config("cursor:zoom_factor") + step
  hl.config({ cursor = { zoom_factor = math.max(1.0, math.min(3.0, z)) } })
end
hl.bind("SUPER + minus", function() zoom(-0.3) end, { repeating = true })
hl.bind("SUPER + equal", function() zoom(0.3) end, { repeating = true })
hl.bind("SUPER + code:82", function() zoom(-0.3) end, { repeating = true })
hl.bind("SUPER + code:86", function() zoom(0.3) end, { repeating = true })

-- Task-manager habit: Ctrl+Shift+Esc opens btop.
o.bind("CTRL + SHIFT + Escape", "Activity", { tui = "btop" })

-- Qt apps use qt6ct (themed by the Omarchy theme-set hook) instead of Omarchy's gtk3 default.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
