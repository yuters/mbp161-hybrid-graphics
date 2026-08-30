# Kernel patches

Four patches, applied in order on top of **Linux 7.2 with the
[t2linux](https://wiki.t2linux.org/) v7.2-rc6 patch stack**.

| | |
|---|---|
| `0001` | `platform/x86: apple-gmux` — switch the panel mux to the iGPU before either DRM driver binds, dropping the firmware framebuffer first. Exports `apple_gmux_panel_is_igd()`. |
| `0002` | `drm/amdgpu` — skip in-kernel fbdev when the panel is muxed to the iGPU. |
| `0003` | `drm/amd/display` — skip detect, HPD, polling and EDID on the internal eDP while it is muxed away (the "ghost eDP"). |
| `0004` | `PCI/PM` — leave six MacBookPro16,1 PCI functions untouched across s2idle. |

All four are gated on `apple_gmux_panel_is_igd()` or on an explicit DMI match
plus exact PCI IDs, so they are inert on other hardware.

## Verification status

**Verified:** all four apply cleanly with `patch -p1` to a pristine t2linux
v7.2-rc6 tree, and every file they touch compiles from that tree —
`apple-gmux.o`, `pci-driver.o`, `amdgpu_drv.o`, and the whole
`drivers/gpu/drm/amd/display/amdgpu_dm/` directory.

**A kernel built from exactly these four patches has been booted and used.**
2026-08-29: a fresh tree at the t2linux v7.2-rc6 base with only these four
patches applied, built with zero errors, packaged, installed alongside the
research kernel and booted. Verified on that build:

- **0001** — booted with `apple_gmux.force_igd=1` and **no**
  `modprobe.blacklist=amdgpu`. Both GPUs bound (`00:02.0` i915, `03:00.0`
  amdgpu), internal panel lit, `apple_gmux: Switching to IGD` logged. This is
  the direct test: without the patch, that same configuration races i915 against
  amdgpu and lands on a grey screen with a plymouth/PID-1 crash.
- **0002** — `Skipping in-kernel fbdev: gmux panel on IGD, compositor owns KMS`.
- **0003** — `Skipping eDP detect: gmux panel is owned by IGD`; `card1-eDP-2`
  stays `disconnected`.
- **0004** — six bypass markers in a device-callback gate, then a real 36.75 s
  s2idle **with the external display attached**: every captured field identical
  across the sleep, no amdgpu/SMU/xHCI/i915 error, no `WARNING:`/`BUG:`/`Call
  Trace`, both displays live at full resolution on resume.
- The compositor came up Intel-primary with AMD secondary at an ordinary login,
  drove `DP-5` at 3840x2160@60, and logged **zero** `drmModeAddFB2WithModifiers`
  or buffer-submit failures — so the aquamarine patch is exercised on this build
  too.
- No research code reached the binaries; the kernel log contains none of the
  research tree's markers.

**Note on 0002.** The version that first ran on the reference machine also
tested `adev->pm.rpm_mode == AMDGPU_RUNPM_GMUX`. That enum belongs to the
research tree, not upstream, so the condition was dropped here — redundant
anyway, since `apple_gmux_panel_is_igd()` is false unless apple-gmux is bound
with the mux on the iGPU. **The version in this repo is now the version that has
been booted and tested**, which was not true when this file was first written.

## Not included, on purpose

The research tree these came from also contains gmux Config3 / D3cold power
sequencing, debugfs research hooks, tracing, and a gmux runtime-PM gate. None of
it made the machine better and some of it can hang it. It is not here.
