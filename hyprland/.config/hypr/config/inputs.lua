-- Input configuration

hl.config({
    input = {
	natural_scroll = true;
	numlock_by_default = true,
	repeat_delay = 500,
	repeat_rate = 40,
        sensitivity = 0.5,
        accel_profile = "flat",
	touchpad = {
	    natural_scroll = true,
	    scroll_factor = 1.2,
	},
    },
    -- Uncomment the section below to enable software cursors; this can help with cursor display or behavior issues
    -- cursor = {
    --     no_hardware_cursors = 1,
    -- },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "fullscreen" })
--hl.gesture({ fingers = 3, direction = "left",         action = "move" })
--hl.gesture({ fingers = 3, direction = "right",         action = "resize" })
hl.gesture({ fingers = 3, direction = "up",       action = "float" })
