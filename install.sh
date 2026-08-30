#!/usr/bin/env bash
# Apply the MacBookPro16,1 hybrid-graphics setup to a working Omarchy/Arch
# install. Idempotent: safe to re-run.
#
#   ./install.sh --kernel-package /path/to/linux-t2-mbp161-hybrid-*.pkg.tar.zst
#   ./install.sh --skip-kernel        # userspace + config only
#
# Run it as your normal user; it calls sudo where it needs to.
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kernel_package=""
do_kernel=1
do_aquamarine=1
while (( $# )); do
	case "$1" in
	--kernel-package) kernel_package="${2:?path required}"; shift 2 ;;
	--skip-kernel)    do_kernel=0; shift ;;
	--skip-aquamarine) do_aquamarine=0; shift ;;
	-h|--help) sed -n '2,9p' "$0"; exit 0 ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

say()  { printf '\n== %s\n' "$*"; }
info() { printf '   %s\n' "$*"; }
die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

say "preflight"
[[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)" == MacBookPro16,1 ]] ||
	die "this is not a MacBookPro16,1. These patches are DMI- and PCI-ID-gated and will do nothing elsewhere."
command -v pacman >/dev/null || die "pacman not found; this installer is Arch-specific."
[[ $EUID -ne 0 ]] || die "run as your normal user, not root. It uses sudo where needed."
info "MacBookPro16,1 confirmed"

# ---------------------------------------------------------------- kernel ---
if (( do_kernel )); then
	say "kernel"
	if [[ -n "$kernel_package" ]]; then
		[[ -f "$kernel_package" ]] || die "no such package: $kernel_package"
		info "installing $(basename "$kernel_package")"
		sudo pacman -U --noconfirm "$kernel_package"
	else
		cat <<-EOF
		   No --kernel-package given, so nothing was installed.

		   You need a kernel carrying kernel/patches/*.patch. Either:
		     * pass a package you built earlier:
		         ./install.sh --kernel-package /path/to/linux-t2-mbp161-hybrid-*.pkg.tar.zst
		     * or build one now, per docs/INSTALL.md section 1. Budget ~100 minutes.

		   Re-run with --skip-kernel once the kernel is in place.
		EOF
	fi
fi

kernel_pkg_name="$(pacman -Qq 2>/dev/null | grep -m1 -E '^(linux-t2-mbp161-hybrid|linux-mbp161)' || true)"

# ------------------------------------------------------------ aquamarine ---
if (( do_aquamarine )); then
	say "aquamarine (Intel-primary 4K fix)"
	if pacman -Q aquamarine 2>/dev/null | grep -q '0.14.0-2.1'; then
		info "already at 0.14.0-2.1"
	else
		info "building from aquamarine/PKGBUILD (a few minutes)"
		( cd "$here/aquamarine" && makepkg -si --noconfirm )
	fi
	if grep -qE '^\s*IgnorePkg.*aquamarine' /etc/pacman.conf; then
		info "already pinned via IgnorePkg"
	else
		info "pinning: without this a routine -Syu silently restores stock and 4K breaks"
		sudo sed -i 's/^#*\s*IgnorePkg\s*=.*/&\nIgnorePkg   = aquamarine/' /etc/pacman.conf ||
			echo "IgnorePkg   = aquamarine" | sudo tee -a /etc/pacman.conf >/dev/null
	fi
fi

# ------------------------------------------------------------ system bits --
say "system scripts, units and lid policy"
sudo install -Dm755 "$here/system/bin/mbp161-amdgpu-hybrid-prep"   /usr/local/bin/mbp161-amdgpu-hybrid-prep
sudo install -Dm755 "$here/system/bin/mbp161-amdgpu-dpm-governor"  /usr/local/bin/mbp161-amdgpu-dpm-governor
sudo install -Dm644 "$here/system/systemd/mbp161-hybrid-prep.service"         /etc/systemd/system/mbp161-hybrid-prep.service
sudo install -Dm644 "$here/system/systemd/mbp161-amdgpu-dpm-governor.service" /etc/systemd/system/mbp161-amdgpu-dpm-governor.service
sudo install -Dm644 "$here/system/systemd/30-mbp161-lid-safety.conf"          /etc/systemd/logind.conf.d/30-mbp161-lid-safety.conf
if [[ -d /etc/boot/hooks/post.d ]]; then
	sudo install -Dm755 "$here/system/boot-hooks/80-mbp161-default-entry" \
		/etc/boot/hooks/post.d/80-mbp161-default-entry
fi
info "installed"

# --------------------------------------------------------------- cmdline ---
say "kernel command line"
if [[ -d /etc/limine-entry-tool.d ]]; then
	if grep -rqs 'modprobe.blacklist=amdgpu' /etc/limine-entry-tool.d/*.conf 2>/dev/null; then
		cat <<-'EOF'
		   WARNING: modprobe.blacklist=amdgpu is present in an existing drop-in.
		   That blacklist is the safety net for an UNPATCHED kernel: it dodges the
		   i915/amdgpu bind race by never loading amdgpu, at the cost of the dGPU.
		   Patch 0001 fixes that race properly, so with these patches the blacklist
		   should be REMOVED -- otherwise you get no discrete GPU and no USB-C
		   display. Not removing it automatically; edit it yourself and re-run.
		EOF
	fi
	# Named zz- deliberately: drop-ins are read in sorted order and plain `=`
	# assignment is last-one-wins, so BOOT_ORDER here must load AFTER
	# omarchy-defaults.conf or Omarchy's ordering silently wins.
	sudo rm -f /etc/limine-entry-tool.d/mbp161-hybrid.conf
	sudo tee /etc/limine-entry-tool.d/zz-mbp161-hybrid.conf >/dev/null <<-'EOF'
		# MacBookPro16,1 hybrid graphics.
		#
		# apple_gmux.force_igd=1 hands the internal panel to the iGPU at gmux probe.
		#   (Patch 0001 also defaults this on by DMI; belt and braces.)
		# amdgpu.runpm=0 keeps the discrete GPU bound and awake. It drives the USB-C
		#   display, and runtime-suspending it is adjacent to what breaks suspend.
		#
		# `+=` so this appends to whatever root=/cryptdevice= your install already
		# needs. Never use `=` here: that replaces the whole line and you lose root.
		KERNEL_CMDLINE[default]+=" apple_gmux.force_igd=1 amdgpu.runpm=0"

		# Menu order only. Limine auto-boots `default_entry` (a path or a 1-based
		# index), not whichever kernel happens to be listed first. The post-hook
		# 80-mbp161-default-entry sets default_entry to
		# Omarchy/linux-t2-mbp161-hybrid. linux-t2 stays in the menu as a fallback.
		BOOT_ORDER="linux-t2-mbp161-hybrid, *, *fallback, Snapshots"
	EOF
	info "wrote /etc/limine-entry-tool.d/zz-mbp161-hybrid.conf"
	if command -v limine-update >/dev/null; then
		info "regenerating UKIs / limine.conf (picks up cmdline, BOOT_ORDER, default_entry)"
		sudo limine-update
	else
		info "limine-update not on PATH; reboot entries will not change until it is run"
	fi
else
	cat <<-'EOF'
	   No limine-entry-tool found. Add these to your bootloader's kernel cmdline
	   by hand, then regenerate your initramfs/UKI:
	       apple_gmux.force_igd=1 amdgpu.runpm=0
	   Make sure modprobe.blacklist=amdgpu is NOT present, and set the patched
	   kernel as the default entry with the distro kernel kept as a fallback.
	   In limine.conf that is `default_entry: <OS>/<kernel>`, not menu order.
	EOF
fi

# --------------------------------------------------------------- session ---
say "session GPU selection"
env_file="$HOME/.config/uwsm/env"
mkdir -p "$(dirname "$env_file")"
if grep -qs 'AQ_DRM_DEVICES' "$env_file"; then
	info "$env_file already sets AQ_DRM_DEVICES -- left alone, merge by hand if needed"
else
	printf '\n' >> "$env_file"
	cat "$here/system/uwsm-env-snippet.sh" >> "$env_file"
	info "appended the snippet to $env_file"
fi

# --------------------------------------------------------------- services --
say "services"
sudo systemctl daemon-reload
sudo systemctl enable mbp161-hybrid-prep.service mbp161-amdgpu-dpm-governor.service >/dev/null
info "enabled (they take effect at next boot; prep must run before the display manager)"

say "done -- reboot, then verify"
cat <<-EOF
   Installed kernel package: ${kernel_pkg_name:-<none: install one and re-run>}

   After rebooting into it:
     sudo grep '^default_entry:' /boot/limine.conf   # expect Omarchy/linux-t2-mbp161-hybrid
     journalctl -b -k | grep -E 'Switching to IGD|gmux panel'   # expect 3 lines
     cat /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level  # low
     hyprctl monitors | grep -E '^Monitor|[0-9]+x[0-9]+@'

   Plug the external display in AFTER boot; a cold boot with the cable already
   attached produces no hotplug event at all. See README "Known rough edges".
EOF
