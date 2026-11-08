# KAIT2EN hybrid candidate — 7.2.8

**Historical experiment:** this candidate is not installed on the current
[7.2.11 setup](KERNEL-7.2.11.md). Its test boot entries have been removed.
The commands below require an explicit 7.2.8 target and matching headers;
the hybrid pin has not been reviewed for 7.2.11.

The first candidate combines Falcon (0001), the Apple AV adapter fix (0004)
and KAIT2EN amdgpu runtime PM (0005), with KAIT2EN's `t2gmux` replacing
`apple_gmux`. It targets `7.2.8-arch1-Watanare-T2-1-t2` only.
Compilation and image inspection are complete. AMD-primary and Intel-primary
boots passed on October 5, including offscreen rendering on both GPUs.
AMD idle power-off and repeated runtime wake cycles remain unvalidated.

## Pinned upstream and local changes

[`kernel/hybrid-upstream.json`](../kernel/hybrid-upstream.json) pins KAIT2EN
to `ed5a3613a49399a8b426850cdde8c3eaf43f71e9`, records the t2gmux source
hash, and identifies the target T2 patch revision. Upstream code and its
authorship remain identified in patch 0005. Three hunks needed adjustments
to surrounding 7.2.8 code. A local error-path fix additionally unwinds
`in_runpm`, MP1 unload state and PX switch state when suspend preparation
fails, sharing the existing suspend-error cleanup.

Falcon's firmware initialization still sends its UCLK rule after feature
enable on boot/reset/resume. KAIT2EN adds MP1 unload before GMUX power-off;
their combination needs repeated hardware runtime suspend/resume tests.

With an exact prepared 7.2.8 source tree and a checkout of the pinned
KAIT2EN repository:

```sh
JOBS=6 tools/build-amdgpu.sh --with-apple-av-adapter --with-hybrid \
    /path/to/exact-kernel-source build/hybrid-amdgpu 7.2.8-arch1-Watanare-T2-1-t2
tools/build-t2gmux.sh /path/to/KaiT2en-Fedora build/hybrid-gmux \
    7.2.8-arch1-Watanare-T2-1-t2
```

Both helpers default to `kernel/target-release` but accept the explicit release
shown above. They build in private directories and record module hashes.
Both reject hybrid targets that differ from the reviewed pin, and the GMUX
helper also rejects source that differs from the reviewed hash.
Neither installs modules or modifies firmware preferences.
Use the isolated module-root/UKI procedure in [INSTALL.md](INSTALL.md).

## First image contents

- Exact installed 7.2.8 kernel, rebuilt amdgpu and pinned t2gmux.
- Known Falcon firmware, SHA-256
  `7a5053cd96e519021830dbd698875c273f63eab67998c9538c09948b8ce250e5`.
- Packaged BCE (all five modules) and cdc_ncm. Our 0002 and 0003 are built
  separately but deliberately excluded from this first image.
- Early module order: t2gmux, i915, amdgpu; stock apple_gmux blocked by kernel
  command line and initramfs modprobe policy. The stock GMUX module is absent
  from the inspected initramfs.
- Existing encrypted-root boot support. No resume hook or resume arguments;
  `nohibernate` disables both creating and restoring hibernation images in
  this test kernel. Do not change that until S4 is separately validated.

This first image follows the firmware's GPU preference. On the reference machine
that was **discrete**, so the first boot was an AMD-display sanity check
of the new kernel/driver combination. It does not yet demonstrate Intel
scanout or AMD idle power-off. KAIT2EN's hybrid setup changes
`gpu-power-prefs` to Intel for a subsequent boot; it is a firmware-wide
preference, not a property of one menu entry. Preserve its original bytes
and establish a working recovery route before making that change.

## October 5 AMD-primary boot result

Boot `878a2e2b-a63e-4975-aad4-0168b6baaf96` ran the exact 7.2.8 image.
All eight embedded module srcversions matched its manifest, including
amdgpu `A3440C90C05A322142FCD20` and t2gmux `3782DDFC8E536B45630EC9E`.
The kernel reported Falcon `0x04350b03`, successful UCLK-rule initialization
and Apple GMUX runtime PM. The AMD internal panel ran at 3072×1920/60 Hz;
PipeWire exposed the speaker sink. The user confirmed that everything tested
worked normally after being asked about screen, input and speaker audio.
External-display hotplug, suspend and AMD offload/power cycles remain untested.

The two SDMA fence fallback messages and Thunderbolt missing-device-link
warnings also occurred on the previous daily boot. No GPU reset, ring timeout
or kernel oops was found in the inspected candidate-boot log. Intel runtime
status was suspended and AMD active, as expected while AMD drives the panel.

## Intel-primary one-boot experiment

A separate image uses the same kernel, firmware and modules, with an early
[`mbp161_gpu_recovery`](../boot/initcpio/mbp161_gpu_recovery) hook. The firmware
preference is saved, Intel is selected for the next boot, and Limine selects
the new test image through `LoaderEntryOneShot`. The persistent default stays
on the working daily image.

