# Install

Read [the warnings](../README.md#do-not-do-these) first. One of them will hang
your machine if you ignore it.

Every path below assumes Arch. Adapt package steps for other distributions; the
kernel patches and system files are distribution-agnostic.

## 0. Prerequisites

You need a working [t2linux](https://wiki.t2linux.org/) install first — keyboard,
trackpad, audio, NVMe and Wi-Fi all depend on it. This repo assumes that is
already done and adds hybrid graphics on top.

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
PACMAN_PKGBASE=linux-mbp161 make pacman-pkg
```

Without it the package is named `linux-upstream` and installs *alongside* your
real kernel rather than replacing it.

After installing, verify the package owns every file it should — this catches
modules you hot-replaced during testing and forgot about:

```sh
sudo pacman -Qkk linux-mbp161      # expect zero altered files
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

sudo systemctl daemon-reload
sudo systemctl enable mbp161-hybrid-prep.service
sudo systemctl enable mbp161-amdgpu-dpm-governor.service
```

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
