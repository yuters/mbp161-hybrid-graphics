# MacBookPro16,1 hybrid graphics: pick the compositor's DRM devices.
# Append to ~/.config/uwsm/env (or the equivalent for your session manager).
#
# Intel must be the PRIMARY device and AMD the secondary. That ordering
# requires the patched aquamarine in this repo; on stock aquamarine a 4K
# modeset on the secondary AMD backend fails drmModeAddFB2WithModifiers and
# the external head scans out a stale buffer -- you get a quarter-screen
# desktop.
#
# The AMD GPU is only opened when DPM is already at a STATIC level.
# power_dpm_force_performance_level=auto kills the SMU in about 9 seconds on
# this chip, even with the GPU completely idle. mbp161-amdgpu-hybrid-prep
# sets `low` at boot; if for any reason it did not run, this falls back to
# Intel-only rather than opening AMD at a level that will hang the machine.
#
# Export HYPR_LID_ONLY=1 before starting the session for an Intel-only session.

igpu=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-card 2>/dev/null || true)
dgpu=$(readlink -f /dev/dri/by-path/pci-0000:03:00.0-card 2>/dev/null || true)
dpm=$(cat /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level 2>/dev/null || true)

if [ "${HYPR_LID_ONLY:-}" = 1 ]; then
	[ -n "$igpu" ] && [ -e "$igpu" ] && export AQ_DRM_DEVICES="$igpu"
elif [ -n "${AQ_DRM_DEVICES:-}" ] && [ "${AQ_ALLOW_DGPU:-}" = "1" ]; then
	:
elif { [ "$dpm" = "high" ] || [ "$dpm" = "low" ]; } && [ -n "$dgpu" ] && [ -e "$dgpu" ] && [ -n "$igpu" ] && [ -e "$igpu" ]; then
	export AQ_DRM_DEVICES="$igpu:$dgpu"
	export AQ_ALLOW_DGPU=1
elif [ -n "$igpu" ] && [ -e "$igpu" ]; then
	export AQ_DRM_DEVICES="$igpu"
fi