Once the test initramfs starts, the hook restores the AMD preference before
udev and the graphics modules load. Firmware has already routed the display
for the current boot; restoring the preference prepares later boots rather
than performing a live display switch. The hook requires the explicit
`rd.mbp161.restore_discrete=1` argument and exact MacBookPro16,1/variable
values. It logs the result and verifies the eight-byte preference readback.
If boot fails before reaching this hook, automatic restoration cannot run.

The initial image was checked for hook order, command line, recovery values
and unchanged module/firmware hashes, but its dependency check missed `cmp`:
mkinitcpio's BusyBox does not provide it. The first Intel boot therefore left
the Intel preference set. It was restored manually after inspection.

Revision 2 explicitly embeds both `/usr/bin/cmp` and `/usr/bin/chattr`.
Tests run inside a private copy of the extracted image with ordinary files
standing in for EFI and a mocked chattr, without mounting host filesystems.
They cover restoration, already-discrete state, unexpected bytes, wrong model,
unlock failure, missing opt-in and reproduction of the original missing-cmp
failure. These checks prevent borrowing missing commands from the host PATH.
Actual early-boot EFI writeback still needs verification on the next boot.
Hibernation remains disabled.

## October 5 Intel-primary result and idle blocker

Boot `36a5bf5c-1fc0-492c-9551-225cc9f97310` drove the internal panel through
Intel at 3072×1920/60 Hz and a Dell S2722QC through AMD DP-6 at 3840×2160/60 Hz.
Hyprland's DRM engine counters confirm Intel rendering. An EGL pbuffer test
explicitly selected each PCI GPU, performed 120 clears and verified the
pixel readback: both Intel UHD 630 and AMD Navi14 passed. This verifies
rendering, not a runtime wake from a powered-off GPU.

After the user disconnected the Dell, Hyprland removed the output and
released its secondary renderer, but kernel DRM state retained AMD CRTC 92
as active at 3840×2160 with a Hyprland framebuffer. amdgpu's runtime-PM checks
reject suspend while a CRTC is active. AMD consequently remained active;
this is not evidence that GMUX power-off itself failed.

The then-installed Aquamarine 0.15.0-2 has a closely matching upstream report,
[#386](https://github.com/hyprwm/aquamarine/issues/386), fixed by
[#410](https://github.com/hyprwm/aquamarine/pull/410), merged September 15.
That fix explicitly releases the output during disconnect. It was not
installed in this experiment. Omarchy 4.5 subsequently installed Aquamarine
0.15.1-1, but external-display unplug/replug has not been retested on the
current AMD-primary setup. First establish idle/wake behavior
with an internal-screen-only boot, then evaluate the userspace fix for
external-display unplug/replug. No compositor or desktop configuration was
changed during these tests.

## BCE rebase: built, excluded from the first image

Patch 0003 now preserves the packaged USB stateful reset-resume, no-state
preparation/error propagation and PCM workqueue/timing changes. The old
playback timer workaround is superseded. The local SUSPEND trigger, audio
card lifetime, S4 queue reconstruction and loader handoff remain.

The rebase also serializes command-ring resets against the new completion
mutex, drains command DMA before loader sign-on and re-enables the submission
gate after restore. The PCM workqueue survives until the disconnected ALSA
card's last user closes it.

The failure path where VHCI unregister and firmware revoke both fail still
needs a design that protects URB payloads as well as queue rings. This is an
open correctness issue, not a successful fault-injection result. See
[hibernation limitations](HIBERNATION.md). Keep the rebase out of the first
graphics image; S4 hardware tests remain deferred.

## Verification performed

- Linux and Arch source hashes match the installed package recipe; its
  PKGBUILD hash matches `.BUILDINFO`. Packaged T2 patches apply without fuzz.
- All five repository patches apply without fuzz in numeric order. All 27
  changed files match the compiled sources byte-for-byte.
- Eight modules compile with the exact target vermagic: amdgpu, t2gmux,
  cdc_ncm and five BCE modules. The new GMUX build helper was exercised too.
- The extracted UKI kernel, command line, firmware and all eight embedded
  modules match their intended inputs. BCE/NCM hashes match the packaged
  modules, rather than the separately built alternatives.
- Build tooling reports pahole 131 versus the kernel's 132. Initramfs
  generation warns about optional `qat_6xxx` firmware. These warnings are
  recorded; they are not substitutes for a successful boot test.

## Hardware test order

1. Select the additional 7.2.8 graphics test entry manually. Check internal
   display, LUKS input, desktop, audio and external-display hotplug. Confirm
   the loaded module srcversions match the image manifest.
2. After that sanity check, select Intel as the firmware boot preference and
   boot this candidate again. Confirm Intel scanout, AMD render offload,
   repeated AMD idle/wake and external-display wake. Avoid polling tools that
   themselves wake the AMD GPU when measuring idle power.
3. Check lid/suspend/resume and internal Ethernet with packaged USB resume
   handling. Only add 0002 for a separate comparison if it is still needed.
4. Resolve the BCE teardown failure path, then build and test an S4 image
   separately. Historical 7.2.6 restore counts do not validate this rebase.

The first image does not change desktop configuration or require the
experimental Titan Ridge series. A full kernel build for that series remains
a separate experiment.
