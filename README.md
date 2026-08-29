# MacBookPro16,1 hybrid graphics on Linux

Dual-GPU display, power management and suspend for the 16-inch 2019 MacBook Pro
(`MacBookPro16,1`) running Linux: **internal panel on the Intel iGPU, USB-C on
the AMD dGPU, one Wayland session across both, and a discrete GPU that idles
instead of burning 25 W.**

This is what the machine does with these patches applied:

| | |
|---|---|
| Internal panel | Intel `eDP-1`, 3072x1920@60 |
| USB-C | AMD `DP-5`, 3840x2160@60 |
| Session | one compositor spanning both GPUs, Intel primary |
| Idle dGPU power | 4-5 W, rising automatically under load |
| Suspend | s2idle works with the external display attached or detached |
| Sleep power | ~2.1 W (about 28 h on a full battery) |
| Lid closed while docked | external display keeps running, no suspend |

## Hardware and software this was built against

- `MacBookPro16,1` — Intel UHD 630 (`8086:9bc4` at `00:02.0`), AMD Navi 14
  (`1002:7340` at `03:00.0`), Apple gmux, two Intel JHL7540 Titan Ridge USB-C
  controllers, Apple T2.
- Arch Linux, Hyprland via uwsm, aquamarine 0.14.0.
- Linux 7.2 with the [t2linux](https://wiki.t2linux.org/) v7.2-rc6 patch stack.
  **The T2 stack is a prerequisite, not part of this repo** — you need it for
  the keyboard, trackpad, audio and NVMe regardless.
- Tested on one machine. See [What is and isn't verified](#what-is-and-isnt-verified).

## The four problems, and what fixes each

Each of these was a separate defect with a separate cause. They were originally
misattributed to each other, so it is worth being precise.

**1. The internal panel is black.** Firmware POSTs this machine with the panel
muxed to the discrete GPU. i915 reads eDP DPCD down the inactive AUX, fails, and
permanently drops the panel — silently, with no error in the log.
→ `kernel/patches/0001` switches the mux to the iGPU during apple-gmux probe,
before either DRM driver binds, and drops the firmware framebuffer *before*
`gmux_switchto()`. That ordering is the whole fix: without dropping fbcon first
the boot succeeded roughly 6 times in 9.

**2. A phantom internal display on the AMD side.** With the panel muxed away,
amdgpu still probes its own eDP link. It stalls on EDID, reports the connector
connected with no sink, steals `fb0`, and blocks runtime idle.
→ `kernel/patches/0002` and `0003` teach amdgpu that the internal panel is not
its to drive while the mux is on the iGPU. USB-C DP is untouched; its AUX is
pinned to the discrete GPU.

**3. 4K on USB-C draws a quarter-screen desktop.** With Intel as the
compositor's primary GPU, the external head is fed by a cross-GPU blit. On a
mode change aquamarine handed amdgpu a buffer it rejects,
`drmModeAddFB2WithModifiers` failed, and the display scanned out a stale
buffer.
→ `aquamarine/intel-primary-4k.patch` selects the fresh, mode-sized consumer
buffer before deciding whether to import or blit.

**4. Idle power, and a hard lock.** The discrete GPU idled at 25 W. The obvious
fix — `power_dpm_force_performance_level=auto` — **hung the machine in this
configuration**: the SMU stopped responding about 9 seconds after the write,
then an SDMA ring timeout, then a GPU reset. That was measured with the panel
muxed to the iGPU and the discrete GPU completely **idle** — USB-C unplugged, no
outputs, no CRTC, `gpu_busy_percent=0`. So it is not a load problem, but see
[the scope of that finding](#the-auto-warning-and-its-limits) before treating it
as a property of the chip.
→ `system/bin/mbp161-amdgpu-hybrid-prep` pins a static `low` at boot (4-5 W, and
still drives 4K@60 — `low` is a clock *ceiling*, not a pin).
`system/bin/mbp161-amdgpu-dpm-governor` raises it to `high` under sustained load
and drops back when idle. **Neither ever writes `auto`.**

**Bonus: suspend.** Every system suspend used to end in a reboot — the SMU
returned `-ETIME`, both Titan Ridge controllers came back `-ENODEV`, and DP Alt
Mode fell back to a USB Billboard device.
→ `kernel/patches/0004` leaves six PCI functions and their driver state
completely alone across s2idle, and marks their bridges `skip_bus_pm`. The
tradeoff is honest: those devices stay powered, which is why sleep costs ~2.1 W
rather than the ~0.2 W macOS achieves. **The working resume and the 2 W floor
are the same design decision.** Deep S3 is still broken and is not addressed
here.

## Install

See [docs/INSTALL.md](docs/INSTALL.md) for the full procedure. In short:

1. Build a kernel from Linux 7.2 + the t2linux v7.2-rc6 stack, then apply
   `kernel/patches/*.patch`.
2. Boot it. `apple_gmux.force_igd` now defaults on for this model by DMI; see
   [the kernel command line notes](docs/INSTALL.md#2-kernel-command-line) for
   the one parameter that needs a decision.
3. Build the patched aquamarine (`aquamarine/`) and pin it so a routine
   `pacman -Syu` cannot silently revert you.
4. Install `system/bin/*`, `system/systemd/*`, and the `uwsm` env snippet.

## What is and isn't verified

Stated plainly, because a repo that overclaims is worse than no repo.

**Verified on the machine, repeatedly:** the display configuration above; 4-5 W
idle; four consecutive real s2idle sleeps (attached and detached) with no
errors, no reboot and unbroken uptime; sleep power measured on battery via
`CLOCK_BOOTTIME - CLOCK_MONOTONIC`; lid-closed-while-docked keeping the external
display alive.

**On the boot count, precisely.** The gmux ordering change was measured at 26
consecutive clean boots, but that run used hand-built modules loaded into a
running kernel, not the packaged patch here. Across the packaged builds the
record is 6 clean boots. The pre-fix baseline it replaced was roughly 6 good
boots in 9. Note also that a bad boot cannot be detected by grepping the log:
the failure is that i915 reads DPCD down the inactive AUX and *silently* drops
the panel, so you get a black display and no error at all. Score boots by the
panel lighting up and by the presence of `apple_gmux: Switching to IGD`, never
by an absent error.

**Not verified:** anything on a second machine, any other Apple model, any other
kernel base, and deep S3 (`mem_sleep_default=deep`), which remains broken —
amdgpu's mode-1 reset and Titan Ridge power removal are both unfixed.

**Known rough edges:** the monitor layout can swap sides after a lid close/open
cycle, because the compositor re-lays-out from scratch rather than restoring the
previous arrangement — pin positions in your compositor config if it bothers
you. A cold boot with the USB-C cable already attached produces no hotplug event at
all, and you must replug after boot — this is a limitation, not a bug to work
around. On a cold boot with the Dell attached, the connector reads
`card1-DP-5=unknown/disabled` and **no** USB devices enumerate behind the port
either; the display's own USB hub is simply absent until the cable is replugged.
Forcing a DRM re-detect does not help, because the link is not up to detect.
There is no `typec` class on this machine at all (`/sys/class/typec` is empty),
so Linux cannot observe the port's alt-mode state or ask it to renegotiate — on
a T2 Mac the USB-C power-delivery controller is owned by the T2, not by the
host. Absent a T2 USB-C/PD driver, a physical replug is the only trigger. `brcmfmac` logs a Wi-Fi Direct interface failure
(`err=-52`) at boot and after every resume; it is cosmetic and the interface
works.

## Do not do these

Learned by breaking the machine.

- **Do not write `auto` to `power_dpm_force_performance_level` in this
  configuration** — see [the scope of that finding](#the-auto-warning-and-its-limits).
  Nine seconds to a dead SMU, then an SDMA ring timeout, then a GPU reset. Being
  idle did not save it.
- Neither `high` nor `low` pins the clock; both are **ceilings**. Read the live
  clock from `hwmon/freq1_input`, never infer it.
- `pp_dpm_sclk` rows change between reads milliseconds apart. It is a sample,
  not state.
- `gpu_busy_percent` cannot drive a clock governor on its own — utilisation
  *falls* when the clock rises, so a naive loop oscillates. Normalise by the
  live clock.
- Do not measure a suspend with kernel or journal timestamps. printk does not
  advance across the sleep and journald stamps its whole backlog at flush. Use
  `CLOCK_BOOTTIME - CLOCK_MONOTONIC`.

## The `auto` warning and its limits

Worth stating precisely, because the warning above is easy to over-read.

**What was actually tested here:** one write of `auto`, with the panel muxed to
the iGPU by `force_igd`, the discrete GPU idle, USB-C unplugged, no outputs, no
CRTC, `gpu_busy_percent=0`. The SMU stopped answering 9 seconds later and the
machine needed a reboot. That is a real, reproducible failure in the topology
this repo sets up, and it is why nothing here ever writes `auto`.

**What was not tested:** `auto` with the discrete GPU actively scanning out. That
run was planned and then cancelled on the reasoning that if `auto` kills an idle
GPU, scanout cannot save it. That was an inference, not a measurement, and it may
well be backwards — continuous scanout could be exactly what keeps the SMU out of
the gated state the transition wedges.

**A counter-example exists.** Another `MacBookPro16,1`, running stock kernel
7.1.8-t2 with no patches and the panel left on the discrete GPU (firmware
default, no `force_igd`), reports `auto` running without trouble — with the dGPU
driving both the internal panel and the externals. That machine is not running
the hybrid topology this repo builds; its iGPU is unused. It is second-hand and
unverified here, but it is enough to say the failure is **conditional on
something**, and the honest candidates are the mux position, the idle state, or
both.

**Practical upshot:** `auto` is not worth pursuing on this setup regardless. It
measured about 16 W on that other machine, while `low` gives 4-5 W here and still
drives 4K@60. The warning stands for this configuration; do not repeat it as a
blanket claim about Navi 14.

## Licence

Kernel patches are GPL-2.0, matching Linux. The aquamarine patch follows
aquamarine's BSD-3-Clause. Scripts and documentation are MIT.
