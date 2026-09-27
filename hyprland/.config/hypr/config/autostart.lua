-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP ")
    hl.exec_cmd("noctalia")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' ")
    hl.exec_cmd("xhost +SI:localuser:root")
end)
