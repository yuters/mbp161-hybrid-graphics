# Kernel patches

Five patches, applied in order on top of **Linux 7.2 with the
[t2linux](https://wiki.t2linux.org/) v7.2-rc6 patch stack**.

| | |
|---|---|
| `0001` | `platform/x86: apple-gmux` — switch the panel mux to the iGPU before either DRM driver binds, dropping the firmware framebuffer first. Exports `apple_gmux_panel_is_igd()`. |
| `0002` | `drm/amdgpu` — skip in-kernel fbdev when the panel is muxed to the iGPU. |
| `0003` | `drm/amd/display` — skip detect, HPD, polling and EDID on the internal eDP while it is muxed away (the "ghost eDP"). |
| `0004` | `PCI/PM` — leave the two MacBookPro16,1 AMD functions untouched across s2idle. |
| `0005` | `PCI` + `thunderbolt` + `xhci` — drive Apple's native Titan Ridge power sequence across s2idle, so both USB-C controllers suspend and resume properly instead of being pinned in D0. |

All five are gated on `apple_gmux_panel_is_igd()` or on an explicit DMI match
plus exact PCI IDs, so they are inert on other hardware.

## 0004 and 0005, and why 0004 shrank

`0004` originally covered **six** functions: the two AMD ones and both Titan
Ridge USB-C controllers. Pinning the USB-C controllers in D0 across s2idle
worked, but it is an avoidance, not a fix — it blocks Thunderbolt power
management entirely and leaves both controllers burning power in D0 while the
machine sleeps.

`0005` replaces that half with the sequence macOS actually performs, taken from
`AppleThunderboltNHIType3` and cross-checked against the machine's own AML:

| phase | call | where |
|---|---|---|
| down | xHCI `RTPC(0)` | `xhci_pci_suspend()` |
| | NHI Go2Sx mailbox, NHI `RTPC(0)` | `apple_tr_nhi_suspend_noirq()` |
| | `NHI0.SXFP(0)`, `NHI0.XRST(1)` | root-port `suspend_late` fixup |
| up | `NHI0.XRST(0)`, `NHI0.TRPE(1, 0)` | root-port `resume_early` fixup |
| | NHI `RTPC(1)` | `apple_tr_nhi_resume_noirq()` |
| | xHCI `RTPC(1)` | `xhci_pci_resume()` |

Three details were each established by measurement rather than by reading:

- **Both `RTPC` votes are load-bearing.** NHI `RTPC` writes `PEGn.RTBT`, xHCI
  `RTPC` writes `PEGn.RUSB`, and the upstream switch's `POFF()` is
  `!RTBT && !RUSB`. `RUSB` defaults to `One`, so without the xHCI half `POFF()`
  never becomes true and firmware refuses to release power.
- **`SXFP(0)` must run from the root port, not the NHI.** It drives GPIO
  `0x03050007` low, which takes the whole subtree off the bus. The PCI core still
  has to walk the NHI and three bridges above it into D3hot afterwards; issuing
  it from the NHI's `suspend_noirq` makes all of them fail with `Unable to
  change power state from D0 to D3hot`. `DECLARE_PCI_FIXUP_SUSPEND_LATE` on the
  root port runs at the `Fixup:` label of `pci_pm_suspend_noirq()` — after that
  port's own D-state change and after everything below it has suspended.
- **The Go2Sx mailbox is not answered here, and that is expected.** It is served
  by a firmware connection manager; Linux runs the software CM on Apple hardware
  (`icm.c` refuses `x86_apple_machine`). `tb_switch_suspend()` has already set
  `TB_LC_SX_CTRL_SLP` on every link controller over the control channel, which is
  the same notification by another route — mainline's `icl_nhi_suspend_noirq()`
  skips the mailbox for exactly that reason. The command is still sent because
  Apple sends it; the timeout is logged, not treated as an error.

**Falling back.** `mbp161_tb_type3` defaults to on. To restore the old
pin-in-D0 behaviour exactly, boot with:

```
mbp161_tb_type3=0 mbp161_tb_bypass=1
```

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
- **0004** — six bypass markers in a device-callback gate (that build still
  included the Titan Ridge functions; `0005` has since taken them over), then a
  real 36.75 s
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

### 0005, measured (2026-08-30/31)

Six `pm_test=platform` cycles and one real **123.7 s** s2idle, every one with
**zero** Titan Ridge PM failures in the kernel log. For comparison, the same
machine without `0005` and without the old bypass produces 24 such lines in a
single cycle.

- `TRPE(1, 0)` acquired `PEGn.UPSB.AVND` on the **first attempt every time**, in
  72.0–72.3 ms, with no drift across repeats and no power-cycle retries.
- `xhci_pci_resume()` returned success on both controllers each time (the
  `RTPC(1)` marker is only emitted on success).
- Both controllers then reached **D3cold on their own** when idle — power
  management the previous pin-in-D0 bypass could never allow. Note that a
  runtime-suspended controller reads `ffffffff` from raw config space; that is
  the feature working, not a dead device. Ask the PM core, not `setpci`.

**Not verified for `0005`:** suspend with a device or display attached to a
USB-C port. Every measurement above ran with both ports empty. The older
pin-in-D0 approach *was* verified attached, so this is a genuine gap and the
reason the fallback above is documented rather than removed.

## Not included, on purpose

The research tree these came from also contains gmux Config3 / D3cold power
sequencing, debugfs research hooks, tracing, and a gmux runtime-PM gate. None of
it made the machine better and some of it can hang it. It is not here.

`0005`'s development also produced four alternative ACPI sequences behind a
`mbp161_tb_acpi` selector, built around `TBTC`/`UTLK`/`ICMB`/`SXEX`. Disassembly
of `AppleThunderboltNHI` showed macOS never calls any of those four methods, and
two of the modes hard-froze the machine. They are not here either.
