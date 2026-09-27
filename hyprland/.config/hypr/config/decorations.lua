-- Look and feel configuration

hl.config({
    animations = {
        enabled = true,
    },
    general = {
        gaps_in = 3,
        gaps_out = 6,
        border_size = 3,
        extend_border_grab_area = 10,
        layout = "scrolling",
	resize_on_border = true,
    },
    decoration = {
        dim_special = 0.3,
        rounding = 8,
        active_opacity = 1.0,
        inactive_opacity = 0.9,
        fullscreen_opacity = 1,
        blur = {
	    enabled = false,	
            size = 5,
            passes = 4,
            special = true,
        },
	shadow = {
  	    enabled = false,
	},
    },
})
