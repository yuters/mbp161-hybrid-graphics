# Install

Read [the warnings](../README.md#do-not-do-these) first. One of them will hang
your machine if you ignore it.

## The short path

If you already have a kernel package built from `kernel/patches/*.patch` — from
a previous install of yours, or built once and kept — you do not need to rebuild
anything:

```sh
./install.sh --kernel-package /path/to/linux-t2-mbp161-hybrid-*.pkg.tar.zst
```

That installs the kernel, builds and pins the patched aquamarine, installs the
scripts, units and lid policy, writes the kernel command line, appends the
session GPU selection, and enables the services. It is idempotent; re-running is
safe. `./install.sh --skip-kernel` does everything except the kernel.

**A kernel package survives a full OS reinstall.** It is a normal
`.pkg.tar.zst`. Keeping one on a separate partition turns a 100-minute rebuild
into a 30-second `pacman -U`. The rest of this document is the long path: how to
build that package the first time.

## Prerequisite: a booting install first

Apply this repo on top of an Arch/Omarchy install that already boots and logs
in. The stock Omarchy installer detects a T2 Mac and installs `linux-t2` for
you; there is nothing extra to add.

Keep the distro kernel (`linux-t2`) installed. `install.sh` puts
`linux-t2-mbp161-hybrid` first in the menu (`BOOT_ORDER`) and sets Limine's
`default_entry` to `Omarchy/linux-t2-mbp161-hybrid`. Those are different
knobs: `BOOT_ORDER` is limine-entry-tool's menu sort; Limine auto-boots
`default_entry` (a path or a 1-based index, see CONFIG.md). Using only
`BOOT_ORDER` does not change auto-boot if `default_entry` already names a
specific kernel — which a previous config on this machine did
(`Omarchy/linux-t2`).

Every path below assumes Arch. Adapt package steps for other distributions; the
kernel patches and system files are distribution-agnostic.

## 0. Prerequisites

Omarchy on this machine already provides the T2 stack (keyboard, trackpad,
audio, NVMe, Wi-Fi). This repo adds hybrid graphics on top.

You also need `apple-set-os` (or an equivalent EFI shim) so that the iGPU is
visible in `lspci -s 00:02.0`. Without it the mux switch has nowhere to go:

```sh
lspci -s 00:02.0     # must show the Intel VGA controller
lspci -s 03:00.0     # must show the AMD Navi 14
```

## 1. Kernel

Start from Linux 7.2 with the t2linux v7.2-rc6 patch stack applied, then:

```sh
cd linux
for p in /path/to/mbp161-hybrid-graphics/kernel/patches/*.patch; do
    patch -p1 < "$p"
done
```

Confirm `CONFIG_APPLE_GMUX=y` (or `=m`) — patches 2 and 3 call
`apple_gmux_panel_is_igd()` and fall back to a stub without it.

Build and install however you normally do. On Arch, `make pacman-pkg` works, but
**set `PACMAN_PKGBASE` explicitly**:

```sh
PACMAN_PKGBASE=linux-t2-mbp161-hybrid make pacman-pkg
```

Without it the package is named `linux-upstream` and installs *alongside* your
real kernel rather than replacing it. `PACMAN_PKGBASE` is also the Limine
entry name.

After installing, verify the package owns every file it should — this catches
modules you hot-replaced during testing and forgot about:

```sh
sudo pacman -Qkk linux-t2-mbp161-hybrid      # expect zero altered files
```

## 2. Kernel command line

Patch 1 makes `force_igd` default on for `MacBookPro16,1` by DMI, so nothing is
strictly required. Two parameters are worth knowing about:

```
apple_gmux.force_igd=0     # escape hatch: boot WITHOUT the mux switch
amdgpu.runpm=0             # see below
```

**`amdgpu.runpm` needs a decision, and I owe you honesty about it.** The
reference machine ran `amdgpu.runpm=-2` ("auto with power down when displays are
attached"), but it did so alongside a larger research tree that is deliberately
not shipped here — including a gmux runtime-PM path and an `amdgpu.gmux_runpm`
parameter that **does not exist** in a clean build. If you copied that command
line from a write-up of this work, drop `amdgpu.gmux_runpm`; it will be silently
ignored at best.

With only the four patches in this repo, amdgpu has no gmux runtime-PM support,
so the discrete GPU simply stays bound and awake — which is what this
configuration wants, since it is driving the external display and since runtime
suspending it is close to what breaks suspend in the first place.
`amdgpu.runpm=0` states that intent explicitly, and it is **now the tested
value**: a build from only these four patches was booted with
`apple_gmux.force_igd=1 amdgpu.runpm=0` and behaved correctly —
`/sys/bus/pci/devices/0000:03:00.0/power/control` reads `on`,
`runtime_suspended_time` stays `0`, the GPU never attempts a runtime suspend,
and both displays plus s2idle work. Use `runpm=0`.

Regenerate your initramfs / UKI afterwards.

## 3. aquamarine

Required for Intel-primary. On stock aquamarine you get a quarter-screen 4K
desktop.

```sh
cd aquamarine
makepkg -si
```

Then pin it, or the next `pacman -Syu` silently reverts you to a broken display
with no obvious cause. In `/etc/pacman.conf`:

```
IgnorePkg = aquamarine
```

Re-apply the patch and bump `pkgrel` when you deliberately update aquamarine.

## 4. System services

```sh
sudo install -m755 system/bin/mbp161-amdgpu-hybrid-prep      /usr/local/bin/
sudo install -m755 system/bin/mbp161-amdgpu-dpm-governor     /usr/local/bin/
sudo install -m644 system/systemd/mbp161-hybrid-prep.service            /etc/systemd/system/
sudo install -m644 system/systemd/mbp161-amdgpu-dpm-governor.service    /etc/systemd/system/
sudo install -Dm644 system/systemd/30-mbp161-lid-safety.conf \
     /etc/systemd/logind.conf.d/30-mbp161-lid-safety.conf

sudo install -m755 system/boot-hooks/80-mbp161-default-entry \
     /etc/boot/hooks/post.d/80-mbp161-default-entry

sudo systemctl daemon-reload
sudo systemctl enable mbp161-hybrid-prep.service
sudo systemctl enable mbp161-amdgpu-dpm-governor.service
sudo limine-update
```

The Limine post-hook rewrites `default_entry` to the patched kernel after
`limine-update`.

`mbp161-hybrid-prep` must run **before** the display manager. It sets a static
DPM level and turns off the phantom AMD eDP connector. If it has not run, the
session env snippet below deliberately falls back to Intel-only rather than
opening the AMD GPU at a level that will hang the machine.

## 5. Session environment

Append `system/uwsm-env-snippet.sh` to `~/.config/uwsm/env` (or your session
manager's equivalent). It sets `AQ_DRM_DEVICES` to Intel-first and only opens
AMD when DPM is already at a static level.

## 6. Verify

Reboot, log in normally, then:

```sh
# both GPUs present, both outputs live
hyprctl monitors | grep -E '^Monitor|[0-9]+x[0-9]+@'

# DPM is static, never `auto`
cat /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level

# idle power, expect roughly 4-5 W
cat /sys/class/drm/card1/device/hwmon/hwmon*/power1_average
```

Plug the external display in **after** boot. A cold boot with the cable already
attached produces no hotplug event; replug it.

## 7. Optional: verify suspend

```sh
systemctl suspend
```

To measure how long it actually slept — kernel and journal timestamps cannot
tell you, because printk does not advance across the sleep and journald stamps
its whole backlog at flush:

```sh
python3 -c 'import time; print("%.2f s suspended since boot" % (
    time.clock_gettime(time.CLOCK_BOOTTIME) -
    time.clock_gettime(time.CLOCK_MONOTONIC)))'
```

For sleep *power*, unplug the charger first — on AC the battery does not
discharge and you will measure nothing. Sample
`/sys/class/power_supply/BAT0/charge_now` before and after, and subtract the
awake portion of the bracket or you will overstate the figure.
