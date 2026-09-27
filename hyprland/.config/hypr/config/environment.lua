-- Environmental variables (for reference https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/)
-- if you use UWSM, define your variables in ~/.config/uwsm/env
-- if you don't use UWSM, define your variables here (e.g. hl.env("QT_QPA_PLATFORM", "wayland"))

-- Environment
hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("XCURSOR_SIZE", "30")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")
hl.env("HYPRCURSOR_SIZE", "30")

hl.env("QT_QPA_PLATFORMTHEME","qt6ct")
--hl.env("QT_QPA_PLATFORMTHEME","qt5ct")


-- if you have an NVIDIA GPU uncomment the following lines:

-- hl.env("GBM_BACKEND", "nvidia-drm") -- force GBM as a backend
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia") -- force GBM as a backend
-- hl.env("LIBVA_DRIVER_NAME", "nvidia") -- Hardware acceleration on NVIDIA GPUs
-- hl.env("__GL_GSYNC_ALLOWED", "1") -- Controls if G-Sync capable monitors should use Variable Refresh Rate (VRR)
