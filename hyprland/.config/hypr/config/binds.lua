local mainMod = "SUPER"
local noctCall = "noctalia msg "
--local launchPrefix = "uwsm app -- " -- if you are not using UWSM, make this empty (e.g. "")
local launchPrefix = "" -- not using UWSM

---------------------------
---- WINDOW MANAGEMENT ----
---------------------------

-- Window manipulation
hl.bind("CONTROL + Escape", hl.dsp.exec_cmd("hyprctl kill")) --| Kill window
hl.bind(mainMod .. " + Q", hl.dsp.window.close()) --| Close window
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.float({ action = "toggle" })) --| Toggle floating
hl.bind(mainMod .. " + A", hl.dsp.window.fullscreen({ mode = 1 })) --| Toggle maximize
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen()) --| Toggle fullscreen
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) --| Toggle split

-- Change focus
hl.bind(mainMod .. " + Left", hl.dsp.focus({ direction = "left" })) --| Focus left
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" })) --| Focus right
hl.bind(mainMod .. " + Up", hl.dsp.focus({ direction = "up" })) --| Focus up
hl.bind(mainMod .. " + Down", hl.dsp.focus({ direction = "down" })) --| Focus down
--hl.bind("ALT + Tab",           hl.dsp.window.cycle_next())
hl.bind(mainMod .. " + Tab", hl.dsp.window.cycle_next()) --| Switch windows in current workspace
--hl.bind(mainMod .. " + Tab",   hl.dsp.exec_cmd(noctCall .. "window-switcher"))
hl.bind("ALT + Tab", hl.dsp.exec_cmd(noctCall .. "window-switcher")) --| Switch windows in all workspaces

-- Move active window around workspaces & monitors
hl.bind(mainMod .. " + SHIFT + Up", hl.dsp.window.move({ direction = "u" })) --| Move window up
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.move({ direction = "r" })) --| Move window right
hl.bind(mainMod .. " + SHIFT + Left", hl.dsp.window.move({ direction = "l" })) --| Move window left
hl.bind(mainMod .. " + SHIFT + Down", hl.dsp.window.move({ direction = "d" })) --| Move window down
--hl.bind(mainMod .. " + SHIFT + 1",                    hl.dsp.window.move({ monitor = MONITOR1 }))
--hl.bind(mainMod .. " + SHIFT + 2",                    hl.dsp.window.move({ monitor = MONITOR2 }))
--hl.bind(mainMod .. " + SHIFT + 3",                    hl.dsp.window.move({ monitor = MONITOR3 }))
--hl.bind(mainMod .. " + SHIFT + mouse_up",             hl.dsp.window.move({ monitor   = "-1" }))
--hl.bind(mainMod .. " + SHIFT + mouse_down",           hl.dsp.window.move({ monitor   = "+1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + Right", hl.dsp.window.move({ workspace = "m+1" })) --| Move window to workspace on right
hl.bind(mainMod .. " + CONTROL + SHIFT + Left", hl.dsp.window.move({ workspace = "m-1" })) --| Move window to workspace on left
hl.bind(mainMod .. " + CONTROL + SHIFT + down", hl.dsp.window.move({ workspace = "emptym" })) --| Move window to a empty workspace
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up", hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }))

for i = 1, NUM_WPM do
	local key = i % 10
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = "m~" .. i })) --| Move window to workspace with number 0-9
end

-- Move & Resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag()) --| Move with mouse left
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize()) --| Resize with mouse right

-- Zoom
local function zoomfunction(value)
	local zoomvalue = hl.get_config("cursor:zoom_factor")
	if (zoomvalue + value) > 3.0 then
		hl.config({ cursor = { zoom_factor = 3.0 } })
	elseif (zoomvalue + value) < 1.0 then
		hl.config({ cursor = { zoom_factor = 1.0 } })
	else
		hl.config({ cursor = { zoom_factor = zoomvalue + value } })
	end
end
hl.bind(mainMod .. " + Minus", function()
	zoomfunction(-0.3)
end, { repeating = true }) --| Zoom in
hl.bind(mainMod .. " + Plus", function()
	zoomfunction(0.3)
end, { repeating = true }) --| Zoom out

--# Zoom with keypad
hl.bind(mainMod .. " + code:82", function()
	zoomfunction(-0.3)
end, { repeating = true })
hl.bind(mainMod .. " + code:86", function()
	zoomfunction(0.3)
end, { repeating = true })

------------------
---- LAUNCHER ----
------------------

hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(launchPrefix .. TERMINAL)) --| Terminal - foot
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(launchPrefix .. FILE_MANAGER)) --| File manger - dolphin
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(launchPrefix .. EDITOR)) --| Text editor - geany
hl.bind("XF86Calculator", hl.dsp.exec_cmd(launchPrefix .. CALCULATOR)) --| Calculator
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(launchPrefix .. BROWSER)) --| Browser - brave origin
hl.bind(mainMod .. " + ALT + B", hl.dsp.exec_cmd(launchPrefix .. BROWSER .. " --incognito  ")) --| Browser incognito - brave origin
hl.bind(mainMod .. " + Delete", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e btop")) --| System monitor - btop
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd(launchPrefix .. "zen-browser --new-window")) --| Browser - zen browser
hl.bind(mainMod .. " + ALT + Z", hl.dsp.exec_cmd(launchPrefix .. "zen-browser --private-window")) --| Browser incognito - zen browser
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(noctCall .. "settings-toggle")) --| Noctalia settings
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center")) --| Noctalia control center
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher")) --| App launcher
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher /emo")) --| Emoji
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd(noctCall .. "session lock")) --| Lock session
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd(noctCall .. "panel-toggle session")) --| Power menu
hl.bind(mainMod .. " + Y", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-large -e yazi ")) --| Yazi file manager
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(launchPrefix .. "super-productivity")) --| Super productivity
hl.bind(" ALT + Space", hl.dsp.exec_cmd(launchPrefix .. "~/.config/scripts/tools-manager.sh")) --| Tool manager
--hl.bind(" ALT + Z ", hl.dsp.exec_cmd(launchPrefix .. "voxtype record toggle")) --| voice dictate
hl.bind(" CONTROL + Space ", hl.dsp.exec_cmd(launchPrefix .. "handy --toggle-transcription")) --| voice dictate
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(launchPrefix .. "~/.config/scripts/webapps-launcher.sh")) --| Webapps launcher
hl.bind(mainMod .. " + T ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-large -e ~/.cargo/bin/tuxedo")) --| Tuxedo todo
--hl.bind(mainMod .. " + N ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-medium -e ~/.config/scripts/view-notes.sh")) --| View Quick notes
hl.bind(mainMod .. " + N ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-medium -e ~/.config/scripts/integrated-notetaker.sh -v")) --| View Quick notes
hl.bind(mainMod .. " + M ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-large -e ~/.config/scripts/integrated-notetaker.sh")) --| Integrated Markdown notetaker
hl.bind(mainMod .. " + ALT + T ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-small -e ~/.config/scripts/quicktodo.sh")) --| Quick todo
--hl.bind(mainMod .. " + ALT + N ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-small -e ~/.config/scripts/quicknote.sh")) --| Quick note
hl.bind(mainMod .. " + ALT + N ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-small -e ~/.config/scripts/integrated-notetaker.sh -q")) --| Quick note
hl.bind(mainMod .. " + ALT + R ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-small -e ~/.config/scripts/quickreminder.sh")) --| Quick reminder
hl.bind(mainMod .. " + ALT + D ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-medium -e ~/.config/scripts/quick-download.sh")) --| Quick downloader
hl.bind(mainMod .. " + ALT + H ",hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " --title apps-float-medium -e ~/.config/scripts/routine-tui.sh")) --| Habit/Routine tracker
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd(launchPrefix .. "~/.config/scripts/hypr-binds.sh")) --| Keybinds - shortcuts

---------------------------
---- HARDWARE CONTROLS ----
---------------------------

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctCall .. "volume-up"), { locked = true, repeating = true }) --| volume up
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctCall .. "volume-down"), { locked = true, repeating = true }) --| volume down
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(noctCall .. "volume-mute"), { locked = true }) --| mute audio
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(noctCall .. "mic-mute"), { locked = true }) --| mute mic

-- Media
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(noctCall .. "media toggle"), { locked = true }) --| play media
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(noctCall .. "media toggle"), { locked = true }) --| pause media
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(noctCall .. "media next"), { locked = true }) --| play next
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(noctCall .. "media previous"), { locked = true }) --| play previous

-- Brightness
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(noctCall .. "brightness-up"), { locked = true, repeating = true }) --| brightness up
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctCall .. "brightness-down"), { locked = true, repeating = true }) --| brightness down

-------------------
---- UTILITIES ----
-------------------

-- Screen Capture
--hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("hyprpicker -a -n"))			--| color picker
hl.bind("Print", hl.dsp.exec_cmd(noctCall .. "screenshot-region")) --| screenshot a region
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(noctCall .. "screenshot-fullscreen")) --| screenshot fullscreen

-- Theming and Wallpaper
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(noctCall .. "wallpaper-random")) --| change random wallpaper

-- Clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(noctCall .. "panel-toggle clipboard")) --| clipboard history

-- Notifications
hl.bind(mainMod .. " + ALT + A", hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center notifications")) --| notification history

-------------------------------
---- WORKSPACES & MONITORS ----
-------------------------------

-- Focus on monitors
--hl.bind(mainMod .. " + 1", hl.dsp.focus({ monitor = MONITOR1 }))
--hl.bind(mainMod .. " + 2", hl.dsp.focus({ monitor = MONITOR2 }))
--hl.bind(mainMod .. " + 3", hl.dsp.focus({ monitor = MONITOR3 }))

-- Focus on workspace number
-- Absolute
for i = 1, NUM_WPM do
	local key = i % 10
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i })) --| focus workspace with number 0-9
end
-- Relative
for i = 1, NUM_WPM do
	local key = i % 10
	hl.bind(mainMod .. " + CONTROL + " .. key, hl.dsp.focus({ workspace = "m~" .. i })) --| focus workspace with relative number
end

-- Move to adjacent workspaces and next empty on a given monitor
hl.bind(mainMod .. " + CONTROL + Right", hl.dsp.focus({ workspace = "m+1" })) --| Go to workspace on right
hl.bind(mainMod .. " + CONTROL + Left", hl.dsp.focus({ workspace = "m-1" })) --| Go to workspace on left
hl.bind(mainMod .. " + CONTROL + Down", hl.dsp.focus({ workspace = "emptym" })) --| Go to a empty workspace

-- Scroll through existing workspaces & monitors
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mainMod .. " + CONTROL + mouse_up", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special" })) --| Move window to Scratchpad
hl.bind(mainMod .. " + ALT + S", hl.dsp.workspace.toggle_special()) --| Go to Scratchpad
