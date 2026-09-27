-- Window rules wiki https://wiki.hypr.land/Configuring/Basics/Window-Rules/

-- Generic floating position
hl.window_rule({ match = { float = true }, center = true, persistent_size = true })

-- Picture-in-Picture
hl.window_rule({
    match             = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
    float             = true,
    opacity	      = "1.0 override",
    keep_aspect_ratio = true,
    size              = { "max(monitor_w, monitor_h)*0.25", "min(monitor_w, monitor_h)*0.25" },
    move = { "monitor_w - window_w - (monitor_w * 0.055)","monitor_h - window_h - (monitor_h * 0.055)"},
    pin               = true,
})

-- Gaming
local gamingApps = "^(steam_app.*|gamescope)$"
local gamingWorkspace = "name:gaming"

hl.window_rule({ match = { content = "game" }, workspace = gamingWorkspace })
hl.window_rule({ match = { xdg_tag = "^(.*game.*)$" }, workspace = gamingWorkspace, fullscreen_state = 2, content = "game", sync_fullscreen = true })
hl.window_rule({ match = { class = gamingApps }, workspace = gamingWorkspace })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, float = true })
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

-- Apps
hl.window_rule({ match = { class = "^(.*\\.exe)$", float = true }, monitor = PRIMARY_MONITOR, center = true, fullscreen_state = 0 })
hl.window_rule({ match = { class = "^(.*[Ll]auncher.*)$" }, float = true, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(vesktop|discord)$" }, monitor = PRIMARY_MONITOR })
hl.window_rule({ match = { class = "^(.*[Cc]alc.*)$" }, float = true, size = { "max(monitor_w, monitor_h)*0.17", "min(monitor_w, monitor_h)*0.43" } })
hl.window_rule({ match = { class = "^(org\\.kde\\.keditfiletype)$" }, float = true })
hl.window_rule({ match = { class = "^(org\\.kde\\.ark)$" }, float = true,  size = { "max(monitor_w, monitor_h)*0.40", "min(monitor_w, monitor_h)*0.40" } })
hl.window_rule({ match = { class = "^(.*satty.*)$", title = "^(Satty)$" }, min_size = { "max(monitor_w, monitor_h)*0.35", "min(monitor_w, monitor_h)*0.35" }, float = true })
hl.window_rule({ match = { class = "^(dev\\.)?(noctalia\\.Noctalia(\\.Settings)?)$" }, float = true, size = { "monitor_w*0.70", "monitor_h*0.70" } })
hl.window_rule({
    match = {
        class = "^(org\\.kde\\.dolphin|[Tt]hunar)$",
        title = "negative:^(Moving.*|Create New.*|Extract.*|Delete.*|Compress.*|Copying.*|Progress.*|Configure.*|Properties.*|Choose\\sApplication.*)$",
    },
    float = false,
    size = { "max(monitor_w, monitor_h)*0.50", "min(monitor_w, monitor_h)*0.55" },
})

-- Opacity Overrides
local terminals = "^(kitty|foot|ghostty|[Kk]onsole|Alacritty|gnome-terminal|xfce[0-9]?-terminal)$"

hl.window_rule({ match = { class = "^(firefox|brave|brave-origin|zen)$" }, opacity = "1.0 override" })
hl.window_rule({ match = { class = terminals }, opacity = "0.95 override" }) -- Override opacity in favor of terminal settings for opacity. If your terminal doesn't support transparency, you can remove this rule.
hl.window_rule({ match = { class = "^(mpv|org.kde.haruna|.*plex.*|org\\.kde\\.gwenview|.*vlc.*)$" }, opacity = "1.0 override" })

-- Float Utility Windows
local floatApps = {
    { class = "^(kvantummanager|qt[56]ct|nwg-look)$" },
    { class = "^(org.pulseaudio.pavucontrol|blueman-manager|nm-applet|nm-connection-editor)$" },
    { title = "^(Winetricks.*|Protontricks.*)$" },
}
for _, m in ipairs(floatApps) do hl.window_rule({ match = m, float = true }) end

-- Float Common Modals
local modalMatches = {
    { title = "^(Open|Authentication Required|Add Folder to Workspace|Choose Files|Save As|Confirm to replace files|File Operation Progress)$" },
    { initial_title = "^(Open File)$" },
    { class = "^([Xx]dg-desktop-portal-gtk)$" },
    { title = "^(File Upload|Choose wallpaper|Library)(.*)$" },
    { class = "^(.*dialog.*)$" },
    { title = "^(.*dialog.*)$" },
    { class = "^(hyprland-share-picker)$"},
    { title = "^(tools-menu)$" },
    { title = "^([Gg]alculator)$" },
    { class = "^([Xx]archiver)$" },
}
for _, m in ipairs(modalMatches) do hl.window_rule({ match = m, float = true }) end

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})


--  terminal windows ~ TUI

hl.window_rule({ match = { class = "^foot$", title = "test-float" }, float = true })
--hl.window_rule({ match = { class = "^xarchiver$" }, float = true })
hl.window_rule({ match = { class = "^foot$", title = "apps-float-small" }, float = true, size = { "max(monitor_w, monitor_h)*0.4", "min(monitor_w, monitor_h)*0.4" }})
hl.window_rule({ match = { class = "^foot$", title = "apps-float-medium" }, float = true, size = { "max(monitor_w, monitor_h)*0.6", "min(monitor_w, monitor_h)*0.6" }})
hl.window_rule({ match = { class = "^foot$", title = "apps-float-large" }, float = true, size = { "max(monitor_w, monitor_h)*0.8", "min(monitor_w, monitor_h)*0.8" }})

hl.window_rule({ match = { class = "^foot$", title = "tools-float" }, float = true, size = { "max(monitor_w, monitor_h)*0.6", "min(monitor_w, monitor_h)*0.6" }})

hl.window_rule({ match = { title = "Ente Auth" }, float = true })



-- Float Browser Extensions and Popups
local extensionMatches = {
    { title = "^(Bitwarden)$" },
    { initial_title = "^(_crx_.*)$" }, -- Robustly catches ALL Chromium-based extension popups (Brave, Chrome, Edge, etc.)
}
for _, m in ipairs(extensionMatches) do 
    hl.window_rule({ match = m, float = true }) 
end






